# 1. Introdução
O CPA (Controle de Processos e Contratações) é um sistema web desenvolvido para atender a uma exigência da legislação federal de licitações, que obriga a Prefeitura de Serranópolis do Iguaçu - PR a elaborar e publicar o Plano de Contratações Anual (PCA).

O PCA funciona como um cronograma estratégico que define o que o município planeja licitar e em qual data, seguindo a regra de que o planejamento de cada exercício seja estruturado e publicado sempre no ano anterior, como ocorre com a elaboração, em 2026, do plano voltado para 2027.

## 1.1. Descrição da Demanda 
A demanda por uma solução surgiu para substituir o antigo controle em planilhas do Excel, processo que era altamente manual, demorado e limitava a visão geral dos resultados. O novo sistema foi desenvolvido para automatizar e otimizar essa rotina dos usuários, facilitando o monitoramento da execução das compras, formalizando o registro de justificativas em casos de atraso e analisando o que foi ou não realizado durante o ano. 

A aplicação atual gerencia um volume recorrente de dados relacionados ao PCA e aos processos licitatórios, com picos de atividade na consolidação anual do PCA, na geração bimestral de relatórios e nas sincronizações automáticas com o Portal da Transparência.

Atualmente, são administrados cerca de 150 a 210 itens do PCA por ano, além de um histórico de aproximadamente 3.500 processos licitatórios, com cerca de 200 novos processos incorporados anualmente.

O sistema atual mantém o histórico integral dos dados, incluindo informações públicas sincronizadas do Portal da Transparência e dados próprios do setor, como andamentos, justificativas e registros de auditoria. A operação utiliza exclusivamente dados públicos, sem informações pessoais ou sensíveis.

## 1.2. Descrição da Aplicação
Seguindo a linha de raciocínio do que seria necessário para suprir as necessidades atuais dos usuários, para suportar essa governança, a aplicação CPA foi dimensionada para operar com uma base enxuta, pois são de 5 a 10 usuários simultâneos diariamente, apresentando um perfil de acesso estável e sem picos abruptos de tráfego.

A aplicação CPA adota uma abordagem híbrida e moderna na nuvem, separando as camadas de interface do usuário, lógica de negócios e persistência de dados, buscando segurança, organização e possibilidade de expansão da infraestrutura.

### 1.2.1. Camada do FrontEnd
A interface de usuário foi desenvolvida utilizando o framework **Angular 19** e é executada de forma conteinerizada utilizando **AWS ECS (Elastic Container Service)**.
* **Proxy Reverso e Roteamento:** O gerenciamento do tráfego de entrada e o roteamento de caminhos  são centralizados em um proxy Nginx dedicado, responsável por realizar o proxy reverso e encaminhar as requisições diretamente para os serviços do backend, eliminando a necessidade do AWS API Gateway.

### 1.2.2. Camada do BackEnd e Banco de Dados
O núcleo da aplicação é uma API construída em **Java 17 utilizando Spring Boot**, enquanto a persistência de dados relacional utiliza **PostgreSQL**. Esta camada utiliza uma abordagem tradicional baseada em instâncias de máquinas virtuais **Amazon EC2 (VM)**.
* **Containers Docker:** Tanto a aplicação backend quanto o banco de dados rodam encapsulados em containers Docker na mesma instância EC2 (ou em instâncias correlacionadas).
* **Segurança de Comunicação:** A comunicação entre o backend e o banco de dados ocorre de forma estritamente interna e isolada, reduzindo a superfície de exposição externa.

### 1.2.3. Segurança e Acesso Administrativo (Bastion Host)
Para garantir a segurança operacional e evitar exposições desnecessárias via SSH:
* É utilizado um **Bastion Host (Amazon EC2)** dedicado a funcionar como um ponto de entrada seguro (entreposto).
* O acesso administrativo às instâncias do backend via SSH (porta 22) é realizado exclusivamente através deste Bastion Host.
* Autenticação da Aplicação: O acesso ao sistema é protegido por tokens **JWT**. A aplicação adota um modelo misto: ações de edição exigem login, enquanto o *dashboard* possui acesso público (read-only) para visualização pelas Secretarias.

## 1.3. Funcionalidades Principais e Interoperabilidade
Para atender à demanda de monitoramento do PCA, a aplicação conta com as seguintes funcionalidades vitais nesta entrega:
* **AndamentoService:** Gerencia a fase atual do PCA antes da publicação (ex: fase de TR).
* **PcaService & SecretariaService:** Cadastros estruturais dos planos e das secretarias do município.
* **LicitacaoService & SincronizacaoAgendadaJob:** Responsáveis pela interoperabilidade. Consomem a API pública municipal para buscar novas licitações. O Job possui **tolerância a falhas**: caso a API da prefeitura fique fora do ar, o erro não quebra a aplicação; o evento (data, hora e erro) é registrado no banco de dados para auditoria.
* **PcaSugestaoService:** Sistema de recomendação que sugere associações entre PCAs e licitações importadas sem vínculo.
* **RelatorioService:** Geração de resultados consolidados para facilitar o trabalho da equipe de compras.

