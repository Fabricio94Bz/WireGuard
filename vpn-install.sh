#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Paths
WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"
SERVER_CONFIG="$WG_DIR/wg0.conf"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Por favor, execute como root: sudo ./vpn-complete-setup.sh${NC}"
    exit 1
fi

# Function to log messages
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Function to handle errors
error() {
    echo -e "${RED}[ERRO] $1${NC}"
    exit 1
}

# Function to display header
header() {
    clear
    echo -e "${GREEN}"
    echo "==================================================="
    echo "         INSTALADOR COMPLETO WIREGUARD VPN"
    echo "             + MENU DE GERENCIAMENTO"
    echo "==================================================="
    echo -e "${NC}"
}

# Function to pause
pause() {
    echo -e "${YELLOW}"
    read -p "Pressione Enter para continuar..."
    echo -e "${NC}"
}

# =============================================================================
# INSTALAÇÃO DO WIREGUARD
# =============================================================================

install_wireguard() {
    header
    echo -e "${CYAN}=== INICIANDO INSTALAÇÃO DO WIREGUARD ===${NC}"
    echo ""
    
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
    mkdir -p $CLIENTS_DIR
    cd $WG_DIR
    
    # Generate server keys
    log "Gerando chaves do servidor..."
    umask 077
    wg genkey | tee privatekey | wg pubkey > publickey
    
    SERVER_PRIVATE_KEY=$(cat privatekey)
    
    # Determine network interface
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    [ -z "$INTERFACE" ] && INTERFACE="eth0"
    
    # Create server configuration
    log "Criando configuração do servidor..."
    cat > $SERVER_CONFIG << EOF
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
    
    # Wait for service to start
    sleep 3
}

# =============================================================================
# MENU DE GERENCIAMENTO
# =============================================================================

# Function to get server info
get_server_info() {
    SERVER_IP=$(curl -4 -s ifconfig.co)
    SERVER_PUBLIC_KEY=$(cat $WG_DIR/publickey 2>/dev/null)
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
}

