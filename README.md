# 🛡️ WireGuard VPN Installer (Ubuntu)

Instalação **100% automática** do **WireGuard VPN** em servidores **Ubuntu 20.04 / 22.04 / 24.04**  
Cria o servidor, gera chaves, configura o firewall, adiciona o primeiro cliente e inclui um utilitário para adicionar novos usuários com QR Code.

---

## 🚀 Instalação rápida

Execute este único comando no seu servidor Ubuntu:

```bash
bash <(curl -s https://raw.githubusercontent.com/Fabricio94Bz/WireGuard/main/install_wireguard.sh)

🧰 Recursos

✅ Instala e configura o WireGuard automaticamente
✅ Cria chaves privadas/públicas do servidor
✅ Gera o primeiro cliente (wg-client.conf)
✅ Gera QR Code para conectar via celular
✅ Cria o utilitário add-client.sh para novos clientes
✅ Configura firewall, NAT e IP forwarding automaticamente

📦 Estrutura
Arquivo	Função
install_wireguard.sh	Script principal de instalação
/usr/local/bin/add-client.sh	Cria novos clientes com QR Code
/etc/wireguard/wg0.conf	Configuração do servidor
/etc/wireguard/*.conf	Arquivos dos clientes

👥 Criar novos clientes

Após a instalação, use o comando: sudo add-client.sh nome_do_cliente

🧹 Remover um cliente (manual)

Para remover um cliente, edite /etc/wireguard/wg0.conf e apague o bloco:

[Peer]
PublicKey = CHAVE_PUBLICA_DO_CLIENTE
AllowedIPs = 10.8.0.X/32

Depois, reinicie o serviço: sudo systemctl restart wg-quick@wg0


🔍 Verificar status da VPN: sudo wg
🔄 Reiniciar o WireGuard: sudo systemctl restart wg-quick@wg0

#Menu
bash <(curl -s https://raw.githubusercontent.com/Fabricio94Bz/WireGuard/main/wireguard-manager.sh)




