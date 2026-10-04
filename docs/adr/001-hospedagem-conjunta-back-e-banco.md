## ADR 001: Hospedagem conjunta do Backend e Banco de Dados em uma única instância EC2

* **Status:** Aceito
* **Contexto:** A aplicação possui um volume de tráfego baixo a moderado, com um público-alvo de 5 a 10 usuários simultâneos, e restrições orçamentárias severas para o ambiente de desenvolvimento e produção. Avaliou-se o uso de um serviço de banco de dados gerenciado (Amazon RDS) e contêineres separados para a API.
* **Decisão:** Optou-se por consolidar o backend (Java/Spring Boot) e o banco de dados (PostgreSQL) em contêineres Docker executados dentro de uma única instância Amazon EC2 (`t3.medium`).
* **Consequências:**
  * **Positivas:** Redução drástica de custos em comparação com a utilização de serviços gerenciados separados; simplificação do gerenciamento de rede (comunicação interna do Docker).
  * **Negativas:** Criação de um ponto único de falha (Single Point of Failure). Se a instância EC2 cair, tanto a aplicação quanto os dados ficam indisponíveis. Exige a criação de rotinas manuais de backup do banco de dados e manutenção do SO.
