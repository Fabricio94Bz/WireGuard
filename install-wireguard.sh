#!/bin/bash

# Script de instalação automatizada do WireGuard VPN Server
# Autor: Auto-generated
# Versão: 1.3 (Corrigida)

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para imprimir mensagens coloridas
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função para verificar se é root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "Este script não deve ser executado como root. Use com sudo."
        exit 1
    fi
}

# Função para verificar se está no Ubuntu
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Sistema operacional não identificado."
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "Este script é destinado apenas para Ubuntu."
        exit 1
    fi
}

# Função para verificar conectividade com a internet
check_internet() {
    print_status "Verificando conectividade com a internet..."
    if ! ping -c 1 -W 1 8.8.8.8 &> /dev/null && ! ping -c 1 -W 1 1.1.1.1 &> /dev/null; then
        print_warning "Sem conexão com a internet. Algumas funcionalidades podem não funcionar."
        read -p "Deseja continuar mesmo assim? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            exit 1
        fi
    else
        print_success "Conectividade com internet verificada."
    fi
}

# Função para atualizar o sistema
update_system() {
    print_status "Atualizando o sistema..."
    sudo apt update && sudo apt upgrade -y
    if [ $? -ne 0 ]; then
        print_error "Falha ao atualizar o sistema."
        exit 1
    fi
    print_success "Sistema atualizado com sucesso."
}

# Função para instalar WireGuard
install_wireguard() {
    print_status "Instalando WireGuard..."
    
    # Verificar se WireGuard já está instalado
    if command -v wg &> /dev/null && command -v wg-quick &> /dev/null; then
        print_warning "WireGuard já está instalado."
        return 0
    fi
    
    # Instalar WireGuard e dependências
    sudo apt install -y wireguard-tools resolvconf qrencode net-tools curl
    
    if [ $? -ne 0 ]; then
        print_error "Falha ao instalar WireGuard."
        exit 1
    fi
    
    # Habilitar módulo do kernel
    sudo modprobe wireguard
    
    print_success "WireGuard instalado com sucesso."
}

# Função para configurar IP forwarding
setup_ip_forwarding() {
    print_status "Configurando IP forwarding..."
    
    # Verificar se já está configurado
    if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        print_warning "IP forwarding já está configurado."
    else
        echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p
        if [ $? -ne 0 ]; then
            print_error "Falha ao configurar IP forwarding."
            exit 1
        fi
        print_success "IP forwarding configurado."
    fi
}

# Função para configurar firewall
setup_firewall() {
    print_status "Configurando firewall (UFW)..."
    
    # Obter porta do usuário ou usar padrão
    read -p "Digite a porta para WireGuard (padrão: 51820): " WG_PORT
    WG_PORT=${WG_PORT:-51820}
    
    # Obter interface de rede principal
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    read -p "Digite a interface de rede principal (padrão: $DEFAULT_INTERFACE): " NET_INTERFACE
    NET_INTERFACE=${NET_INTERFACE:-$DEFAULT_INTERFACE}
    
    if [[ -z "$NET_INTERFACE" ]]; then
        print_error "Não foi possível determinar a interface de rede."
        exit 1
    fi
    
    # Verificar se UFW está instalado, se não, instalar
    if ! command -v ufw &> /dev/null; then
        print_status "UFW não encontrado, instalando..."
        sudo apt install -y ufw
    fi
    
    # Configurar regras UFW
    sudo ufw allow $WG_PORT/udp
    sudo ufw allow ssh
    
    # Configurar regras de forwarding
    sudo sed -i '/# START WIREGUARD RULES/,/# END WIREGUARD RULES/d' /etc/ufw/before.rules
    
    sudo tee -a /etc/ufw/before.rules > /dev/null <<EOF
# START WIREGUARD RULES
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.0.0.0/24 -o $NET_INTERFACE -j MASQUERADE
COMMIT
# END WIREGUARD RULES
EOF
    
    # Habilitar forwarding no UFW
    sudo sed -i '/^DEFAULT_FORWARD_POLICY/s/DROP/ACCEPT/' /etc/default/ufw
    
    # Reiniciar UFW para aplicar mudanças
    sudo ufw --force enable
    sudo ufw reload
    
    print_success "Firewall configurado na porta $WG_PORT."
}

