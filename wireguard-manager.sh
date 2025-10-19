#!/bin/bash
chmod +x "$0" 2>/dev/null
# ===========================================
# WireGuard VPN Manager - Instalação e Gestão
# Compatível com Ubuntu 20.04 / 22.04 / 24.04
# Autor: ChatGPT (GPT-5)
# ===========================================

WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/wg0.conf"
ADD_CLIENT_SCRIPT="/usr/local/bin/add-client.sh"
PORT=51820

# ---------- Funções ----------

install_wireguard() {
    echo "🛠️ Instalando o WireGuard..."
    apt update && apt install -y wireguard qrencode ufw curl

    mkdir -p ${WG_DIR}
    cd ${WG_DIR}
    umask 077

    wg genkey | tee server_private.key | wg pubkey > server_public.key
    SERVER_PRIV=$(cat server_private.key)
    SERVER_PUB=$(cat server_public.key)
    IFACE=$(ip route show default | awk '/default/ {print $5}')
    SERVER_IP="10.8.0.1"
    SERVER_PUBLIC_IP=$(curl -s ifconfig.me || echo "SEU_IP_PUBLICO")

    cat > ${WG_CONF} <<EOF
[Interface]
Address = ${SERVER_IP}/24
ListenPort = ${PORT}
PrivateKey = ${SERVER_PRIV}

PostUp = iptables -t nat -A POSTROUTING -o ${IFACE} -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o ${IFACE} -j MASQUERADE
EOF

    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sysctl -p

    ufw allow ${PORT}/udp
    ufw allow OpenSSH
    ufw --force enable

    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0

    echo "✅ WireGuard instalado e rodando!"
}

add_client() {
    if [ ! -f "${WG_CONF}" ]; then
        echo "❌ WireGuard não está instalado."
        return
    fi

    read -p "Digite o nome do novo cliente: " NAME
    CLIENT_PRIV=$(wg genkey)
    CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
    SERVER_PUB=$(cat ${WG_DIR}/server_public.key)
    SERVER_IP=$(curl -s ifconfig.me)
    PORT=$(grep ListenPort ${WG_CONF} | awk '{print $3}')
    DNS="1.1.1.1"

    CLIENT_IP=$(grep AllowedIPs ${WG_CONF} | tail -n 1 | awk '{print $3}' | cut -d'.' -f4 | cut -d'/' -f1)
    NEXT_IP=$((CLIENT_IP + 1))
    CLIENT_ADDR="10.8.0.${NEXT_IP}"

    echo "Criando cliente $NAME com IP ${CLIENT_ADDR}..."

    echo -e "\n[Peer]\nPublicKey = ${CLIENT_PUB}\nAllowedIPs = ${CLIENT_ADDR}/32" >> ${WG_CONF}

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
    echo "✅ Cliente criado com sucesso!"
    qrencode -t ansiutf8 < ${WG_DIR}/${NAME}.conf
}

remove_client() {
    if [ ! -f "${WG_CONF}" ]; then
        echo "❌ WireGuard não está instalado."
        return
    fi

    read -p "Digite o nome do cliente a remover: " NAME
    if [ ! -f "${WG_DIR}/${NAME}.conf" ]; then
        echo "❌ Cliente não encontrado."
        return
    fi

    CLIENT_PUB=$(grep -A1 "\[Interface\]" ${WG_DIR}/${NAME}.conf | grep PrivateKey | awk '{print $3}' | wg pubkey 2>/dev/null)
    if [ -z "$CLIENT_PUB" ]; then
        echo "Removendo cliente pelo nome direto..."
        CLIENT_PUB=$(grep -A2 "${NAME}" ${WG_CONF} | grep PublicKey | awk '{print $3}')
    fi

    if [ -n "$CLIENT_PUB" ]; then
        sed -i "/PublicKey = ${CLIENT_PUB}/,+1d" ${WG_CONF}
        systemctl restart wg-quick@wg0
    fi

    rm -f ${WG_DIR}/${NAME}.conf
    echo "✅ Cliente ${NAME} removido!"
}

list_clients() {
    echo "📋 Clientes configurados:"
    grep "AllowedIPs" ${WG_CONF} | awk '{print $3}'
    echo
    echo "📡 Conectados atualmente:"
    wg show | grep "peer" || echo "Nenhum cliente conectado."
}

uninstall_wireguard() {
    echo "⚠️ Isso removerá completamente o WireGuard e suas configurações."
    read -p "Tem certeza? (y/N): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        systemctl stop wg-quick@wg0
        apt remove --purge -y wireguard
        rm -rf /etc/wireguard
        rm -f /usr/local/bin/add-client.sh
        echo "✅ WireGuard removido completamente."
    else
        echo "❎ Cancelado."
    fi
}

# ---------- Menu Interativo ----------

while true; do
    clear
    echo "====================================="
    echo "  🛡️  WireGuard VPN Manager (Ubuntu)"
    echo "====================================="
    echo "1) Instalar WireGuard"
    echo "2) Adicionar novo cliente"
    echo "3) Remover cliente"
    echo "4) Listar clientes e status"
    echo "5) Desinstalar WireGuard"
    echo "0) Sair"
    echo "-------------------------------------"
    read -p "Escolha uma opção: " OPTION

    case $OPTION in
        1) install_wireguard ;;
        2) add_client ;;
        3) remove_client ;;
        4) list_clients ;;
        5) uninstall_wireguard ;;
        0) echo "Saindo..."; exit 0 ;;
        *) echo "Opção inválida."; sleep 1 ;;
    esac
    read -p "Pressione Enter para voltar ao menu..."
done
