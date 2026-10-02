-- Exemplo de ADR:

# ADR-004: Armazenamento das fotos enviadas pelos usuários
No contexto de uma aplicação que recebe fotos enviadas pelos usuários,
diante da necessidade de que os arquivos sobrevivam à recriação da instância,
decidimos armazená-los em object storage (Amazon S3),
e descartamos o disco local da instância e um volume em bloco dedicado,
para que destruir e recriar a VM não apague os arquivos,
aceitando que a aplicação passa a depender de permissões de acesso ao bucket e que o tráfego da sub-rede privada até o bucket passa pelo NAT e é cobrado.

