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