# Função para gerar chaves do servidor
generate_server_keys() {
    print_status "Gerando chaves do servidor..."
    
    sudo mkdir -p /etc/wireguard
    cd /etc/wireguard
    
    # Gerar chaves com permissões seguras
    sudo umask 077
    sudo wg genkey | sudo tee privatekey | sudo wg pubkey | sudo tee publickey > /dev/null
    
    if [ $? -ne 0 ]; then
        print_error "Falha ao gerar chaves do servidor."
        exit 1
    fi
    
    SERVER_PRIVATE_KEY=$(sudo cat privatekey)
    SERVER_PUBLIC_KEY=$(sudo cat publickey)
    
    print_success "Chaves do servidor geradas."
    print_status "Chave pública do servidor: $SERVER_PUBLIC_KEY"
}

# Função para criar configuração do servidor
create_server_config() {
    print_status "Criando configuração do servidor..."
    
    # Obter informações do usuário
    read -p "Digite a porta do servidor (padrão: 51820): " WG_PORT
    WG_PORT=${WG_PORT:-51820}
    
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    read -p "Digite a interface de rede principal (padrão: $DEFAULT_INTERFACE): " NET_INTERFACE
    NET_INTERFACE=${NET_INTERFACE:-$DEFAULT_INTERFACE}
    
    read -p "Digite o endereço DNS para os clientes (padrão: 8.8.8.8): " CLIENT_DNS
    CLIENT_DNS=${CLIENT_DNS:-8.8.8.8}
    
    SERVER_PRIVATE_KEY=$(sudo cat /etc/wireguard/privatekey)
    
    # Criar arquivo de configuração do servidor
    sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = 10.0.0.1/24
ListenPort = $WG_PORT
SaveConfig = true
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $NET_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $NET_INTERFACE -j MASQUERADE

EOF
    
    if [ $? -ne 0 ]; then
        print_error "Falha ao criar configuração do servidor."
        exit 1
    fi
    
    # Configurar permissões seguras
    sudo chmod 600 /etc/wireguard/wg0.conf
    
    print_success "Configuração do servidor criada."
}

# Função para iniciar serviço WireGuard
start_wireguard() {
    print_status "Iniciando serviço WireGuard..."
    
    # Parar serviço se estiver rodando
    sudo wg-quick down wg0 2>/dev/null
    
    # Iniciar serviço
    sudo wg-quick up wg0
    
    if [ $? -ne 0 ]; then
        print_error "Falha ao iniciar WireGuard."
        print_status "Verificando logs..."
        sudo systemctl status wg-quick@wg0
        exit 1
    fi
    
    # Habilitar inicialização automática
    sudo systemctl enable wg-quick@wg0
    
    print_success "Serviço WireGuard iniciado e configurado para iniciar automaticamente."
}

# Função para verificar se IP já está em uso
is_ip_available() {
    local ip=$1
    sudo wg show wg0 2>/dev/null | grep -q "$ip/32"
    return $?
}

