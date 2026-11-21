## 1. Contexto e objetivo

A arquitetura desta entrega é de **alta disponibilidade**: duas zonas de disponibilidade (`us-east-2a` e `us-east-2b`), ALB na frente do frontend (ECS), backend em duas instâncias EC2 em sub-redes privadas e banco **Amazon RDS PostgreSQL Multi-AZ** com replicação síncrona entre uma instância primária e uma standby.

Alta disponibilidade e backup protegem contra falhas diferentes. A replicação do Multi-AZ mantém o sistema no ar quando uma instância ou uma zona falha, mas **copia para a réplica qualquer alteração, inclusive um erro**: um `DELETE` indevido, uma migração defeituosa ou uma corrupção de dados chegam à standby em instantes. O backup é a única forma de **voltar a um estado anterior**. Por isso a tabela de riscos continua exigindo backup (risco de perda de dados e de erro lógico), mesmo com Multi-AZ.

Configurar uma política de backup completa geraria custo durante meses, o que não faz sentido para um ambiente acadêmico. Por isso esta parte tem duas políticas com papéis diferentes:

| Política | Papel | Entrega |
|---|---|---|
| **Conservadora (GFS)** | O que o grupo recomendaria para operar a aplicação de verdade | Apenas o plano, com análise de custos para 12 meses |
| **Mínima** | Exercitar na prática os mecanismos de backup com custo próximo de zero | Configurada na nuvem e apresentada |

### 1.1. O que precisa ser protegido

| Dado | Onde está | Pode ser recriado? | Precisa de backup? |
|---|---|---|---|
| Licitações sincronizadas do Portal da Transparência (~3.500, +~200/ano) | Banco (RDS) | Em tese sim, pela API pública (se ela mantiver o histórico) | Sim, para não depender da API para restaurar |
| PCAs, andamentos, justificativas de atraso | Banco (RDS) | **Não**: são dados próprios do setor | **Sim, é o dado mais crítico** |
| Registros de auditoria e log das sincronizações | Banco (RDS) | **Não** | **Sim** |
| Usuários e perfis | Banco (RDS) | Parcialmente | Sim |
| Código, `docker-compose`, IaC, imagens | Repositório Git e ECR | Sim | Já protegido pelo Git e pelo ECR |
| Segredos (senha do banco, chave JWT) | Variáveis de ambiente ou gerenciador de segredos | Não | **Fora do dump**: guardar em local próprio (ex.: Secrets Manager ou cofre do grupo) |

> Conclusão: o alvo do backup é o **banco de dados**. As instâncias EC2 e o frontend são reconstruíveis por IaC.

### 1.2. Metas de recuperação (RPO e RTO)

Como a arquitetura é de alta disponibilidade, as metas são definidas **por cenário**:

| Cenário | Mecanismo | RPO (dado que se aceita perder) | RTO (tempo para voltar) |
|---|---|---|---|
| Falha de instância ou de uma zona de disponibilidade | Alta disponibilidade: failover automático do RDS Multi-AZ; frontend e backend continuam na outra zona | Praticamente zero (replicação síncrona) | Poucos minutos (estimativa de 1 a 2 minutos para o failover do banco) |
| Erro lógico: exclusão ou corrupção de dados, deploy defeituoso, ataque | Backup: restauração do dump guardado no S3 (política GFS) | Até 24 horas (backup diário) | Algumas horas (preparar o banco, baixar o dump e executar o `pg_restore`; valor a medir no teste de restauração) |
| Perda da região ou da conta AWS | Fora do escopo desta entrega | - | - |

A replicação síncrona **não substitui o backup**. O RTO do cenário de backup será medido no teste de restauração (seção 2.1) e atualizado neste documento com o valor real.

---

## 2. Política conservadora (GFS): apenas o plano

GFS (avô-pai-filho) é um esquema de rotação de backups organizado em gerações com frequências e retenções diferentes. As cópias recentes ficam disponíveis em grande número, e as antigas são mantidas de forma espaçada. Assim é possível voltar a qualquer dia da última semana, a qualquer semana do último mês e a qualquer mês do último ano, sem guardar uma cópia de cada dia do ano.

| Geração | Frequência | Retenção | Permite restaurar |
|---|---|---|---|
| **Son (filho)** | Diária | 7 dias | Qualquer dia da última semana |
| **Father (pai)** | Semanal (domingo) | 4 a 5 semanas | Qualquer semana do último mês |
| **Grandfather (avô)** | Mensal (dia 1) | 12 meses | Qualquer mês do último ano |

No máximo **24 cópias** ao mesmo tempo (7 + 5 + 12). Na prática menos, porque o backup semanal pode ser a própria cópia diária de domingo.

### 2.1. Desenho técnico proposto

**Backup lógico (principal).** Um `pg_dump` em formato custom (`-Fc`, já comprimido) executado por agendador (`cron`) numa das EC2 de aplicação, que se conecta ao RDS pela porta 5432 e envia o arquivo ao S3. O RDS não grava no S3 por conta própria: quem executa o `pg_dump` é uma máquina cliente dentro da VPC.

