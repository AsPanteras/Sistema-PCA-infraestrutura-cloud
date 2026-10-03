# Documento de Arquitetura e Orçamento Cloud (AWS)

**Link da Estimativa (730h):** [Calculadora AWS - 730h](https://calculator.aws/#/estimate?id=eef5ffee754d84b811869b21335e88b29be590a6)
**Link da Estimativa (10h):** [Calculadora AWS - 10h](https://calculator.aws/#/estimate?id=7de0dfb7498d625c0f94082f71101b1c157a495a)

## 1. Visão Geral da Infraestrutura

A infraestrutura foi desenhada para a Amazon Web Services (AWS) com um custo estimado de 99,11 USD por mês (ou 1.189,32 USD anuais) em cenário de uso contínuo. A arquitetura está contida numa única Virtual Private Cloud (VPC) na região us-east-2 (Ohio), dividida entre sub-redes públicas e privadas para garantir a segurança dos dados.

* **Internet Gateway:** Permite o fluxo de tráfego entre a internet e a sub-rede pública, sem custos fixos de provisionamento.

* **NAT Gateway:** Localizado na sub-rede pública, permite que os recursos na sub-rede privada descarreguem atualizações e pacotes de forma segura.

* **API Gateway:** Para otimizar custos e simplificar o desenho, o API Gateway foi removido. O contentor do Frontend assumirá a função de proxy reverso.

## 2. Componentes e Escolha de Instâncias

### 2.1. Frontend (ECS - Sub-rede Pública)

* **Serviço:** AWS Fargate (ECS).

* **Configuração:** 0.25 vCPU, 2 GB de RAM, 20 GB de armazenamento e sistema operativo Linux.

* **Custo Mensal (Uso Contínuo):** 13,88 USD.

* **Justificativa:** O Fargate gere os contentores de forma serverless. É responsável por executar o Nginx, que serve os ficheiros estáticos da interface Angular e atua como proxy reverso para o backend.

### 2.2. Backend + Banco de Dados (EC2 - Sub-rede Privada)

* **Serviço:** Amazon EC2 (t3.medium com 30 GB EBS).

* **Custo Mensal (Uso Contínuo):** 32,77 USD.

* **Justificativa da Família (t3):** Foi escolhida a família de uso geral com CPU partilhada baseada em créditos. Esta família é ideal para cargas de trabalho que não exigem processamento intensivo de forma contínua, oferecendo o melhor rácio de custo-benefício.

* **Comportamento no Limite de Créditos:** Se a aplicação sofrer um pico de acessos e esgotar os créditos acumulados, o desempenho da CPU será drasticamente estrangulado (throttled) para uma linha de base baixa (ex: 20%). A aplicação ficará extremamente lenta até que o tráfego diminua e novos créditos sejam gerados.

* **Justificativa do Tamanho (medium):** Um tamanho menor, como o t3.micro (com 1 GB de RAM), não seria suficiente. Como a máquina precisa de executar o serviço Docker contendo a JVM do backend em Java/Spring Boot juntamente com a base de dados PostgreSQL, 1 GB resultaria em underprovisioning (falta de memória e falhas na aplicação). O tamanho medium (4 GB RAM) suporta as tecnologias adequadamente sem causar overprovisioning.

### 2.3. Bastion Host (EC2 - Sub-rede Pública)

* **Serviço:** Amazon EC2 (t4g.nano com 8 GB EBS).

* **Custo Mensal (Uso Contínuo):** 3,71 USD.

* **Justificativa:** Usada estritamente como entreposto (jump box) para aceder via SSH à máquina do backend na sub-rede privada. Terá regras estritas, permitindo apenas ligações na porta 22. Sendo uma carga levíssima, o menor tamanho disponível na família t4g (processadores ARM Graviton) é mais do que suficiente.

## 3. Análise de Custos e Estratégia de Redução

Abaixo encontra-se a lista dos itens de custo previstos no orçamento de uso contínuo:

* **Amazon VPC:** 48,75 USD

* **Amazon EC2 (Backend):** 32,77 USD

* **AWS Fargate (Frontend):** 13,88 USD

* **Amazon EC2 (Bastion):** 3,71 USD

**Identificação do item mais caro:** O recurso mais caro do projeto é a Amazon VPC. Este valor é impulsionado pela existência de 3 endereços IPv4 públicos em uso (Bastion, NAT e ECS), pelo tráfego de dados de saída (50 GB) e, sobretudo, pelo custo por hora de funcionamento do NAT Gateway.

**Proposta de redução de custos:**
Para reduzir os valores do EC2 e Fargate, a equipa poderia abandonar o modelo "Sob Demanda" e adotar um Compute Savings Plan (compromisso de uso de 1 ou 3 anos). Para reduzir os custos da VPC, o NAT Gateway poderia ser substituído por uma instância EC2 a correr como NAT (NAT Instance).

**O que se perde:** Ao adotar o Savings Plan, perde-se a flexibilidade de encerrar o projeto a qualquer momento, ficando a equipa presa a um contrato. Ao utilizar uma NAT Instance em vez do NAT Gateway gerido, perde-se a alta disponibilidade, a escalabilidade automática de banda larga e aumenta-se a carga de trabalho de manutenção da infraestrutura.

**Utilização do Nível Gratuito (Free Tier):**
Foi contemplada a utilização do Nível Gratuito da AWS. A camada gratuita cobre os 30 GB de armazenamento EBS de uso geral (gp3) acoplados à instância do backend. A VPC nativa e o Internet Gateway não têm custos. No entanto, serviços como a instância t3.medium, o NAT Gateway e o Fargate gerarão cobranças desde o início.

## 4. Plano de Controlo de Custos do Grupo

Para evitar surpresas na faturação, será implementado o seguinte plano:

* **Alerta de Orçamento:** Configuração do AWS Budgets para enviar notificações imediatas por e-mail caso os gastos estimados alcancem um teto máximo de segurança predefinido.

* **Destruição do Ambiente:** Como se trata de um ambiente de desenvolvimento, os recursos serão provisionados via código (Infrastructure as Code). A infraestrutura será destruída entre sessões de teste e desligada fora do horário de trabalho.

* **Tags nos Recursos:** Todos os recursos (EC2, ECS, Volumes EBS) receberão etiquetas estruturadas. Isso permitirá utilizar o AWS Cost Explorer para auditar exatamente que componente do sistema está a consumir mais verbas.

## 5. Anexos: Detalhamento das Estimativas do Provedor (PDF)

Para demonstrar a viabilidade financeira do projeto durante a fase de desenvolvimento, o grupo gerou duas estimativas distintas: o cenário de infraestrutura ligada 24/7 e o cenário real de uso do grupo.

### Cenário 1: Utilização Contínua (730 horas/mês)

📄 **Documento de referência:** [My Estimate - Calculadora de Preços da AWS.pdf](./My%20Estimate%20-%20Calculadora%20de%20Preços%20da%20AWS.pdf)

A AWS utiliza a média de **730 horas por mês** para calcular o uso mensal ininterrupto de um recurso (365 dias por ano × 24 horas por dia ÷ 12 meses = 730 horas). Esta estimativa reflete o cenário em que a infraestrutura permanece ligada 24 horas por dia, totalizando **99,11 USD/mês**.

### Cenário 2: Utilização Efetiva do Grupo (10 horas/mês)

📄 **Documento de referência:** [My Estimate - Calculadora de Preços da AWS - 10 horas mês.pdf](./My%20Estimate%20-%20Calculadora%20de%20Preços%20da%20AWS%20-%2010%20horas%20mês.pdf)

Alinhado ao plano descrito no item 4 (Destruição do Ambiente via IaC), a equipe manterá os recursos ativos apenas durante os períodos de teste e desenvolvimento. Estimamos o uso efetivo de **10 horas mensais**, derrubando o custo total para **48,85 USD/mês**.

**Resumo dos Recursos (Base de 10 horas/mês):**

* **AWS Fargate (Frontend Nginx):**
  * Custo: **0,19 USD/mês** (queda de 98% em relação ao uso contínuo).
  * Duração média: 10 horas, 1 tarefa/pod.

* **Amazon EC2 (Backend e Banco de Dados - t3.medium):**
  * Custo: **0,44 USD/mês** (redução significativa frente aos 32,77 USD originais).
  * Estratégia de preço: Utilização sob demanda (10 horas).

* **Amazon EC2 (Bastion Host - t4g.nano):**
  * Custo: **2,17 USD/mês**.

* **Amazon VPC (Atenção ao Custo Fixo):**
  * Custo: **46,05 USD/mês**.
  * **Análise:** Mesmo desligando as máquinas, a VPC continua sendo o maior ofensor de custos do projeto. Isso ocorre porque recursos como o **NAT Gateway e endereços IPv4 públicos** cobram taxas por hora de existência. Para que o custo caia efetivamente para os 48,85 USD demonstrados (ou até menos), a rotina de *Infrastructure as Code* deve destruir os IPs elásticos e o NAT Gateway ao final do dia de trabalho, não apenas parar as instâncias EC2.