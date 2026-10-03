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
O frontend é executado de forma conteinerizada utilizando **AWS ECS (Elastic Container Service)**.
* **Proxy Reverso e Roteamento:** O gerenciamento do tráfego de entrada e o roteamento de caminhos  são centralizados em um proxy Nginx dedicado, responsável por realizar o proxy reverso e encaminhar as requisições diretamente para os serviços do backend, eliminando a necessidade do AWS API Gateway.

### 1.2.2. Camada do BackEnd e Banco de Dados
O núcleo da aplicação utiliza uma abordagem tradicional baseada em instâncias de máquinas virtuais **Amazon EC2 (VM)**.
* **Containers Docker:** Tanto a aplicação backend quanto o banco de dados rodam encapsulados em containers Docker na mesma instância EC2 (ou em instâncias correlacionadas).
* **Segurança de Comunicação:** A comunicação entre o backend e o banco de dados ocorre de forma estritamente interna e isolada, reduzindo a superfície de exposição externa.

### 1.2.3. Segurança e Acesso Administrativo (Bastion Host)
Para garantir a segurança operacional e evitar exposições desnecessárias via SSH:
* É utilizado um **Bastion Host (Amazon EC2)** dedicado a funcionar como um ponto de entrada seguro (entreposto).
* O acesso administrativo às instâncias do backend via SSH (porta 22) é realizado exclusivamente através deste Bastion Host.

# 6. Tabela de Tecnologias
| Categoria | Tecnologia | Descrição |
|---|---|---|
| Provedor de nuvem | **AWS** | Provedor de infraestrutura em nuvem escolhido para hospedar a aplicação. |
| Frontend | **Amazon ECS (Elastic Container Service)** | Gerenciamento e execução do frontend em containers, utilizando uma abordagem serverless. |
| Frontend | **Nginx** | Proxy reverso responsável pelo gerenciamento do tráfego de entrada e pelo roteamento das requisições para os serviços do backend. |
| Backend | **Amazon EC2 (Elastic Compute Cloud)** | Instância de máquina virtual para hospedar e executar o backend em uma arquitetura tradicional. |
| Backend e banco de dados | **Docker** | Containerização dos serviços do backend e do banco de dados, com comunicação interna entre os containers. |
| Bastion Host | **Amazon EC2** | Instância dedicada ao acesso administrativo à máquina do backend, por meio de conexão SSH (porta 22). |

# 10. Riscos e Limitações 


