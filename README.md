# Sistema de Acompanhamento do PCA

## Integrantes da equipe
* Cecília de Moura Cezar Quaresma
* Josiane Cristina Marins Steiernagel
* Vitor Huugo Marcolin

## O problema que a aplicação resolve
 
Conforme exigido pela legislação federal (Leis de Licitações), o planejamento e a publicação do Plano de Contratações Anual (PCA) devem ocorrer no ano anterior à sua execução (ex: o plano de 2027 é estruturado em 2026). Durante o ano de execução, é necessário realizar o monitoramento constante desse plano, com fechamentos bimestrais.

Anteriormente, esse controle era feito de forma manual em planilhas do Excel, o que tornava o acompanhamento de resultados difícil e suscetível a falhas. A aplicação resolve esse problema centralizando e automatizando o monitoramento: o sistema consome a API pública do município para buscar as licitações publicadas, cruza esses dados para associar as licitações aos itens do PCA e fornece uma visão clara de prazos e atrasos. Além disso, permite registrar os andamentos, justificar eventuais atrasos e gerar relatórios precisos, facilitando a rotina administrativa.

## Usuários da aplicação

O sistema possui perfis de acesso divididos de acordo com a necessidade de interação:

Equipe de Monitoramento (Departamento de Licitações e Contratos): Usuários com perfil de edição. São responsáveis por cadastrar os PCAs, registrar os andamentos das fases, inserir justificativas e gerenciar as associações.

Secretarias Municipais: Usuários com perfil de leitura (read-only). Acessam a plataforma apenas para visualizar os dashboards e acompanhar o status das solicitações, sem realizar movimentações ou edições.

## Funcionalidades Principais (Entrega 2)

* **Autenticação e Acessos:** Login seguro na aplicação (AuthService) e gerenciamento/cadastro de usuários (UsuarioService).

* **Gestão Estrutural:** Cadastro das secretarias municipais no sistema (SecretariaService).

* **Gestão do PCA:** Cadastro e manutenção dos Planos de Contratações Anuais (PcaService).

* **Controle de Andamentos:** Registro detalhado da fase atual em que o PCA se encontra antes da publicação (ex: fase de Termo de Referência - TR) (AndamentoService).

* **Integração e Sincronização:** Consumo da API pública municipal para buscar e cadastrar novas licitações no banco de dados local (LicitacaoService), contando com uma rotina de execução automática em background (SincronizacaoAgendadaJob).

* **Associação Inteligente:** Sistema de recomendação que indica possíveis PCAs para licitações que foram importadas sem vínculo (PcaSugestaoService).

* **Relatórios:** Geração de relatórios consolidados com os resultados do monitoramento (RelatorioService).

## Componentes Técnicos

* **Frontend:** Interface de usuário construída em Angular 19.

* **Backend:** API construída em Java 17 utilizando o framework Spring Boot.

* **Banco de Dados:** Relacional, utilizando PostgreSQL.

## Requisitos Não Funcionais assumidos

* **Usuários simultâneos:** O sistema foi dimensionado para o uso interno municipal, suportando confortavelmente uma carga estimada entre 05 a 10 usuários simultâneos realizando operações no sistema.

* **Disponibilidade:** Alinhado com a realidade do escopo desta Entrega 2, a arquitetura atual não oferece alta disponibilidade (rodando em contêiner/instância única, sem balanceamento de carga ou replicação ativa do banco). A arquitetura, no entanto, é adequada para o momento e permite escalabilidade futura.

* **Segurança e Acesso:** A autenticação do sistema é realizada de forma segura utilizando tokens JWT. O sistema adota uma abordagem de acesso misto: as ações de edição, cadastro e movimentação exigem login autenticado, enquanto o dashboard (tela principal/index) possui acesso público, permitindo que servidores de outras secretarias visualizem os dados de acompanhamento sem necessidade de credenciais.

* **Implantação e Portabilidade:** O projeto utiliza Docker para a conteinerização tanto do frontend quanto do backend. O uso de contêineres é um requisito assumido para padronizar o ambiente e facilitar significativamente a implantação na infraestrutura local da prefeitura.

* **Interoperabilidade e Resiliência (Tolerância a falhas):** A integração via rotina automática (SincronizacaoAgendadaJob) com a API de licitações do município possui um mecanismo de resiliência e auditoria. Sempre que o sistema tenta puxar os dados, ele registra o evento no banco de dados (data e horário). Caso a API externa esteja fora do ar ou ocorra uma falha, o erro não quebra a aplicação; ele é capturado e salvo no banco para posterior análise e rastreabilidade.

* **Desempenho e Usabilidade:** O foco atual desta entrega está na exatidão do cruzamento de dados e no funcionamento das regras de negócio, não havendo ainda métricas rígidas de tempo de resposta máximo. Da mesma forma, o uso principal assumido é via computadores Desktop (padrão nas repartições públicas da prefeitura), não sendo a responsividade para dispositivos móveis uma obrigatoriedade nesta fase.