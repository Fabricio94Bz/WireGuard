# Fazer download do script
curl -O https://raw.githubusercontent.com/Fabricio94Bz/WireGuard/refs/heads/main/vpn-install.sh

# Ou criar manualmente
nano vpn-install.sh
# Cole o conteúdo acima e salve

# Dar permissão de execução
chmod +x vpn-install.sh

# Executar como root
sudo ./vpn-install.sh

# Adicionar primeiro cliente:
add-vpn-client meucelular

# Ver status:
vpn-status

# Remover cliente:
remove-vpn-client meucelular

Ubuntu 22.04 LTS

    ✅ Mais estável

    ✅ Melhor documentação

    ✅ Comunidade maior

    ✅ Pacotes testados