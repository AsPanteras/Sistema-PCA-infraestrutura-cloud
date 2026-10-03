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
| Frontend | **Amazon ECS (Elastic Container Service)** | Gerenciamento e execução do frontend em containers, utilizando uma abordagem serverless. |
| Frontend | **Nginx** | Proxy reverso responsável pelo gerenciamento do tráfego de entrada e pelo roteamento das requisições para os serviços do backend. |
| Backend | **Amazon EC2 (Elastic Compute Cloud)** | Instância de máquina virtual para hospedar e executar o backend em uma arquitetura tradicional. |
| Backend e banco de dados | **Docker** | Containerização dos serviços do backend e do banco de dados, com comunicação interna entre os containers. |
| Bastion Host | **Amazon EC2** | Instância dedicada ao acesso administrativo à máquina do backend, por meio de conexão SSH (porta 22). |

# 10. Riscos e Limitações 