# Function to list clients
list_clients() {
    header
    echo -e "${CYAN}=== CLIENTES VPN CONFIGURADOS ===${NC}"
    echo ""
    
    if [ ! -d "$CLIENTS_DIR" ] || [ -z "$(ls -A $CLIENTS_DIR/*.conf 2>/dev/null)" ]; then
        echo -e "${YELLOW}Nenhum cliente configurado.${NC}"
        return
    fi
    
    echo -e "${BLUE}Nome do Cliente        IP Address       Status${NC}"
    echo "---------------------------------------------------"
    
    for client_file in $CLIENTS_DIR/*.conf; do
        if [ -f "$client_file" ]; then
            client_name=$(basename "$client_file" .conf)
            client_ip=$(grep "Address" "$client_file" | awk '{print $3}' | cut -d'/' -f1)
            client_private_key=$(grep "PrivateKey" "$client_file" | awk '{print $3}')
            client_public_key=$(echo "$client_private_key" | wg pubkey 2>/dev/null)
            
            # Check if client is connected
            if wg show wg0 2>/dev/null | grep -q "$client_public_key"; then
                status="${GREEN}● Conectado${NC}"
            else
                status="${RED}● Desconectado${NC}"
            fi
            
            printf "%-20s %-15s %s\n" "$client_name" "$client_ip" "$status"
        fi
    done
    
    echo ""
    echo -e "${CYAN}Total de clientes: $(ls -1 $CLIENTS_DIR/*.conf 2>/dev/null | wc -l)${NC}"
}

# Function to add client
add_client() {
    header
    echo -e "${CYAN}=== ADICIONAR NOVO CLIENTE ===${NC}"
    echo ""
    
    read -p "Nome do cliente (sem espaços): " client_name
    
    if [ -z "$client_name" ]; then
        echo -e "${RED}Nome do cliente não pode estar vazio.${NC}"
        pause
        return
    fi
    
    if [ -f "$CLIENTS_DIR/$client_name.conf" ]; then
        echo -e "${RED}Cliente '$client_name' já existe.${NC}"
        pause
        return
    fi
    
    # Get next available IP
    last_ip=1
    for client_file in $CLIENTS_DIR/*.conf; do
        if [ -f "$client_file" ]; then
            ip=$(grep "Address" "$client_file" | awk '{print $3}' | cut -d'.' -f4 | cut -d'/' -f1)
            if [ "$ip" -gt "$last_ip" ]; then
                last_ip=$ip
            fi
        fi
    done
    client_ip="10.0.0.$((last_ip + 1))"
    
    # Generate client keys
    mkdir -p $CLIENTS_DIR
    cd $CLIENTS_DIR
    
    wg genkey | tee $client_name-private.key | wg pubkey > $client_name-public.key
    
    client_private_key=$(cat $client_name-private.key)
    client_public_key=$(cat $client_name-public.key)
    server_public_key=$(cat $WG_DIR/publickey)
    server_ip=$(curl -4 -s ifconfig.co)
    
    # Create client configuration
    cat > $client_name.conf << EOF
[Interface]
PrivateKey = $client_private_key
Address = $client_ip/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $server_public_key
Endpoint = $server_ip:51820
AllowedIPs = 0.0.0.0/0
EOF

    # Add client to server
    wg set wg0 peer $client_public_key allowed-ips $client_ip
    
    echo ""
    echo -e "${GREEN}Cliente '$client_name' criado com sucesso!${NC}"
    echo -e "${YELLOW}IP: $client_ip${NC}"
    echo ""
    
    # Display QR code
    echo -e "${CYAN}=== QR CODE PARA O CLIENTE ===${NC}"
    qrencode -t ansiutf8 < $client_name.conf
    
    echo ""
    echo -e "${CYAN}=== CONFIGURAÇÃO DO CLIENTE ===${NC}"
    cat $client_name.conf
    
    echo ""
    echo -e "${YELLOW}Arquivo de configuração: $CLIENTS_DIR/$client_name.conf${NC}"
    echo -e "${YELLOW}Use o QR code ou o arquivo de configuração no app WireGuard${NC}"
    
    pause
}

# Function to remove client
remove_client() {
    header
    echo -e "${CYAN}=== REMOVER CLIENTE ===${NC}"
    echo ""
    
    if [ ! -d "$CLIENTS_DIR" ] || [ -z "$(ls -A $CLIENTS_DIR/*.conf 2>/dev/null)" ]; then
        echo -e "${YELLOW}Nenhum cliente configurado.${NC}"
        pause
        return
    fi
    
    echo "Clientes disponíveis:"
    echo "---------------------"
    for client_file in $CLIENTS_DIR/*.conf; do
        client_name=$(basename "$client_file" .conf)
        echo " - $client_name"
    done
    echo ""
    
    read -p "Nome do cliente a remover: " client_name
    
    if [ -z "$client_name" ]; then
        echo -e "${RED}Nome do cliente não pode estar vazio.${NC}"
        pause
        return
    fi
    
    if [ ! -f "$CLIENTS_DIR/$client_name.conf" ]; then
        echo -e "${RED}Cliente '$client_name' não encontrado.${NC}"
        pause
        return
    fi
    
    # Get client public key
    client_private_key=$(grep "PrivateKey" "$CLIENTS_DIR/$client_name.conf" | awk '{print $3}')
    client_public_key=$(echo "$client_private_key" | wg pubkey)
    
    # Remove client from server
    wg set wg0 peer $client_public_key remove
    
    # Remove client files
    rm -f $CLIENTS_DIR/$client_name-*.key
    rm -f $CLIENTS_DIR/$client_name.conf
    
    echo -e "${GREEN}Cliente '$client_name' removido com sucesso!${NC}"
    
    pause
}

# Function to show client config
show_client_config() {
    header
    echo -e "${CYAN}=== CONFIGURAÇÃO DO CLIENTE ===${NC}"
    echo ""
    
    if [ ! -d "$CLIENTS_DIR" ] || [ -z "$(ls -A $CLIENTS_DIR/*.conf 2>/dev/null)" ]; then
        echo -e "${YELLOW}Nenhum cliente configurado.${NC}"
        pause
        return
    fi
    
    echo "Clientes disponíveis:"
    echo "---------------------"
    for client_file in $CLIENTS_DIR/*.conf; do
        client_name=$(basename "$client_file" .conf)
        echo " - $client_name"
    done
    echo ""
    
    read -p "Nome do cliente: " client_name
    
    if [ -z "$client_name" ]; then
        echo -e "${RED}Nome do cliente não pode estar vazio.${NC}"
        pause
        return
    fi
    
    if [ ! -f "$CLIENTS_DIR/$client_name.conf" ]; then
        echo -e "${RED}Cliente '$client_name' não encontrado.${NC}"
        pause
        return
    fi
    
    echo ""
    echo -e "${CYAN}=== CONFIGURAÇÃO: $client_name ===${NC}"
    cat "$CLIENTS_DIR/$client_name.conf"
    
    echo ""
    echo -e "${CYAN}=== QR CODE ===${NC}"
    qrencode -t ansiutf8 < "$CLIENTS_DIR/$client_name.conf"
    
    pause
}

# Function to show server status
show_server_status() {
    header
    echo -e "${CYAN}=== STATUS DO SERVIDOR ===${NC}"
    echo ""
    
    get_server_info
    
    echo -e "${BLUE}Informações do Servidor:${NC}"
    echo "-----------------------------"
    echo -e "IP Público: ${YELLOW}$SERVER_IP${NC}"
    echo -e "Porta: ${YELLOW}51820${NC}"
    echo -e "Interface: ${YELLOW}wg0${NC}"
    echo -e "Interface de Rede: ${YELLOW}$INTERFACE${NC}"
    echo ""
    
    echo -e "${BLUE}Status do WireGuard:${NC}"
    echo "---------------------"
    wg show
    
    echo ""
    echo -e "${BLUE}Conexões Ativas:${NC}"
    echo "------------------"
    wg show wg0 transfers
    
    pause
}

# Function to restart service
restart_service() {
    header
    echo -e "${CYAN}=== REINICIAR SERVIÇO WIREGUARD ===${NC}"
    echo ""
    
    systemctl restart wg-quick@wg0
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Serviço reiniciado com sucesso!${NC}"
    else
        echo -e "${RED}Erro ao reiniciar o serviço.${NC}"
    fi
    
    pause
}

# Function to show statistics
show_statistics() {
    header
    echo -e "${CYAN}=== ESTATÍSTICAS DA VPN ===${NC}"
    echo ""
    
    total_clients=$(ls -1 $CLIENTS_DIR/*.conf 2>/dev/null | wc -l)
    connected_clients=$(wg show wg0 2>/dev/null | grep "peer:" | wc -l)
    
    echo -e "${BLUE}Resumo:${NC}"
    echo "-------"
    echo -e "Total de clientes: ${YELLOW}$total_clients${NC}"
    echo -e "Clientes conectados: ${YELLOW}$connected_clients${NC}"
    echo -e "Clientes offline: ${YELLOW}$((total_clients - connected_clients))${NC}"
    echo ""
    
    if [ $connected_clients -gt 0 ]; then
        echo -e "${BLUE}Clientes Conectados:${NC}"
        echo "-------------------"
        wg show wg0 | grep "peer:" | while read line; do
            peer_key=$(echo $line | awk '{print $2}')
            for client_file in $CLIENTS_DIR/*.conf; do
                client_private_key=$(grep "PrivateKey" "$client_file" | awk '{print $3}')
                client_public_key=$(echo "$client_private_key" | wg pubkey)
                if [ "$client_public_key" = "$peer_key" ]; then
                    client_name=$(basename "$client_file" .conf)
                    echo -e "${GREEN}✓ $client_name${NC}"
                fi
            done
        done
    fi
    
    echo ""
    echo -e "${BLUE}Uso de Transferência:${NC}"
    echo "----------------------"
    wg show wg0 transfers
    
    pause
}

# Main management menu
management_menu() {
    while true; do
        header
        echo -e "${BLUE}MENU PRINCIPAL - GERENCIADOR VPN${NC}"
        echo ""
        echo -e "${GREEN}1. ${NC}Listar clientes"
        echo -e "${GREEN}2. ${NC}Adicionar cliente"
        echo -e "${GREEN}3. ${NC}Remover cliente"
        echo -e "${GREEN}4. ${NC}Ver configuração do cliente"
        echo -e "${GREEN}5. ${NC}Status do servidor"
        echo -e "${GREEN}6. ${NC}Estatísticas da VPN"
        echo -e "${GREEN}7. ${NC}Reiniciar serviço"
        echo -e "${RED}8. ${NC}Sair do menu"
        echo ""
        read -p "Selecione uma opção [1-8]: " choice
        
        case $choice in
            1) list_clients ;;
            2) add_client ;;
            3) remove_client ;;
            4) show_client_config ;;
            5) show_server_status ;;
            6) show_statistics ;;
            7) restart_service ;;
            8) 
                echo -e "${GREEN}Retornando...${NC}"
                break
                ;;
            *) 
                echo -e "${RED}Opção inválida!${NC}"
                pause
                ;;
        esac
    done
}

# =============================================================================
# INSTALAÇÃO DO MENU DE GERENCIAMENTO
# =============================================================================

install_management_menu() {
    log "Instalando menu de gerenciamento..."
    
    # Create management script
    cat > /usr/local/bin/vpn-manager << 'EOF'
#!/bin/bash
# Este script é instalado automaticamente pelo vpn-complete-setup.sh
# Use o script original para gerenciamento completo
/usr/local/bin/vpn-complete-setup.sh menu
EOF

    # Make executable
    chmod +x /usr/local/bin/vpn-manager
    
    log "Menu de gerenciamento instalado em /usr/local/bin/vpn-manager"
}

# =============================================================================
# FUNÇÃO PRINCIPAL
# =============================================================================

main() {
    header
    
    # Check if WireGuard is already installed
    if [ -f "$SERVER_CONFIG" ]; then
        echo -e "${YELLOW}WireGuard já está instalado.${NC}"
        echo ""
        echo "O que você gostaria de fazer?"
        echo ""
        echo -e "${GREEN}1. ${NC}Abrir menu de gerenciamento"
        echo -e "${GREEN}2. ${NC}Reinstalar WireGuard (ATENÇÃO: apaga configurações existentes)"
        echo -e "${RED}3. ${NC}Sair"
        echo ""
        read -p "Selecione [1-3]: " choice
        
        case $choice in
            1) 
                management_menu
                ;;
            2)
                echo -e "${RED}Isso irá remover todas as configurações existentes!${NC}"
                read -p "Continuar? (s/N): " confirm
                if [[ $confirm =~ ^[Ss]$ ]]; then
                    systemctl stop wg-quick@wg0 2>/dev/null
                    systemctl disable wg-quick@wg0 2>/dev/null
                    rm -rf $WG_DIR
                    install_wireguard
                    install_management_menu
                    show_final_instructions
                fi
                ;;
            3)
                exit 0
                ;;
            *)
                echo -e "${RED}Opção inválida${NC}"
                exit 1
                ;;
        esac
    else
        # Fresh installation
        install_wireguard
        install_management_menu
        show_final_instructions
    fi
}

# Function to show final instructions
show_final_instructions() {
    header
    echo -e "${GREEN}
===================================================
         INSTALAÇÃO CONCLUÍDA COM SUCESSO!
===================================================

${YELLOW}INFORMAÇÕES DO SERVIDOR:${NC}
- Endpoint: $(curl -4 -s ifconfig.co):51820
- Interface: wg0
- Rede: 10.0.0.0/24

${YELLOW}COMANDOS DISPONÍVEIS:${NC}
- ${GREEN}vpn-manager${NC}          - Menu interativo de gerenciamento
- ${GREEN}sudo vpn-complete-setup.sh${NC} - Script completo (instalação + menu)

${YELLOW}PRÓXIMOS PASSOS:${NC}
1. Execute: ${GREEN}vpn-manager${NC}
2. Adicione clientes pelo menu
3. Use QR code ou arquivos .conf nos clientes

${YELLOW}APPS WIREGUARD:${NC}
- Android: Play Store
- iOS: App Store  
- Windows: Microsoft Store
- macOS: App Store
- Linux: pacote 'wireguard-tools'

===================================================
${NC}"

    # Start management menu
    echo ""
    read -p "Abrir menu de gerenciamento agora? (s/N): " open_menu
    if [[ $open_menu =~ ^[Ss]$ ]]; then
        management_menu
    else
        echo -e "${GREEN}Execute 'vpn-manager' a qualquer momento para gerenciar sua VPN.${NC}"
    fi
}

# Handle command line arguments
case "${1:-}" in
    "menu")
        management_menu
        ;;
    "install")
        install_wireguard
        install_management_menu
        show_final_instructions
        ;;
    "status")
        show_server_status
        ;;
    *)
        main
        ;;
esac