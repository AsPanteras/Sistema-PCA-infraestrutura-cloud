# Proposta de arquitetura de alta disponibilidade

## 1. Visão geral

Esta proposta evolui a arquitetura implantada na Entrega 1 (uma única zona de disponibilidade, uma EC2 com aplicação e banco, um NAT e um bastion) para uma arquitetura distribuída em **duas zonas de disponibilidade** (`us-east-2a` e `us-east-2b`) da região `us-east-2`, sem ponto único de falha nos caminhos críticos de usuário.

Resumo das mudanças em relação à Entrega 1:

| Componente | Entrega 1 (implantada) | Proposta de alta disponibilidade |
|---|---|---|
| Zonas de disponibilidade | 1 (`us-east-2a`) | 2 (`us-east-2a` e `us-east-2b`) |
| Entrada de tráfego | Frontend ECS com IP público | ALB público + frontend ECS (um por AZ) |
| Backend | 1 EC2 (`t3.medium`) | 2 EC2 (`t3.medium`), uma por AZ, atrás de um ALB interno |
| Banco de dados | Container PostgreSQL na mesma EC2 da aplicação | RDS PostgreSQL Multi-AZ (primário + standby) |
| NAT Gateway | 1 | 1 por AZ |
| Bastion host | 1 | 1 por AZ |
| Backup | Não há | Backups automáticos do RDS e `pg_dump` para S3 |
| Arquivos enviados | Disco da EC2 | Bucket S3 (ver seção 7) |

## 2. Diagrama

![Diagrama alta-disponibilidade](diagramas/diagrama-pca-ha.drawio.png)

## 3. Plano de endereçamento

VPC `vpc-pca` com CIDR `10.0.0.0/16`. Os CIDRs da Entrega 1 (`10.0.10.0/24` e `10.0.20.0/24`) foram mantidos na AZ `us-east-2a`, e as demais sub-redes foram adicionadas sem sobreposição.

| Camada | us-east-2a | us-east-2b | Conteúdo |
|---|---|---|---|
| Pública | `10.0.10.0/24` | `10.0.11.0/24` | ALB público, ECS frontend, NAT Gateway, bastion host |
| Privada (aplicação) | `10.0.20.0/24` | `10.0.21.0/24` | EC2 do backend (sem IP público), ALB interno |
| Dados (banco) | `10.0.30.0/24` | `10.0.31.0/24` | RDS PostgreSQL (primário e standby), sem IP público |

Tabelas de rotas:

| Sub-redes | Rota para fora da VPC |
|---|---|
| Públicas (2a e 2b) | `0.0.0.0/0` → Internet Gateway |
| Privada 2a | `0.0.0.0/0` → NAT Gateway da 2a |
| Privada 2b | `0.0.0.0/0` → NAT Gateway da 2b |
| Dados (2a e 2b) | Somente rota `local`, sem saída para a internet |

As sub-redes de dados ficam separadas das de aplicação para que o banco não tenha nenhum caminho para a internet e para permitir políticas de rede específicas por camada.

## 4. Balanceamento de carga e health check

O tráfego passa por dois balanceadores, que separam as camadas de frontend e de backend:

| Balanceador | Posição | Destinos | Porta | Security group |
|---|---|---|---|---|
| ALB público | Sub-redes públicas 2a e 2b | Tasks do ECS frontend (uma por AZ) | 80/443 | `sg-alb` |
| ALB interno | Sub-redes privadas 2a e 2b | EC2 do backend (uma por AZ) | 8080 | `sg-alb-int` |

Parâmetros de health check propostos:

| Balanceador | Caminho | Intervalo | Limite saudável | Limite não saudável |
|---|---|---|---|---|
| ALB público (target group do frontend) | `/` | 30 s | 2 | 2 |
| ALB interno (target group do backend) | `/actuator/health` | 30 s | 2 | 2 |

Com isso, qualquer frontend alcança qualquer backend. Se uma instância do backend ficar não saudável, o ALB interno deixa de enviar tráfego a ela e usa a instância da outra AZ.

Evolução possível: substituir as duas EC2 por um Auto Scaling Group com mínimo de duas instâncias distribuídas nas duas sub-redes privadas, mantendo o mesmo target group.

## 5. Estratégia de NAT

**Decisão: um NAT Gateway por zona de disponibilidade** (`nat-a` na sub-rede pública 2a e `nat-b` na sub-rede pública 2b), cada um com seu Elastic IP. A tabela de rotas da sub-rede privada de cada AZ aponta para o NAT da própria AZ.