# 2. Diagrama da arquitetura
![Diagrama da arquitetura](diagramas/Sistema-PCA.drawio.png)

# 3. Plano de endereçamento IP
O dimensionamento da infraestrutura foi estruturado da seguinte forma: A região escolhida foi **us-east-2** (Ohio - USA), usando a zona de disponibilidade **us-east-2a**. Também foi definida uma VPC (Virtual private cloud) com o bloco privado 10.0.0.0/16, conforme a RFC 1918, subdividida em duas sub-redes /24, sem sobreposição:

| Recurso | Nome | CIDR | Zona | Tipo | Finalidade |
|---|---|---|---|---|---|
| Rede virtual | vpc-pca | 10.0.0.0/16 | us-east-2a | - | Rede do projeto |
| Sub-rede | pub-pca-a | 10.0.10.0/24 | us-east-2a | Pública | Bastion, NAT Gateway, Frontend da aplicação |
| Sub-rede | priv-pca-a | 10.0.20.0/24 | us-east-2a | Privada | Backend da aplicação, banco |

A escolha do bloco /16 para a VPC foi escolhido levando em consideração a possibilidade de expansão futura da infraestrutura, esse bloco fornece 65.536 endereços IPv4, permitindo a criação de outras sub-redes sem a necessidade de alterar o bloco. Para as sub-redes, foi escolhido o bloco /24 que fornece 256 endereços, quantidade suficiente para os recursos previstos em cada sub-rede. A AWS reserva 5 endereços em cada bloco CIDR de sub-rede para uso interno da infraestrutura, sendo eles os 4 primeiros endereços e o último, o que torna 251 endereços utilizáveis ao todo em cada sub-rede.


# 4. Tabelas de rota
Cada sub-rede possui uma tabela de rotas própria. A sub-rede pública utiliza o Internet Gateway para comunicação com a Internet, enquanto a sub-rede privada utiliza o NAT Gateway para conexões de saída.

| Recurso | Destino | Alvo | Justificativa |
| --- | ---| --- | --- |
| Sub-rede pública | 10.0.0.0/16 | Local | Comunicação interna da VPC |
| Sub-rede pública | 0.0.0.0/0 | Internet Gateway | Acesso dos usuários ao frontend, acesso do administrador via SSH ao Bastion e saída do NAT Gateway para internet |
| Sub-rede privada | 10.0.0.0/16 | Local | Comunicação interna com frontend (8080) e bastion (22) |
| Sub-rede privada | 0.0.0.0/0 | NAT Gateway | Saída da aplicação para serviços externos, como o portal Elothec |

#### Justificativas
* **Rota local**: Criada automaticamente pela AWS e permite a comunicação entre os recursos da VPC por endereços privadas.
* **Internet Gateway**: Permite acesso da sub-rede pública à internet. O NAT Gateway também utiliza essa rota para encaminhar o tráfego externo.
* **NAT Gateway**: Permite que recursos da sub-rede privada iniciem conexões com a internet sem possuir IP público.

A ausência da rota 0.0.0.0/0 -> NAT Gateway ocasionaria na impossibilidade da aplicação na sub-rede privada acessar serviços externos, consequentemente perdendo a integração com o portal da Elotech.

# 5. Matriz de regras de segurança
As regras de segurança foram definidas seguindo o princípio do menor privilégio, permitindo somente os fluxos necessários para o funcionamento da aplicação. O frontend é o único componente exposto à Internet, utilizando as portas HTTP/HTTPS. 
O acesso administrativo à infraestrutura é realizado exclusivamente por SSH através do Bastion Host, cujo acesso é restrito ao IP do administrador. A aplicação aceita requisições somente vindas do frontend, enquanto o banco de dados não é exposto externamente e permanece acessível apenas internamente à aplicação dentro da rede Docker.

| Grupo de segurança | Direção | Protocolo | Porta | Origem/Destino | Justificativa |
|---|---|---|---|---|---|
| sg-bastion | Entrada | TCP | 22 | <ip_do_admin>/32 | Acesso administrativo |
| sg-bastion | Saída | TCP | 22 | sg-app | Conexão SSH do Bastion para a aplicação |
| sg-app | Entrada | TCP | 22 | sg-bastion | SSH apenas via Bastion |
| sg-app | Entrada | TCP | 8080 | sg-front | Acesso à API apenas via frontend |
| sg-app | Saída | TCP | 80/443 | 0.0.0.0/0 | Acesso a serviços externos por meio do NAT Gateway |
| sg-front | Entrada | TCP | 443 | 0.0.0.0/0 | Acesso HTTPS à aplicação pelo usuário |
| sg-front | Entrada | TCP | 80 | 0.0.0.0/0 | Acesso HTTP à aplicação pelo usuário |
| sg-front | Saída | TCP | 8080 | sg-app | Proxy reverso para a API |