# Função para adicionar cliente
add_client() {
    print_status "Adicionando novo cliente..."
    
    if [[ ! -f "/etc/wireguard/wg0.conf" ]]; then
        print_error "Servidor WireGuard não configurado. Execute a instalação completa primeiro."
        return 1
    fi
    
    read -p "Digite o nome do cliente: " CLIENT_NAME
    if [[ -z "$CLIENT_NAME" ]]; then
        print_error "Nome do cliente não pode estar vazio."
        return 1
    fi
    
    # Limpar nome do cliente para evitar problemas com arquivos
    CLIENT_NAME=$(echo "$CLIENT_NAME" | tr ' ' '_' | tr -cd '[:alnum:]._-')
    
    # Determinar próximo IP disponível
    CLIENT_IP="10.0.0.2"
    while is_ip_available "$CLIENT_IP"; do
        IP_OCTET=$(echo $CLIENT_IP | cut -d'.' -f4)
        CLIENT_IP="10.0.0.$((IP_OCTET + 1))"
        
        # Prevenir loop infinito
        if [ $IP_OCTET -gt 250 ]; then
            print_error "Não há IPs disponíveis na rede 10.0.0.0/24"
            return 1
        fi
    done
    
    # Gerar chaves do cliente
    CLIENT_PRIVATE_KEY=$(wg genkey)
    CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)
    SERVER_PUBLIC_KEY=$(sudo cat /etc/wireguard/publickey)
    
    # Obter IP público do servidor
    read -p "Digite o IP público do servidor (ou Enter para auto-detectar): " SERVER_ENDPOINT
    if [[ -z "$SERVER_ENDPOINT" ]]; then
        if command -v curl &> /dev/null; then
            SERVER_ENDPOINT=$(curl -s -4 ifconfig.me)
        fi
        if [[ -z "$SERVER_ENDPOINT" ]]; then
            print_error "Não foi possível detectar o IP público automaticamente."
            read -p "Digite o IP público do servidor manualmente: " SERVER_ENDPOINT
        fi
    fi
    
    # Obter porta do servidor
    WG_PORT=$(sudo grep -E '^ListenPort' /etc/wireguard/wg0.conf | awk -F' = ' '{print $2}')
    if [[ -z "$WG_PORT" ]]; then
        WG_PORT=51820
    fi
    
    # Adicionar cliente ao servidor
    sudo wg set wg0 peer $CLIENT_PUBLIC_KEY allowed-ips $CLIENT_IP/32
    
    # Adicionar peer permanentemente ao arquivo de configuração
    sudo tee -a /etc/wireguard/wg0.conf > /dev/null <<EOF

[Peer]
# $CLIENT_NAME
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_IP/32
EOF
    
    # Criar arquivo de configuração do cliente
    mkdir -p ~/wireguard-clients
    CLIENT_FILE="$HOME/wireguard-clients/${CLIENT_NAME}.conf"
    
    cat > "$CLIENT_FILE" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_ENDPOINT:$WG_PORT
AllowedIPs = 0.0.0.0/0
EOF
    
    # Configurar permissões do arquivo do cliente
    chmod 600 "$CLIENT_FILE"
    
    # Gerar QR Code se qrencode estiver disponível
    if command -v qrencode &> /dev/null; then
        echo
        print_status "QR Code para o cliente $CLIENT_NAME:"
        qrencode -t ansiutf8 < "$CLIENT_FILE"
    else
        print_warning "qrencode não instalado. Não foi possível gerar QR Code."
    fi
    
    print_success "Cliente $CLIENT_NAME adicionado com IP $CLIENT_IP"
    print_success "Arquivo de configuração salvo em: $CLIENT_FILE"
    print_success "Chave pública do cliente: $CLIENT_PUBLIC_KEY"
}

# Função para mostrar status
show_status() {
    print_status "Status do WireGuard:"
    sudo wg show
    
    print_status "\nInterfaces de rede:"
    if ip addr show wg0 &> /dev/null; then
        ip addr show wg0
    else
        print_warning "Interface wg0 não encontrada"
    fi
}