| Aspecto | Consequência |
|---|---|
| Disponibilidade | A queda de uma AZ não remove a saída para a internet da outra AZ. |
| Custo | A parcela fixa por hora dos NAT Gateways dobra, além do Elastic IP de cada um. |
| Tráfego entre AZs | Cada backend sai pelo NAT da própria AZ, sem cobrança de transferência entre AZs para esse caminho. |

Alternativa descartada: um NAT compartilhado na 2a. Seria mais barato, mas manteria um ponto único de falha, e o backend da 2b perderia a saída (portal Elotech e pull de imagens) se a 2a caísse.

O NAT serve ao fluxo (3): acesso ao portal de transparência Elotech.

## 6. Banco de dados e backups

### 6.1 Estratégia

**Decisão: Amazon RDS for PostgreSQL em modo Multi-AZ (instância com standby).**

- O **primário** fica na AZ `us-east-2a` (sub-rede `10.0.30.0/24`) e o **standby** na AZ `us-east-2b` (sub-rede `10.0.31.0/24`).
- A replicação entre eles é **síncrona**.
- Os dois backends usam o **mesmo endpoint DNS** do RDS, que sempre aponta para o primário. O standby não aceita conexões.
- Em falha do primário ou da AZ 2a, a AWS promove o standby automaticamente (normalmente entre 60 e 120 segundos) e o mesmo endpoint passa a apontar para ele. A aplicação não muda de configuração.
- Sem IP público, em DB subnet group com as sub-redes `10.0.30.0/24` e `10.0.31.0/24`. O `sg-db` aceita a porta 5432 somente a partir do `sg-app`.
- O pool de conexões do backend (HikariCP) deve ter timeout e retry configurados, e o cache de DNS da JVM deve ser curto, para reconectar após um failover.

### 6.2 Alternativas consideradas

| Alternativa | Motivo da decisão |
|---|---|
| Multi-AZ instance (escolhida) | Replicação síncrona, failover automático, sem mudança na aplicação, custo menor que o cluster. |
| Read replica | Replicação assíncrona e promoção manual: pode perder dados recentes e exige intervenção. Serve para escalar leitura, não para alta disponibilidade. |
| Multi-AZ DB cluster | Mais rápido no failover, porém mais caro e mais complexo que o necessário para a aplicação em questão. |
| PostgreSQL próprio em EC2 com réplica | Exige operar replicação, failover e patches manualmente. |

### 6.3 Backups (fluxo 4)

| Mecanismo | Descrição |
|---|---|
| Backups automáticos do RDS | Retenção de 7 dias e recuperação para um ponto no tempo (PITR). Gerenciados pela AWS. |
| Snapshots manuais | Antes de mudanças relevantes (por exemplo, migrações de schema). |
| `pg_dump` para S3 | Dump lógico periódico enviado ao bucket S3 de backup, por um job com IAM Role própria.

O bucket de backup tem versionamento, criptografia em repouso, bloqueio de acesso público e regra de ciclo de vida (por exemplo, transição para classe de armazenamento mais barata após 30 dias e expiração após 90).

## 7. Estado da aplicação fora da instância

Para que qualquer instância atenda qualquer requisição, nenhum estado fica em disco local ou em memória do backend.

| Estado | Onde fica |
|---|---|
| Dados da aplicação | RDS PostgreSQL Multi-AZ |
| Arquivos enviados pelos usuários | Bucket S3 de uploads |
| Sessões de usuário | Spring Session JDBC armazenando as sessões no próprio RDS |
| Imagens Docker | ECR (regional) |
| Logs | CloudWatch Logs |

## 8. Pontos únicos de falha

| Ponto único de falha (Entrega 1) | Tratamento | Justificativa |
|---|---|---|
| Zona de disponibilidade única | Eliminado | Recursos distribuídos em `us-east-2a` e `us-east-2b`. |
| EC2 única de aplicação | Eliminado | Duas EC2 de backend (uma por AZ) atrás do ALB interno com health check. |
| Banco de dados na mesma EC2 da aplicação | Eliminado | RDS Multi-AZ com standby síncrono e failover automático. |
| Frontend ECS único e sem balanceador | Eliminado | Um frontend por AZ atrás do ALB público. |
| NAT Gateway único | Eliminado | Um NAT Gateway por AZ. |
| Bastion host único | Eliminado | Um bastion por AZ, em sub-redes públicas diferentes. |
| Internet Gateway | Aceito | Serviço gerenciado e redundante pela própria AWS. |
| ALB público e ALB interno | Aceito | Serviços gerenciados que operam em múltiplas AZs. |
| ECR e S3 | Aceito | Serviços regionais gerenciados com redundância entre AZs. |
| Portal de transparência Elotech (dependência externa) | Aceito | Fora do controle do grupo. A indisponibilidade afeta apenas a integração. |
| Tempo de failover do RDS (60 a 120 s) | Aceito | Indisponibilidade breve e rara, compatível com o perfil de uso. |
| Região única (`us-east-2`) | Aceito | Recuperação entre regiões (replicação de S3 e snapshots em outra região) aumentaria o custo sem necessidade para o perfil de uso. Fica como evolução futura. |

