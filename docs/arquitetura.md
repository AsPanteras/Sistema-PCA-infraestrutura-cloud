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

## 1.3. Funcionalidades Principais e Interoperabilidade
Para atender à demanda de monitoramento do PCA, a aplicação conta com as seguintes funcionalidades vitais nesta entrega:
* **AndamentoService:** Gerencia a fase atual do PCA antes da publicação (ex: fase de TR).
* **PcaService & SecretariaService:** Cadastros estruturais dos planos e das secretarias do município.
* **LicitacaoService & SincronizacaoAgendadaJob:** Responsáveis pela interoperabilidade. Consomem a API pública municipal para buscar novas licitações. O Job possui **tolerância a falhas**: caso a API da prefeitura fique fora do ar, o erro não quebra a aplicação; o evento (data, hora e erro) é registrado no banco de dados para auditoria.
* **PcaSugestaoService:** Sistema de recomendação que sugere associações entre PCAs e licitações importadas sem vínculo.
* **RelatorioService:** Geração de resultados consolidados para facilitar o trabalho da equipe de compras.

# 2. Diagrama da arquitetura
![Diagrama da arquitetura](diagramas/Sistema-PCA-diagrama.drawio.png)

# 3. Plano de endereçamento IP
O dimensionamento da infraestrutura foi estruturado da seguinte forma: A região escolhida foi **us-east-2** (Ohio - USA), usando a zona de disponibilidade **us-east-2a**. Também foi definida uma VPC (Virtual private cloud) com o bloco privado 10.0.0.0/16, conforme a RFC 1918, subdividida em duas sub-redes /24, sem sobreposição:

| Recurso | Nome | CIDR | Zona | Tipo | Finalidade |
|---|---|---|---|---|---|
| Rede virtual | vpc-pca | 10.0.0.0/16 | us-east-2a | - | Rede do projeto |
| Sub-rede | pub-pca-a | 10.0.10.0/24 | us-east-2a | Pública | Bastion, NAT Gateway, Frontend da aplicação |
| Sub-rede | priv-pca-a | 10.0.20.0/24 | us-east-2a | Privada | Backend da aplicação, banco |

A escolha do bloco /16 para a VPC foi pensado levando em consideração a possibilidade de expansão futura da infraestrutura, esse bloco fornece 65.536 endereços IPV4, permitindo a criação outras sub-redes sem a necessidade de alterar o bloco. Para as sub-redes, foi escolhido o bloco /24 que fornece 256 endereços, quantidade suficiente para os recursos previstos em cada sub-rede. A AWS reserva 5 endereços em cada bloco CIDR de sub-rede para uso interno da infraestrutura, sendo eles os 4 primeiros endereços e o último, o que torna 251 endereços utilizáveis ao todo em cada sub-rede.

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