#!/bin/bash
chmod +x "$0" 2>/dev/null
# ===========================================
# Instalação automática do WireGuard VPN + gerador de clientes
# Compatível com Ubuntu 20.04 / 22.04 / 24.04
# Autor: ChatGPT (GPT-5)
# ===========================================

set -e

SERVER_PORT=51820
SERVER_WG_INTERFACE="wg0"
SERVER_NETWORK="10.8.0.0/24"
SERVER_IP="10.8.0.1"
FIRST_CLIENT="wg-client"
IFACE=$(ip route show default | awk '/default/ {print $5}')

echo "=== WireGuard VPN Installer ==="
sleep 1

# ---- Atualiza o sistema ----
echo "[1/9] Atualizando sistema..."
apt update && apt upgrade -y

# ---- Instala pacotes ----
echo "[2/9] Instalando pacotes necessários..."
apt install -y wireguard qrencode ufw curl

# ---- Gera chaves do servidor ----
echo "[3/9] Gerando chaves do servidor..."
mkdir -p /etc/wireguard
cd /etc/wireguard
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key
SERVER_PRIVKEY=$(cat server_private.key)
SERVER_PUBKEY=$(cat server_public.key)

# ---- Cria arquivo de configuração do servidor ----
echo "[4/9] Criando configuração do servidor..."
cat > /etc/wireguard/${SERVER_WG_INTERFACE}.conf <<EOF
[Interface]
Address = ${SERVER_IP}/24
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIVKEY}

PostUp = iptables -t nat -A POSTROUTING -o ${IFACE} -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o ${IFACE} -j MASQUERADE
EOF

# ---- Ativa encaminhamento de IP ----
echo "[5/9] Habilitando IP forwarding..."
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# ---- Configura firewall ----
echo "[6/9] Configurando firewall..."
ufw allow ${SERVER_PORT}/udp
ufw allow OpenSSH
ufw --force enable

# ---- Ativa o serviço ----
echo "[7/9] Ativando WireGuard..."
systemctl enable wg-quick@${SERVER_WG_INTERFACE}
systemctl start wg-quick@${SERVER_WG_INTERFACE}

# ---- Detecta IP público ----
SERVER_PUBLIC_IP=$(curl -s ifconfig.me || echo "SEU_IP_PUBLICO")

# ---- Cria primeiro cliente ----
echo "[8/9] Criando cliente padrão (${FIRST_CLIENT})..."
CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)

cat >> /etc/wireguard/${SERVER_WG_INTERFACE}.conf <<EOF

[Peer]
PublicKey = ${CLIENT_PUB}
AllowedIPs = 10.8.0.2/32
EOF

cat > /etc/wireguard/${FIRST_CLIENT}.conf <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = 10.8.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBKEY}
Endpoint = ${SERVER_PUBLIC_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

systemctl restart wg-quick@${SERVER_WG_INTERFACE}

# ---- Cria o script add-client.sh ----
echo "[9/9] Criando utilitário add-client.sh..."
cat > /usr/local/bin/add-client.sh <<'EOC'
#!/bin/bash
# Gerador de novos clientes WireGuard

WG_DIR="/etc/wireguard"
SERVER_CONF="${WG_DIR}/wg0.conf"
SERVER_PUB=$(cat ${WG_DIR}/server_public.key)
SERVER_IP=$(curl -s ifconfig.me)
PORT=$(grep ListenPort ${SERVER_CONF} | awk '{print $3}')
DNS="1.1.1.1"

if [ -z "$1" ]; then
  echo "Uso: sudo add-client.sh nome_do_cliente"
  exit 1
fi

NAME=$1
CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
CLIENT_IP=$(grep AllowedIPs ${SERVER_CONF} | tail -n 1 | awk '{print $3}' | cut -d'.' -f4 | cut -d'/' -f1)
NEXT_IP=$((CLIENT_IP + 1))
CLIENT_ADDR="10.8.0.${NEXT_IP}"

echo "Criando cliente $NAME com IP ${CLIENT_ADDR}..."

# Adiciona cliente ao servidor
echo -e "\n[Peer]\nPublicKey = ${CLIENT_PUB}\nAllowedIPs = ${CLIENT_ADDR}/32" >> ${SERVER_CONF}

# Cria arquivo do cliente
cat > ${WG_DIR}/${NAME}.conf <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = ${CLIENT_ADDR}/24
DNS = ${DNS}

[Peer]
PublicKey = ${SERVER_PUB}
Endpoint = ${SERVER_IP}:${PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

systemctl restart wg-quick@wg0
echo
echo "Cliente criado com sucesso!"
echo "Arquivo: ${WG_DIR}/${NAME}.conf"
echo "QR Code:"
qrencode -t ansiutf8 < ${WG_DIR}/${NAME}.conf
EOC

chmod +x /usr/local/bin/add-client.sh

echo
echo "=== ✅ WireGuard instalado com sucesso! ==="
echo "Cliente inicial: /etc/wireguard/${FIRST_CLIENT}.conf"
echo
qrencode -t ansiutf8 < /etc/wireguard/${FIRST_CLIENT}.conf
echo
echo "Para criar novos clientes:"
echo "  sudo add-client.sh nome_do_cliente"
echo
echo "Para ver status:"
echo "  sudo wg"
echo
echo "Reinicie o servidor para finalizar a instalação: sudo reboot"