```
s3://pca-backup-<sufixo>/
  daily/    pca-AAAA-MM-DDThhmmssZ.dump   -> expira em 7 dias
  weekly/   pca-AAAA-MM-DDThhmmssZ.dump   -> expira em 35 dias
  monthly/  pca-AAAA-MM-DDThhmmssZ.dump   -> expira em 365 dias
```

* O script grava sempre em `daily/`; aos domingos copia também para `weekly/`; no dia 1 copia também para `monthly/`. A **rotação (apagar o que venceu) é feita por regras de ciclo de vida do S3**, sem script próprio.
* Bucket com **bloqueio de acesso público**, **criptografia SSE-S3** e **versionamento** ligado (protege contra apagar ou sobrescrever por engano). Com o versionamento ligado, cada regra de ciclo de vida precisa expirar **também as versões não atuais** (ex.: apagar definitivamente 1 dia depois de deixarem de ser a versão atual). Sem isso, a expiração só cria "marcadores de exclusão" e os dumps antigos continuam ocupando espaço e gerando custo para sempre.
* Acesso por **perfil IAM da instância** (sem chave de acesso no servidor), com permissão só de escrita no bucket e, para quem restaura, leitura.
* O grupo de segurança do banco (`sg-db`) precisa permitir entrada na porta 5432 a partir do `sg-app` (já necessário para a aplicação). A senha do banco vem de variável de ambiente protegida ou do Secrets Manager, nunca escrita no script.
* **Endpoint de VPC do tipo Gateway para o S3** (sem custo por hora nem por GB), associado às tabelas de rota das **duas** sub-redes privadas: o tráfego de backup não passa pelos NAT Gateways, não paga o processamento deles e continua funcionando se um NAT falhar.
* Limitação: o agendamento roda em uma única EC2. Se a zona dessa instância cair, o backup diário daquele dia não é feito. Para o escopo da entrega isso é aceito; a evolução natural é usar o AWS Backup ou uma tarefa agendada do ECS.

**Backup nativo do RDS (complementar, opcional).** O RDS mantém backups automáticos com restauração para um ponto no tempo. Habilitá-los reduz o RPO do cenário de erro lógico de 24 horas para alguns minutos. Fica como melhoria recomendada, fora da estimativa de custos desta entrega (o custo de armazenamento do backup automático deve ser conferido na Calculadora da AWS junto com o orçamento do RDS).

**Teste de restauração.** Uma vez por trimestre, restaurar o último dump mensal num contêiner PostgreSQL temporário e conferir contagens (PCAs, licitações, usuários). Backup que nunca foi restaurado não é garantia. O tempo gasto alimenta o RTO da seção 1.2.

### 2.2. Análise de custos para 12 meses

**Premissas**:

* Tamanho de cada dump comprimido: cerca de **200 MB** (margem de folga: a base atual tem cerca de 3.500 licitações e 150 a 210 itens de PCA por ano, então o dump real tende a ser bem menor).
* 24 cópias simultâneas (teto da política): 24 x 200 MB = 4,8 GB, arredondado para **5 GB** na Calculadora da AWS.
* **Todas as gerações (filho, pai e avô) em S3 Standard**, na região `us-east-2` (Ohio). Justificativa na seção 4.
* Preço de lista do S3 Standard: US$ 0,023 por GB-mês (valor de referência de 2026; **o valor oficial é o que aparece na Calculadora**).

| Item | Cálculo | Custo |
|---|---|---|
| Armazenamento (S3 Standard, 5 GB) | 5 GB x US$ 0,023 | ~US$ 0,12/mês |
| Requisições (~30 PUT/mês, mais as cópias semanais e mensais) | ~US$ 0,005 por 1.000 | < US$ 0,01/mês |
| Endpoint de VPC do tipo Gateway para o S3 | gratuito | US$ 0 |
| **Total em 12 meses** | ~US$ 0,12 x 12 | **~US$ 1,40** |

Leitura do resultado:

* O custo do backup é **desprezível frente ao restante da arquitetura**. Os custos do RDS Multi-AZ, do ALB e dos NAT Gateways pertencem à seção de estimativa de custos da arquitetura e são muito maiores. A política conservadora acrescenta cerca de **US$ 1,40 por ano** e não altera de forma relevante os totais dos cenários de 730 h e de 10 h.
* O custo **não** é o critério para escolher a classe de armazenamento (seção 4): para o grupo de avôs (12 cópias, cerca de 2,4 GB no teto), passar do Standard para o Glacier Instant Retrieval economiza centavos por mês.
* Custos que dominariam a conta, se existissem, seriam transferência de saída (restaurar para fora da AWS) e retrieval das classes frias. Com dumps desse tamanho, restaurar custa centavos.

---

## 3. Política mínima: 

**Objetivo:** exercitar o ciclo completo (gerar, guardar, expirar, restaurar) com custo próximo de zero.

### 3.1. Estrutura:
  
A estrutura mínima proposta:

