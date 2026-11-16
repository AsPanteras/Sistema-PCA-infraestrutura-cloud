## 1. Contexto e objetivo

A aplicação mantém o **histórico integral** dos dados (ADR 001 e seção 1.1 de `arquitetura.md`) e roda com backend e PostgreSQL em contêineres Docker numa **única instância EC2** (`t3.medium`, EBS gp3 de 30 GB, sub-rede privada). A tabela de riscos (seção 9.1) já aponta a *perda de dados* como risco: uma falha de disco ou a remoção do contêiner sem backup perde o banco.

Esta parte tem duas políticas com papéis diferentes:

| Política | Papel | Entrega |
|---|---|---|
| **Conservadora (GFS)** | O que o grupo recomendaria para operar a aplicação de verdade | Apenas o plano, com análise de custos para 12 meses |
| **Mínima** | Exercitar na prática os mecanismos de backup com custo próximo de zero | Configurada na nuvem e apresentada |

### 1.1. O que precisa ser protegido

| Dado | Onde está | Pode ser recriado? | Precisa de backup? |
|---|---|---|---|
| Licitações sincronizadas do Portal da Transparência (~3.500, +~200/ano) | Banco PostgreSQL | Em tese sim, pela API pública (se ela mantiver o histórico) | Sim, para evitar depender da API para restaurar |
| PCAs, andamentos, justificativas de atraso | Banco PostgreSQL | **Não**: são dados próprios do setor | **Sim, é o dado mais crítico** |
| Registros de auditoria e log das sincronizações | Banco PostgreSQL | **Não** | **Sim** |
| Usuários e perfis | Banco PostgreSQL | Parcialmente | Sim |
| Código, `docker-compose`, IaC | Repositório Git | Sim | Já protegido pelo Git |
| Segredos (`.env`, chave JWT, senha do banco) | Instância | Não | **Fora do dump**: guardar em local próprio (ex.: Secrets Manager) |

> Conclusão: o alvo principal é o **banco de dados**. O restante da instância é reconstruível por IaC.

### 1.2. Metas de recuperação (RPO e RTO)

A arquitetura desta entrega é de alta disponibilidade (duas zonas de disponibilidade, ALB e banco RDS PostgreSQL Multi-AZ com replicação síncrona). Alta disponibilidade e backup protegem contra falhas diferentes, por isso as metas são definidas por cenário:

| Cenário | Mecanismo | RPO (dado que se aceita perder) | RTO (tempo para voltar) |
|---|---|---|---|
| Falha de instância ou de uma zona de disponibilidade | Alta disponibilidade: failover automático do RDS Multi-AZ e backend/frontend na outra zona | Praticamente zero (replicação síncrona) | Poucos minutos (estimativa de 1 a 2 minutos para o failover do banco) |
| Erro lógico: exclusão ou corrupção de dados, deploy defeituoso, ataque | Backup: restauração do dump do S3 (política GFS) | Até 24 horas (backup diário) | Algumas horas (criar ou preparar o banco, baixar o dump e executar o `pg_restore`; valor a medir no teste de restauração) |
| Perda da região ou da conta | Fora do escopo desta entrega | - | - |

A replicação síncrona **não substitui o backup**: ela copia para a réplica qualquer alteração, inclusive um erro. O backup é a única forma de voltar a um estado anterior. O RTO do cenário de backup será medido no teste de restauração trimestral e atualizado neste documento.

## 2. Política conservadora (GFS): apenas o plano

GFS (avô-pai-filho) é um esquema de rotação de backups organizado em gerações com frequências e retenções diferentes. As cópias recentes ficam disponíveis em grande número, e as antigas são mantidas de forma espaçada. Assim é possível voltar a qualquer dia da última semana, a qualquer semana do último mês e a qualquer mês do último ano, sem guardar uma cópia de cada dia do ano.

| Geração | Frequência | Retenção | Permite restaurar |
|---|---|---|---|
| **Son (filho)** | Diária | 7 dias | Qualquer dia da última semana |
| **Father (pai)** | Semanal (domingo) | 4 a 5 semanas | Qualquer semana do último mês |
| **Grandfather (avô)** | Mensal (dia 1) | 12 meses | Qualquer mês do último ano |

No máximo **24 cópias** ao mesmo tempo (7 + 5 + 12). Na prática menos, porque o backup semanal pode ser a própria cópia diária de domingo.

### 2.1. Desenho técnico proposto

**Camada 1: backup lógico (principal).** Um `pg_dump` em formato custom (`-Fc`, já comprimido) executado por agendador na EC2 e enviado ao S3:

```
s3://pca-backup-<sufixo>/
  daily/    pca-AAAA-MM-DDThhmmssZ.dump   -> expira em 7 dias
  weekly/   pca-AAAA-MM-DDThhmmssZ.dump   -> expira em 35 dias
  monthly/  pca-AAAA-MM-DDThhmmssZ.dump   -> expira em 365 dias (ou conforme auditoria, seção 4)
```

* O script grava sempre em `daily/`; aos domingos copia também para `weekly/`; no dia 1 copia também para `monthly/`. A **rotação (apagar o que venceu) é feita por regras de ciclo de vida do S3**, sem script próprio.
* Bucket com **bloqueio de acesso público**, **criptografia SSE-S3** e **versionamento** ligado (protege contra apagar ou sobrescrever por engano).
* Acesso por **perfil IAM da instância** (sem chave de acesso no servidor), com permissão só de escrita no bucket e, para o usuário que restaura, leitura.
* **Endpoint de VPC do tipo Gateway para o S3** (sem custo por hora nem por GB): o tráfego de backup não passa pelo NAT Gateway, não paga o processamento dele e continua funcionando se o NAT falhar (risco já listado na seção 9.1).

**Camada 2: snapshot do volume EBS (complementar).** Snapshot semanal do volume de 30 GB, com Amazon Data Lifecycle Manager, retenção de 5 cópias. Serve para recompor a máquina inteira (SO, Docker, volumes) mais rápido do que reconstruir por IaC e restaurar o dump. É opcional: se o grupo aceitar reconstruir pela IaC, a camada 1 basta.

**Teste de restauração.** Uma vez por trimestre, restaurar o último dump mensal num contêiner PostgreSQL temporário e conferir contagens (PCAs, licitações, usuários). Backup que nunca foi restaurado não é garantia.

### 2.2. Análise de custos para 12 meses

---

## 3. Política mínima: configurada na nuvem e apresentada

**Objetivo:** exercitar o ciclo completo (gerar, guardar, expirar, restaurar) com custo próximo de zero.

### 3.1. Estrutura:
  
A estrutura mínima proposta:

| Componente | O que é | Por que entra |
|---|---|---|
| **Dump do PostgreSQL** (`pg_dump -Fc`) | Arquivo único com todos os dados do sistema | É onde estão os dados que não se recriam (seção 1.1) |
| **Bucket S3** | Armazenamento de objetos para os dumps | Fora da instância: sobrevive à perda da EC2 e à destruição do ambiente |
| **Regra de ciclo de vida** | Expira os dumps antigos e também as versões não atuais | Demonstra a rotação (em escala reduzida) e evita custo escondido do versionamento |
| **Perfil IAM** da instância | Permissão mínima de escrita no bucket | Sem chaves de acesso gravadas no servidor |
| **Teste de restauração** | `pg_restore` num contêiner temporário | Prova que o backup serve |

Fica de fora, de propósito, na política mínima: snapshots EBS, replicação entre regiões e backup de segredos (seguem descritos no plano conservador).

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
