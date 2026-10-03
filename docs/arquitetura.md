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

A aplicação CPA adota uma abordagem híbrida e moderna na nuvem, separando as camadas de interface do usuário, lógica de negócios e persistência de dados para garantir alta disponibilidade, escalabilidade e segurança.

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

O dimensionamento dos recursos computacionais foi realizado com base no perfil de uso da aplicação (5 a 10 usuários simultâneos diariamente, acessos estáveis) e na necessidade de manter a estabilidade do sistema, evitando tanto o *underprovisioning* (falta de recursos que gera quedas) quanto o *overprovisioning* (capacidade ociosa que gera custos desnecessários).

Abaixo está o detalhamento da capacidade alocada para cada componente da arquitetura:

| Camada / Componente | Serviço AWS | Tamanho/Família | vCPU | Memória RAM | Armazenamento |
|---|---|---|---|---|---|
| **Frontend** (Angular/Nginx) | AWS Fargate (ECS) | Serverless | 0.25 | 2 GB | 20 GB (Efêmero) |
| **Backend + Banco de Dados** | Amazon EC2 | t3.medium | 2 | 4 GB | 30 GB (EBS gp3) |
| **Bastion Host** | Amazon EC2 | t4g.nano | 2 | 0.5 GB | 8 GB (EBS gp3) |

#### Justificativas do Dimensionamento:

* **Frontend (AWS Fargate):** Sendo responsável apenas por executar o Nginx para servir arquivos estáticos e atuar como proxy reverso, a carga de processamento é muito baixa. A configuração de 0.25 vCPU e 2 GB de RAM é o dimensionamento inicial ideal no Fargate para contêineres leves, garantindo a entrega rápida da interface sem custos excessivos.
* **Backend + Banco de Dados (t3.medium):** Esta é a máquina que suporta a maior carga de trabalho. Como os contêineres da API (Java/Spring Boot - JVM) e do banco de dados (PostgreSQL) rodam simultaneamente no mesmo *host*, tamanhos menores (como a *micro* com 1 GB ou *small* com 2 GB) resultariam em estouro de memória (OOM - *Out of Memory*), derrubando a aplicação. Os 4 GB de RAM da `t3.medium` suportam os serviços com folga. A escolha da família "T" (baseada em acúmulo de créditos de CPU) é ideal, pois a aplicação não exige processamento intenso em 100% do tempo.
* **Bastion Host (t4g.nano):** A função exclusiva desta máquina é servir de ponte para tráfego SSH em direção à rede privada. Como não há processamento de dados nem hospedagem de aplicações, o menor tamanho disponível foi escolhido. A adoção da família `t4g` (processadores AWS Graviton baseados em arquitetura ARM) reduz o custo operacional mantendo a performance necessária para conexões seguras.

# 8. Registros de Decisão Arquitetural (ADRs)

Nesta seção, documentamos as principais decisões arquiteturais tomadas durante o planejamento do projeto CPA, detalhando o contexto, a decisão adotada e as suas consequências (positivas e negativas).

## ADR 001: Hospedagem conjunta do Backend e Banco de Dados em uma única instância EC2

* **Status:** Aceito
* **Contexto:** A aplicação possui um volume de tráfego baixo a moderado, com um público-alvo de 5 a 10 usuários simultâneos, e restrições orçamentárias severas para o ambiente de desenvolvimento e produção. Avaliou-se o uso de um serviço de banco de dados gerenciado (Amazon RDS) e contêineres separados para a API.
* **Decisão:** Optou-se por consolidar o backend (Java/Spring Boot) e o banco de dados (PostgreSQL) em contêineres Docker executados dentro de uma única instância Amazon EC2 (`t3.medium`).
* **Consequências:**
  * **Positivas:** Redução drástica de custos em comparação com a utilização de serviços gerenciados separados; simplificação do gerenciamento de rede (comunicação interna do Docker).
  * **Negativas:** Criação de um ponto único de falha (Single Point of Failure). Se a instância EC2 cair, tanto a aplicação quanto os dados ficam indisponíveis. Exige a criação de rotinas manuais de backup do banco de dados e manutenção do SO.