# Função para remover cliente
remove_client() {
    print_status "Clientes conectados:"
    
    # Mostrar clientes de forma mais clara
    CLIENTS=$(sudo wg show wg0 peers)
    if [[ -z "$CLIENTS" ]]; then
        print_warning "Nenhum cliente configurado."
        return 0
    fi
    
    echo "Clientes conectados:"
    sudo wg show wg0 | while read -r line; do
        if [[ $line == peer:* ]]; then
            pubkey=$(echo $line | awk '{print $2}')
            allowed_ips=$(sudo wg show wg0 | grep -A 1 "$pubkey" | grep "allowed ips" | awk '{print $3}')
            echo "  $pubkey"
            echo "    IPs permitidos: $allowed_ips"
            echo
        fi
    done
    
    echo
    read -p "Digite a chave pública do cliente a ser removido: " CLIENT_PUBKEY
    if [[ -n "$CLIENT_PUBKEY" ]]; then
        # Remover do WireGuard
        sudo wg set wg0 peer "$CLIENT_PUBKEY" remove
        
        # Remover do arquivo de configuração
        sudo sed -i "/# $(echo "$CLIENT_PUBKEY" | cut -c1-10)/,/PublicKey = $CLIENT_PUBKEY/d" /etc/wireguard/wg0.conf
        sudo sed -i "/PublicKey = $CLIENT_PUBKEY/,+2d" /etc/wireguard/wg0.conf
        
        if [ $? -eq 0 ]; then
            print_success "Cliente removido."
        else
            print_error "Falha ao remover cliente. Verifique a chave pública."
        fi
    else
        print_error "Chave pública não fornecida."
    fi
}

# Função para backup da configuração
backup_config() {
    print_status "Fazendo backup da configuração..."
    BACKUP_DIR="$HOME/wireguard-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Fazer backup com permissões adequadas
    sudo cp -r /etc/wireguard "$BACKUP_DIR/" 2>/dev/null || true
    sudo chown -R $USER:$USER "$BACKUP_DIR" 2>/dev/null || true
    
    # Backup dos clientes
    if [[ -d ~/wireguard-clients ]]; then
        cp -r ~/wireguard-clients "$BACKUP_DIR/" 2>/dev/null || true
    fi
    
    # Criar arquivo de informações
    cat > "$BACKUP_DIR/backup-info.txt" <<EOF
Backup criado em: $(date)
Diretório: $BACKUP_DIR
Conteúdo:
- Configuração do servidor WireGuard
- Arquivos de configuração de clientes

Para restaurar:
sudo cp -r $BACKUP_DIR/wireguard/* /etc/wireguard/
sudo chmod 600 /etc/wireguard/*
sudo chown root:root /etc/wireguard/*
EOF

    print_success "Backup criado em: $BACKUP_DIR"
    print_status "Informações de backup salvas em: $BACKUP_DIR/backup-info.txt"
}

# Função para verificar dependências
check_dependencies() {
    local deps=("sudo" "awk" "grep" "head" "cut" "sort" "tail")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Dependências faltando: ${missing[*]}"
        print_status "Instalando dependências..."
        sudo apt update && sudo apt install -y "${missing[@]}"
    fi
}

# Função principal
main() {
    clear
    echo "=========================================="
    echo "  INSTALADOR AUTOMATIZADO WIREGUARD VPN"
    echo "  Versão 1.3 - Corrigida"
    echo "=========================================="
    echo
    
    # Verificações iniciais
    check_root
    check_ubuntu
    check_dependencies
    check_internet
    
    # Menu principal
    while true; do
        echo
        echo "Selecione uma opção:"
        echo "1) Instalação completa do WireGuard"
        echo "2) Adicionar novo cliente"
        echo "3) Remover cliente"
        echo "4) Mostrar status"
        echo "5) Reiniciar WireGuard"
        echo "6) Backup da configuração"
        echo "7) Sair"
        echo
        
        read -p "Opção: " choice
        
        case $choice in
            1)
                update_system
                install_wireguard
                setup_ip_forwarding
                setup_firewall
                generate_server_keys
                create_server_config
                start_wireguard
                show_status
                ;;
            2)
                add_client
                ;;
            3)
                remove_client
                ;;
            4)
                show_status
                ;;
            5)
                sudo wg-quick down wg0
                sudo wg-quick up wg0
                print_success "WireGuard reiniciado."
                ;;
            6)
                backup_config
                ;;
            7)
                print_status "Saindo..."
                exit 0
                ;;
            *)
                print_error "Opção inválida."
                ;;
        esac
    done
}

# Tratamento de sinais
trap 'print_error "Script interrompido pelo usuário."; exit 1' INT TERM

# Executar função principal
main "$@"