#### Justificativas:
* **sg-bastion**: Permite apenas a entrada SSH do IP do administrador, evitando que a máquina fique esposta para acesso de qualquer IP. Como saída, usa a porta 22 para acessar a EC2 da aplicação.
* **sg-app**: Permite entrada SSH (porta 22) exclusiva do Bastion, e libera a porta 8080 para acesso do frontend apenas, não expondo a aplicação para a internet. Como saída, libera as portas 80 e 443 para permitir serviços externos, como a API do portal Elotech, por meio do NAT Gateway.
* **sg-front**: Permite entrada HTTP e HTTPS (80/443) para acesso do usuário na aplicação. Como saída, acessa a VM da aplicação via porta 8080.

# 6. Tabela de Tecnologias
| Categoria | Tecnologia | Descrição |
|---|---|---|
| Provedor de nuvem | **AWS** | Provedor de infraestrutura em nuvem escolhido para hospedar a aplicação. |
| Frontend (Framework) | **Angular 19** | Framework utilizado para a construção de toda a interface do usuário (SPA). |
| Frontend (Hospedagem) | **Amazon ECS** | Gerenciamento e execução do frontend em containers, utilizando uma abordagem serverless. |
| Proxy / Roteamento | **Nginx** | Proxy reverso responsável pelo gerenciamento do tráfego de entrada e roteamento. |
| Backend (Linguagem/Framework)| **Java 17 + Spring Boot** | Linguagem e framework base para a construção da API REST da aplicação. |
| Backend (Hospedagem) | **Amazon EC2** | Instância de máquina virtual para hospedar e executar o backend. |
| Banco de Dados | **PostgreSQL** | Banco de dados relacional utilizado para a persistência das informações do sistema. |
| Conteinerização | **Docker** | Containerização dos serviços (Front, Back e Banco), garantindo portabilidade de implantação. |
| Segurança | **JWT (JSON Web Token)** | Padrão utilizado para autenticação segura e autorização das rotas da API. |
| Bastion Host | **Amazon EC2** | Instância dedicada ao acesso administrativo à máquina do backend via SSH (porta 22). |

# 7. Dimensionamento das instâncias
|Provedor | Exemplo | Família | Tamanho |
|---|---|---|---|
| AWS | t3.medium | t3 (CPU baseada em créditos) | medium |
| AWS | T4g.nano | T4g (CPU intermitente) | nano |
| AWS | AWS Fargate (ECS) | ECS Fargate | Task 0.25 vCPU / 2 GB |

## 7.1. Instâncias no projeto
| Componente | Família | Tipo | vCPU | Memória | Disco | Sub-rede |
|---|---|---|---|---|---|---|
| API da aplicação + banco de dados | T3 | T3.medium | 2 | 4.0 | EBS | Privada |
| Bastion Host | T4g | T4g.nano | 2 | 0.5 | EBS | Pública |
| Frontend da aplicação | ECS/Fargate | Task 0.25 vCPU / 2 GB | 0.25 | 2.0 | Pública |

#### Justificativas
* **T3.medium (API da aplicação + banco)**
    - **Justificativa da Família (t3):** Foi escolhida a família de uso geral com CPU partilhada baseada em créditos. Esta família é ideal para cargas de trabalho que não exigem processamento intensivo de forma contínua, oferecendo o melhor rácio de custo-benefício.

    - **Comportamento no Limite de Créditos:** Se a aplicação sofrer um pico de acessos e esgotar os créditos acumulados, o desempenho da CPU será drasticamente estrangulado (throttled) para uma linha de base baixa (ex: 20%). A aplicação ficará extremamente lenta até que o tráfego diminua e novos créditos sejam gerados.

    - **Justificativa do Tamanho (medium):** Um tamanho menor, como o t3.micro (com 1 GB de RAM), não seria suficiente. Como a máquina precisa de executar o serviço Docker contendo a JVM do backend em Java/Spring Boot juntamente com a base de dados PostgreSQL, 1 GB resultaria em underprovisioning (falta de memória e falhas na aplicação). O tamanho medium (4 GB RAM) suporta as tecnologias adequadamente sem causar overprovisioning.

