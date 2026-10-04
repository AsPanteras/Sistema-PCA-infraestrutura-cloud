## ADR 003: Isolamento em Sub-rede Privada e uso de NAT Gateway

* **Status:** Aceito
* **Contexto:** O banco de dados e as regras de negócio precisam de proteção máxima contra acesso externo direto, mas a aplicação (`LicitacaoService` / `SincronizacaoAgendadaJob`) precisa acessar constantemente a internet para consumir a API pública do Portal da Transparência (Elotech).
* **Decisão:** A instância EC2 do backend/banco foi posicionada estritamente em uma sub-rede privada, sem IP público. Para permitir a saída para a internet, foi implementado um NAT Gateway na sub-rede pública. O acesso administrativo ocorre somente via um Bastion Host (jump box).
* **Consequências:**
  * **Positivas:** Aumento significativo da segurança e diminuição da superfície de ataque, seguindo as melhores práticas de proteção de dados.
  * **Negativas:** O NAT Gateway tem um custo fixo atrelado ao tempo de existência (cobrança por hora) e ao volume de dados processados, tornando-se o ofensor de custos mais alto do projeto. Além disso, se o NAT Gateway falhar, a sincronização de dados do município para.