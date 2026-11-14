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

### 1.2. Metas de recuperação (premissas do grupo) <!--verificar as metas de recuperação>
* **RPO (quanto de dado se aceita perder): até 24 horas.**
* **RTO (quanto tempo para voltar): algumas horas.**

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