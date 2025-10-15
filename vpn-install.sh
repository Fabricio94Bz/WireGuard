#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Por favor, execute como root: sudo ./vpn-install.sh${NC}"
    exit 1
fi

echo -e "${GREEN}
===================================================
         INSTALADOR AUTOMÁTICO DE VPN
               WIREGUARD UBUNTU
===================================================
${NC}"

# Function to log messages
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Function to handle errors
error() {
    echo -e "${RED}[ERRO] $1${NC}"
    exit 1
}

# Update system
log "Atualizando sistema..."
apt update && apt upgrade -y || error "Falha ao atualizar sistema"

# Install required packages
log "Instalando dependências..."
apt install -y wireguard wireguard-tools qrencode iptables-persistent || error "Falha ao instalar dependências"

# Enable IP forwarding
log "Configurando IP forwarding..."
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p || error "Falha ao configurar IP forwarding"

# Create WireGuard directory
log "Criando diretório do WireGuard..."
mkdir -p /etc/wireguard/clients
cd /etc/wireguard

# Generate server keys
log "Gerando chaves do servidor..."
umask 077
wg genkey | tee privatekey | wg pubkey > publickey

# Get server public key
SERVER_PUBLIC_KEY=$(cat publickey)
SERVER_PRIVATE_KEY=$(cat privatekey)

# Get server public IP
SERVER_IP=$(curl -4 -s ifconfig.co)

# Determine network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# Create server configuration
log "Criando configuração do servidor..."
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = 10.0.0.1/24
ListenPort = 51820
SaveConfig = false
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE

EOF

# Configure firewall
log "Configurando firewall..."
ufw allow 51820/udp comment "WireGuard VPN"
ufw allow ssh comment "SSH"
ufw --force enable

# Start WireGuard service
log "Iniciando serviço WireGuard..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Create client management script
log "Criando script de gerenciamento de clientes..."
cat > /usr/local/bin/add-vpn-client << 'EOF'
#!/bin/bash

if [ -z "$1" ]; then
    echo "Uso: add-vpn-client <nome-do-cliente>"
    exit 1
fi

CLIENT_NAME=$1
WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"

# Get next available IP
CLIENT_IP="10.0.0.$((2 + $(ls -1q $CLIENTS_DIR/*.conf 2>/dev/null | wc -l)))"

# Generate client keys
mkdir -p $CLIENTS_DIR
cd $CLIENTS_DIR
wg genkey | tee $CLIENT_NAME-private.key | wg pubkey > $CLIENT_NAME-public.key

CLIENT_PRIVATE_KEY=$(cat $CLIENT_NAME-private.key)
CLIENT_PUBLIC_KEY=$(cat $CLIENT_NAME-public.key)
SERVER_PUBLIC_KEY=$(cat $WG_DIR/publickey)
SERVER_IP=$(curl -4 -s ifconfig.co)

# Create client configuration
cat > $CLIENT_NAME.conf << CLIENTEOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_IP:51820
AllowedIPs = 0.0.0.0/0
CLIENTEOF

# Add client to server
wg set wg0 peer $CLIENT_PUBLIC_KEY allowed-ips $CLIENT_IP

# Generate QR code
qrencode -t ansiutf8 < $CLIENT_NAME.conf

echo "==================================================="
echo "Cliente '$CLIENT_NAME' criado com sucesso!"
echo "IP: $CLIENT_IP"
echo "Arquivo: $CLIENTS_DIR/$CLIENT_NAME.conf"
echo "==================================================="
echo "Para revogar: wg set wg0 peer $CLIENT_PUBLIC_KEY remove"
echo "==================================================="
EOF

# Make client script executable
chmod +x /usr/local/bin/add-vpn-client

# Create remove client script
cat > /usr/local/bin/remove-vpn-client << 'EOF'
#!/bin/bash

if [ -z "$1" ]; then
    echo "Uso: remove-vpn-client <nome-do-cliente>"
    exit 1
fi

CLIENT_NAME=$1
WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"

if [ ! -f "$CLIENTS_DIR/$CLIENT_NAME-public.key" ]; then
    echo "Cliente $CLIENT_NAME não encontrado!"
    exit 1
fi

CLIENT_PUBLIC_KEY=$(cat $CLIENTS_DIR/$CLIENT_NAME-public.key)

# Remove client from server
wg set wg0 peer $CLIENT_PUBLIC_KEY remove

# Remove client files
rm -f $CLIENTS_DIR/$CLIENT_NAME-*.key
rm -f $CLIENTS_DIR/$CLIENT_NAME.conf

echo "Cliente $CLIENT_NAME removido com sucesso!"
EOF

chmod +x /usr/local/bin/remove-vpn-client

# Create status script
cat > /usr/local/bin/vpn-status << 'EOF'
#!/bin/bash

echo "=== Status do Servidor WireGuard ==="
wg show

echo -e "\n=== Clientes Conectados ==="
wg show wg0 transfers

echo -e "\n=== Configuração do Servidor ==="
echo "Endpoint: $(curl -4 -s ifconfig.co):51820"
echo "Chave Pública: $(cat /etc/wireguard/publickey)"
EOF

chmod +x /usr/local/bin/vpn-status

# Display completion message
echo -e "${GREEN}
===================================================
         INSTALAÇÃO CONCLUÍDA COM SUCESSO!
===================================================

${YELLOW}INFORMAÇÕES DO SERVIDOR:${NC}
- Endpoint: ${SERVER_IP}:51820
- Interface: wg0
- Rede: 10.0.0.0/24

${YELLOW}COMANDOS DISPONÍVEIS:${NC}
- add-vpn-client <nome>    - Adicionar novo cliente
- remove-vpn-client <nome> - Remover cliente
- vpn-status               - Ver status da VPN

${YELLOW}PRÓXIMOS PASSOS:${NC}
1. Adicione um cliente: ${GREEN}add-vpn-client meu-celular${NC}
2. Escaneie o QR code com app WireGuard
3. Ou use o arquivo .conf no cliente

${YELLOW}APPS WIREGUARD:${NC}
- Android: Play Store
- iOS: App Store  
- Windows: Microsoft Store
- macOS: App Store
- Linux: pacote 'wireguard'

===================================================
${NC}"

# Start services
systemctl restart wg-quick@wg0

log "Instalação finalizada!"