* **T4g.nano (Bastion Host)**
    - Usada estritamente como entreposto (jump box) para aceder via SSH à máquina do backend na sub-rede privada. Terá regras estritas, permitindo apenas ligações na porta 22. Sendo uma carga levíssima, o menor tamanho disponível na família t4g (processadores ARM Graviton) é mais do que suficiente.

* **AWS Fargate (Frontend da aplicação)**
    - O Fargate gere os contentores de forma serverless. É responsável por executar o Nginx, que serve os ficheiros estáticos da interface Angular e atua como proxy reverso para o backend.

# 8. Estimativa de custos
**Link da Estimativa (730h):** [Calculadora AWS - 730h](https://calculator.aws/#/estimate?id=eef5ffee754d84b811869b21335e88b29be590a6)
**Link da Estimativa (10h):** [Calculadora AWS - 10h](https://calculator.aws/#/estimate?id=7de0dfb7498d625c0f94082f71101b1c157a495a)

## 8.1. Análise de Custos e Estratégia de Redução

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

## 8.2. Plano de Controlo de Custos do Grupo

Para evitar surpresas na faturação, será implementado o seguinte plano:

* **Alerta de Orçamento:** Configuração do AWS Budgets para enviar notificações imediatas por e-mail caso os gastos estimados alcancem um teto máximo de segurança predefinido.

* **Destruição do Ambiente:** Como se trata de um ambiente de desenvolvimento, os recursos serão provisionados via código (Infrastructure as Code). A infraestrutura será destruída entre sessões de teste e desligada fora do horário de trabalho.

* **Tags nos Recursos:** Todos os recursos (EC2, ECS, Volumes EBS) receberão etiquetas estruturadas. Isso permitirá utilizar o AWS Cost Explorer para auditar exatamente que componente do sistema está a consumir mais verbas.

## 8.2. Anexos: Detalhamento das Estimativas do Provedor (PDF)

Para demonstrar a viabilidade financeira do projeto durante a fase de desenvolvimento, o grupo gerou duas estimativas distintas: o cenário de infraestrutura ligada 24/7 e o cenário real de uso do grupo.

### Cenário 1: Utilização Contínua (730 horas/mês)

* **Documento de referência:** [My Estimate - Calculadora de Preços da AWS.pdf](./My%20Estimate%20-%20Calculadora%20de%20Preços%20da%20AWS.pdf)

A AWS utiliza a média de **730 horas por mês** para calcular o uso mensal ininterrupto de um recurso (365 dias por ano × 24 horas por dia ÷ 12 meses = 730 horas). Esta estimativa reflete o cenário em que a infraestrutura permanece ligada 24 horas por dia, totalizando **99,11 USD/mês**.

### Cenário 2: Utilização Efetiva do Grupo (10 horas/mês)

* **Documento de referência:** [My Estimate - Calculadora de Preços da AWS - 10 horas mês.pdf](./My%20Estimate%20-%20Calculadora%20de%20Preços%20da%20AWS%20-%2010%20horas%20mês.pdf)

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

# 9. Riscos e Limitações 

## 9.1. Tabela de Riscos
| Risco | Descrição |
|---|---|
| Ponto único de falha no backend e no banco | Backend e banco rodam na mesma instância EC2. Se ela falhar, a aplicação e os dados ficam indisponíveis. |
| Falha da zona de disponibilidade | Toda a infraestrutura está em uma única zona (us-east-2a), então uma falha nela derruba todos os componentes. |
| Perda de dados | O banco roda em container, sem serviço gerenciado. Sem backups, a falha do disco ou a remoção do container pode causar perda de dados, e o histórico precisa ser mantido integralmente. |
| Ponto único de falha no NAT Gateway | Há um único NAT Gateway. Se ele falhar, o backend perde a saída para a internet e as sincronizações com o Portal da Transparência (Elotech) param. |
| Dependência do Portal da Transparência | A atualização dos dados públicos depende da disponibilidade de um serviço externo, fora do controle da equipe. |

## 9.2. Limitações
* **Escalabilidade restrita:** o backend e o banco compartilham os recursos de uma única EC2, e a capacidade só aumenta com o aumento do porte da instância (escalabilidade vertical), o que exige reinício. A arquitetura atende ao volume atual, mas não a um crescimento expressivo de usuários ou de dados.
* **Acesso administrativo manual:** a administração é feita via SSH pelo Bastion Host, sem automação completa de deploy, o que aumenta o risco de erro humano.
* **Região fora do Brasil:** a região us-east-2 (Ohio) foi escolhida por critérios de custo e disponibilidade, mas aumenta a latência para os usuários em Serranópolis do Iguaçu - PR. Como o uso é leve, o impacto esperado é baixo.
* **Dependência de serviço externo:** a atualização automática dos dados depende do Portal da Transparência da Elotech e da saída pelo NAT Gateway.