| Componente | O que é | Por que entra |
|---|---|---|
| **Dump do PostgreSQL** (`pg_dump -Fc`) | Arquivo único com todos os dados do sistema | É onde estão os dados que não se recriam (seção 1.1) |
| **Bucket S3** | Armazenamento de objetos para os dumps | Fora da VPC e do banco: sobrevive à perda das instâncias e à destruição do ambiente |
| **Regra de ciclo de vida** | Expira os dumps antigos e também as versões não atuais | Demonstra a rotação (em escala reduzida) e evita custo escondido do versionamento |
| **Perfil IAM** da instância | Permissão mínima de escrita no bucket | Sem chaves de acesso gravadas no servidor |
| **Teste de restauração** | `pg_restore` num contêiner temporário | Prova que o backup serve |

Fica de fora, de propósito, na política mínima: backup automático do RDS com restauração para um ponto no tempo, replicação entre regiões e backup de segredos (seguem descritos no plano conservador).

### 3.4. Custo

Poucos dumps de ~50 MB por poucos dias: **abaixo de US$ 0,01 por mês** de armazenamento e requisições.

## 4. Auditoria e escolha do tipo de armazenamento

**Decisão do grupo:** manter **todas as cópias da política GFS no S3 Standard**, sem regras de arquivamento em Glacier. O sistema é de uso interno, serve ao planejamento e ao acompanhamento do PCA, e os dados oficiais são os publicados no portal. O custo é irrisório e a restauração é imediata em caso de falha.

**Premissa assumida:** os dados produzidos no sistema (andamentos, justificativas, registros de auditoria) são protegidos pelo backup, mas **não há exigência de retenção por prazo superior a 12 meses** nem de arquivamento imutável. Se a prefeitura ou o controle interno indicarem o contrário, esta decisão deve ser revista conforme a tabela abaixo. A premissa deve ser confirmada com a P.O.

A escolha entre S3 Standard e as classes Glacier **não é decisão de custo** e sim de **requisito de retenção e de acesso**. A pergunta que decide:

> Os dados produzidos no sistema PCA (andamentos, justificativas, registros de auditoria, usuários) se enquadram em uma política de auditoria e retenção do município, ou apenas os dados publicados no portal oficial?

| Resposta | Consequência para o backup |
|---|---|
| **Só o publicado no portal está sujeito a auditoria** | Os dados do sistema são ferramenta interna. Basta o GFS da seção 2, tudo em **S3 Standard** (ou Standard-IA para os mensais). Glacier não se justifica. |
| **Os dados do sistema entram em auditoria, com retenção maior que 12 meses** | Manter o GFS para recuperação operacional e **acrescentar uma cópia anual (ou mensal) em arquivo** pelo prazo exigido: **Glacier Instant Retrieval** se a consulta precisa ser imediata, **Deep Archive** se puder esperar horas. Se houver exigência de imutabilidade, avaliar o **S3 Object Lock**. |

Por que **não** usar Glacier para as gerações filho e pai:

* As classes Glacier têm **tempo mínimo de cobrança** (90 dias no Instant e no Flexible Retrieval, 180 dias no Deep Archive). Um dump que vive 7 dias seria cobrado por 90 ou 180.
* Elas cobram **por GB restaurado** e, nas mais frias, exigem **horas de espera** (de 12 a 48 horas conforme o tipo). Para restaurar "o backup de ontem" depois de uma falha, isso é ruim para o RTO.
* Nas classes Flexible Retrieval e Deep Archive, cada objeto carrega ~40 KB de metadados, o que pesa quando os arquivos são pequenos.

## 5. Resumo das decisões propostas

* Dump lógico do PostgreSQL (`-Fc`) executado por uma EC2 de aplicação contra o RDS, enviado a um bucket S3 próprio, **fora da pilha destruída** pelo IaC.
* GFS por **prefixos + regras de ciclo de vida** (7 / 35 / 365 dias), sem script de rotação, expirando também as versões não atuais.
* Acesso por perfil IAM e **endpoint Gateway do S3** nas duas sub-redes privadas (sem NAT, sem custo).
* **S3 Standard em todas as gerações**, com a premissa de auditoria registrada na seção 4.
* **RPO e RTO por cenário** (seção 1.2): alta disponibilidade cobre falha de infraestrutura; o backup cobre erro lógico.
* **Teste de restauração** como parte da política, não como extra; ele mede o RTO real.
* Backup automático do RDS (restauração para um ponto no tempo) como melhoria recomendada.

## 6. Riscos e limitações do plano

* O backup fica na mesma região (`us-east-2`). O S3 já replica entre zonas, o que cobre a falha de zona, mas **não** cobre a falha de região (replicação entre regiões é possível, com custo adicional pequeno para este volume).
* Dump lógico é uma foto no momento da execução: com RPO de 24 h, até um dia de andamentos e justificativas pode ser perdido em caso de erro lógico (as licitações sincronizadas voltam pela rotina). O backup automático do RDS reduz esse risco.
* O agendamento do backup roda em uma única EC2 (seção 2.1).
* Segredos e variáveis de ambiente não estão no dump e precisam de guarda própria.