## 9. Fluxos numerados

| Fluxo | Descrição | Caminho |
|---|---|---|
| (1) | Usuário → aplicação | Usuário → Internet Gateway → ALB público (:80/:443) → ECS frontend → ALB interno → EC2 backend (:8080) → RDS (:5432) |
| (2) | Administrador → SSH | Administrador → Internet Gateway → bastion host da AZ (:22) → EC2 backend da mesma AZ (:22) |
| (3) | Rede privada → internet / serviço externo | EC2 backend → NAT Gateway da própria AZ → Internet Gateway → portal Elotech |
| (4) | Backup do banco | `pg_dump` e backups do RDS → bucket S3 de backup |
| Pull de imagem | Imagens Docker | ECR → tasks do ECS frontend (e EC2 backend, via NAT) |

Observações:

- No fluxo (1), o backend da AZ 2b conecta ao banco por IP privado através da rota `local` da VPC (a VPC atravessa as AZs), sem NAT nem internet.
- No fluxo (2), o `sg-bastion` aceita SSH somente do IP do administrador, e o `sg-app` aceita SSH somente do `sg-bastion`.

## 10. Segurança: security groups

| Security group | Entrada permitida | Origem |
|---|---|---|
| `sg-alb` | 80/443 | `0.0.0.0/0` |
| `sg-front` | Porta do frontend | `sg-alb` |
| `sg-alb-int` | 8080 | `sg-front` |
| `sg-app` | 8080 | `sg-alb-int` |
| `sg-app` | 22 | `sg-bastion` |
| `sg-db` | 5432 | `sg-app` |
| `sg-bastion` | 22 | IP do administrador |

Princípio de menor privilégio: cada camada aceita tráfego apenas da camada imediatamente anterior, referenciada por security group e não por IP.

## 11. Cenários de falha

| Falha | Efeito | Recuperação |
|---|---|---|
| Queda da AZ `us-east-2a` | Frontend, backend, NAT e bastion da 2a ficam indisponíveis. | Os ALBs enviam tudo à 2b. O standby do RDS é promovido automaticamente. |
| Queda de uma EC2 de backend | O health check do ALB interno a marca como não saudável. | O tráfego segue para a outra instância. |
| Queda do primário do RDS | Conexões abertas caem por 60 a 120 s. | Failover automático e reconexão do pool. |
| Queda de um NAT Gateway | Perde saída para a internet apenas a AZ afetada. | O fluxo (1) não depende do NAT, e a outra AZ segue normal. |
| Queda de um bastion | Acesso administrativo por aquela AZ indisponível. | Usar o bastion da outra AZ. |

## 12. Custo da alta disponibilidade


| Versão | Custo mensal estimado | Variação |
|---|---|---|
| Arquitetura implantada (Entrega 1, cenário A) 12 meses | **1.189,32 USD** | - |
| Proposta de alta disponibilidade 12 meses| **[valor]** | **[+x%]** |

Itens que mais contribuem para o aumento:

1. **RDS Multi-AZ** em substituição ao container de banco na EC2 (o standby dobra o custo da instância de banco).
2. **Segunda EC2 de backend** (`t3.medium`).
3. **Segundo NAT Gateway** (parcela fixa por hora).
4. **Dois Application Load Balancers** (público e interno).
5. **Segundo bastion**, segundo frontend e Elastic IPs adicionais (impacto menor).
6. **Armazenamento em S3** e backups (impacto baixo).

Após análise dos custos da arquitetura de alta disponibilidade proposta, conclui-se que o investimento não é justificável para o escopo da aplicação no cenário atual, onde não há previsão de aumento significativo no número de usuários e com picos de acesso previsíveis e estimáveis ao longo do ano.