## ADR 002: Remoção do API Gateway e adoção de Proxy Reverso via Nginx (ECS Fargate)

* **Status:** Aceito
* **Contexto:** Inicialmente, cogitou-se o uso do AWS API Gateway para gerenciar e rotear as requisições externas para o backend na rede privada.
* **Decisão:** O API Gateway foi removido do desenho para simplificar a arquitetura e otimizar o orçamento. A responsabilidade de roteamento foi transferida para o serviço de Frontend. O contêiner hospedado no AWS Fargate (ECS) executa o Nginx, que serve os arquivos estáticos do Angular e atua como proxy reverso, encaminhando as requisições de API diretamente para a porta 8080 do backend na sub-rede privada.
* **Consequências:**
  * **Positivas:** Redução de custos diretos e da complexidade da infraestrutura AWS. Centralização das configurações de rotas de fronteira no próprio código do frontend.
  * **Negativas:** O contêiner de frontend assume uma responsabilidade dupla (servidor web e proxy de API), o que consome ligeiramente mais recursos locais no Fargate.

## ADR 003: Isolamento em Sub-rede Privada e uso de NAT Gateway

* **Status:** Aceito
* **Contexto:** O banco de dados e as regras de negócio precisam de proteção máxima contra acesso externo direto, mas a aplicação (`LicitacaoService` / `SincronizacaoAgendadaJob`) precisa acessar constantemente a internet para consumir a API pública do Portal da Transparência (Elotech).
* **Decisão:** A instância EC2 do backend/banco foi posicionada estritamente em uma sub-rede privada, sem IP público. Para permitir a saída para a internet, foi implementado um NAT Gateway na sub-rede pública. O acesso administrativo ocorre somente via um Bastion Host (jump box).
* **Consequências:**
  * **Positivas:** Aumento significativo da segurança e diminuição da superfície de ataque, seguindo as melhores práticas de proteção de dados.
  * **Negativas:** O NAT Gateway tem um custo fixo atrelado ao tempo de existência (cobrança por hora) e ao volume de dados processados, tornando-se o ofensor de custos mais alto do projeto. Além disso, se o NAT Gateway falhar, a sincronização de dados do município para.

# 10. Riscos e Limitações 

## 10.1. Tabela de Riscos
| Risco | Descrição |
|---|---|
| Ponto único de falha no backend e no banco | Backend e banco rodam na mesma instância EC2. Se ela falhar, a aplicação e os dados ficam indisponíveis. |
| Falha da zona de disponibilidade | Toda a infraestrutura está em uma única zona (us-east-2a), então uma falha nela derruba todos os componentes. |
| Perda de dados | O banco roda em container, sem serviço gerenciado. Sem backups, a falha do disco ou a remoção do container pode causar perda de dados, e o histórico precisa ser mantido integralmente. |
| Ponto único de falha no NAT Gateway | Há um único NAT Gateway. Se ele falhar, o backend perde a saída para a internet e as sincronizações com o Portal da Transparência (Elotech) param. |
| Dependência do Portal da Transparência | A atualização dos dados públicos depende da disponibilidade de um serviço externo, fora do controle da equipe. |

## 10.2. Limitações
* **Escalabilidade restrita:** o backend e o banco compartilham os recursos de uma única EC2, e a capacidade só aumenta com o aumento do porte da instância (escalabilidade vertical), o que exige reinício. A arquitetura atende ao volume atual, mas não a um crescimento expressivo de usuários ou de dados.
* **Acesso administrativo manual:** a administração é feita via SSH pelo Bastion Host, sem automação completa de deploy, o que aumenta o risco de erro humano.
* **Região fora do Brasil:** a região us-east-2 (Ohio) foi escolhida por critérios de custo e disponibilidade, mas aumenta a latência para os usuários em Serranópolis do Iguaçu - PR. Como o uso é leve, o impacto esperado é baixo.
* **Dependência de serviço externo:** a atualização automática dos dados depende do Portal da Transparência da Elotech e da saída pelo NAT Gateway.