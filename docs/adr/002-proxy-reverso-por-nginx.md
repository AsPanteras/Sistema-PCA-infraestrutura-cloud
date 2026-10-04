## ADR 002: Remoção do API Gateway e adoção de Proxy Reverso via Nginx (ECS Fargate)

* **Status:** Aceito
* **Contexto:** Inicialmente, cogitou-se o uso do AWS API Gateway para gerenciar e rotear as requisições externas para o backend na rede privada.
* **Decisão:** O API Gateway foi removido do desenho para simplificar a arquitetura e otimizar o orçamento. A responsabilidade de roteamento foi transferida para o serviço de Frontend. O contêiner hospedado no AWS Fargate (ECS) executa o Nginx, que serve os arquivos estáticos do Angular e atua como proxy reverso, encaminhando as requisições de API diretamente para a porta 8080 do backend na sub-rede privada.
* **Consequências:**
  * **Positivas:** Redução de custos diretos e da complexidade da infraestrutura AWS. Centralização das configurações de rotas de fronteira no próprio código do frontend.
  * **Negativas:** O contêiner de frontend assume uma responsabilidade dupla (servidor web e proxy de API), o que consome ligeiramente mais recursos locais no Fargate.