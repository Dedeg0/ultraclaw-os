#!/usr/bin/env bash
# ============================================================
#  CLAW-OS Installer v0.1.0
#  Transforms Ubuntu 22.04 / 24.04 into a CLAW-OS environment
# ============================================================

set -euo pipefail

# ── Colors & Symbols ────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

OK="${GREEN}✓${RESET}"
FAIL="${RED}✗${RESET}"
ARROW="${CYAN}❯${RESET}"
WARN="${YELLOW}⚠${RESET}"
INFO="${BLUE}ℹ${RESET}"

# ── Global State ─────────────────────────────────────────────
CLAW_VERSION="0.1.0"
CLAW_HOME="/opt/claw"
CLAW_CONF="/etc/claw"
CLAW_VAR="/var/claw"
CLAW_USER="claw"
LOG_FILE="/tmp/claw-install.log"

INSTALL_OLLAMA=true
OLLAMA_MODEL="llama3.2"
USE_GPU=false
DETECTED_GPU=""
DETECTED_RAM_GB=0
DETECTED_DISK_GB=0
ANTHROPIC_API_KEY=""
OPENAI_API_KEY=""

# ── Logging ──────────────────────────────────────────────────
log()  { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }
info() { echo -e "${INFO} $*"; log "INFO: $*"; }
ok()   { echo -e "${OK} $*"; log "OK: $*"; }
warn() { echo -e "${WARN} ${YELLOW}$*${RESET}"; log "WARN: $*"; }
fail() { echo -e "${FAIL} ${RED}$*${RESET}"; log "FAIL: $*"; }
die()  { fail "$*"; echo -e "\n${DIM}Log completo: $LOG_FILE${RESET}"; exit 1; }

# ── Progress Bar ─────────────────────────────────────────────
progress() {
    local label="$1"
    local total="$2"
    local current="$3"
    local width=40
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++));  do bar+="░"; done
    printf "\r  ${CYAN}%s${RESET} [%s] %d%%" "$label" "$bar" "$(( current * 100 / total ))"
    [[ "$current" -eq "$total" ]] && echo ""
}

# ── Spinner ──────────────────────────────────────────────────
spin() {
    local pid=$1
    local label="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${RESET} %s " "${frames[$((i % 10))]}" "$label"
        sleep 0.1
        ((i++))
    done
    printf "\r  ${OK} %-50s\n" "$label"
}

# ── Banner ───────────────────────────────────────────────────
banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
   ██████╗██╗      █████╗ ██╗    ██╗      ██████╗ ███████╗
  ██╔════╝██║     ██╔══██╗██║    ██║     ██╔═══██╗██╔════╝
  ██║     ██║     ███████║██║ █╗ ██║     ██║   ██║███████╗
  ██║     ██║     ██╔══██║██║███╗██║     ██║   ██║╚════██║
  ╚██████╗███████╗██║  ██║╚███╔███╔╝     ╚██████╔╝███████║
   ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝       ╚═════╝ ╚══════╝
EOF
    echo -e "${RESET}"
    echo -e "  ${BOLD}CLAW-OS Installer${RESET} ${DIM}v${CLAW_VERSION}${RESET}"
    echo -e "  ${DIM}Agente de IA como sistema operacional${RESET}"
    echo ""
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# ── Divisor de seção ─────────────────────────────────────────
section() {
    echo ""
    echo -e "  ${BOLD}${BLUE}$*${RESET}"
    echo -e "  ${DIM}$(printf '─%.0s' {1..48})${RESET}"
}

# ── Prompt interativo ─────────────────────────────────────────
ask() {
    local question="$1"
    local default="$2"
    local var_name="$3"
    local result

    if [[ -n "$default" ]]; then
        printf "  ${ARROW} %s ${DIM}[%s]${RESET}: " "$question" "$default"
    else
        printf "  ${ARROW} %s: " "$question"
    fi

    read -r result
    result="${result:-$default}"
    printf -v "$var_name" '%s' "$result"
}

# ── Confirmação y/n ───────────────────────────────────────────
confirm() {
    local question="$1"
    local default="${2:-s}"
    local answer

    if [[ "$default" == "s" ]]; then
        printf "  ${ARROW} %s ${DIM}[S/n]${RESET}: " "$question"
    else
        printf "  ${ARROW} %s ${DIM}[s/N]${RESET}: " "$question"
    fi

    read -r answer
    answer="${answer:-$default}"
    [[ "${answer,,}" =~ ^(s|sim|y|yes)$ ]]
}

# ── Menu de seleção ──────────────────────────────────────────
menu() {
    local title="$1"
    shift
    local options=("$@")
    local selected=0
    local key

    echo -e "  ${BOLD}$title${RESET}"
    echo ""

    for i in "${!options[@]}"; do
        if [[ $i -eq $selected ]]; then
            echo -e "  ${CYAN}❯ ${options[$i]}${RESET}"
        else
            echo -e "    ${DIM}${options[$i]}${RESET}"
        fi
    done

    # Retorna o índice selecionado (simplificado para bash)
    echo ""
    local choice
    for i in "${!options[@]}"; do
        echo -e "  ${DIM}[$((i+1))]${RESET} ${options[$i]}"
    done
    echo ""
    ask "Escolha uma opção" "1" choice
    echo $(( choice - 1 ))
}

# ════════════════════════════════════════════════════════════
#  DETECÇÃO DE HARDWARE
# ════════════════════════════════════════════════════════════
detect_hardware() {
    section "Detectando hardware..."

    # RAM
    DETECTED_RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    echo -e "  ${OK} RAM detectada: ${BOLD}${DETECTED_RAM_GB}GB${RESET}"

    # Disco disponível
    DETECTED_DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    echo -e "  ${OK} Disco disponível: ${BOLD}${DETECTED_DISK_GB}GB${RESET}"

    # GPU NVIDIA
    if command -v nvidia-smi &>/dev/null; then
        DETECTED_GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "")
        if [[ -n "$DETECTED_GPU" ]]; then
            USE_GPU=true
            echo -e "  ${OK} GPU NVIDIA: ${BOLD}${DETECTED_GPU}${RESET}"
        fi
    fi

    # GPU AMD (ROCm)
    if [[ -z "$DETECTED_GPU" ]] && command -v rocm-smi &>/dev/null; then
        DETECTED_GPU="AMD ROCm"
        USE_GPU=true
        echo -e "  ${OK} GPU AMD: ${BOLD}ROCm detectado${RESET}"
    fi

    # Sem GPU
    if [[ -z "$DETECTED_GPU" ]]; then
        echo -e "  ${INFO} Nenhuma GPU detectada — Ollama rodará em ${YELLOW}CPU${RESET}"
        DETECTED_GPU="CPU"
    fi

    # Verifica requisitos mínimos
    echo ""
    if [[ $DETECTED_RAM_GB -lt 4 ]]; then
        warn "RAM abaixo do recomendado (mínimo 4GB). Performance pode ser ruim."
    fi
    if [[ $DETECTED_DISK_GB -lt 10 ]]; then
        die "Espaço em disco insuficiente. Necessário mínimo 10GB livres."
    fi

    log "Hardware: RAM=${DETECTED_RAM_GB}GB DISK=${DETECTED_DISK_GB}GB GPU=${DETECTED_GPU}"
}

# ════════════════════════════════════════════════════════════
#  VERIFICAÇÕES PRÉ-INSTALAÇÃO
# ════════════════════════════════════════════════════════════
pre_checks() {
    section "Verificações do sistema..."

    # Root
    if [[ $EUID -ne 0 ]]; then
        die "Este instalador precisa ser executado como root.\n  Use: sudo bash install.sh"
    fi
    ok "Executando como root"

    # Ubuntu
    if [[ ! -f /etc/os-release ]]; then
        die "Sistema operacional não reconhecido."
    fi
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        warn "Sistema detectado: $PRETTY_NAME — recomendado Ubuntu 22.04 ou 24.04."
        confirm "Continuar mesmo assim?" "n" || die "Instalação cancelada."
    else
        ok "Sistema: ${BOLD}${PRETTY_NAME}${RESET}"
    fi

    # Python
    if ! command -v python3 &>/dev/null; then
        die "Python3 não encontrado. Instale com: sudo apt install python3"
    fi
    PYTHON_VER=$(python3 --version | awk '{print $2}')
    ok "Python: ${BOLD}${PYTHON_VER}${RESET}"

    # curl
    if ! command -v curl &>/dev/null; then
        info "Instalando curl..."
        apt-get install -y curl >> "$LOG_FILE" 2>&1
    fi
    ok "curl disponível"

    # systemd
    if ! command -v systemctl &>/dev/null; then
        die "systemd não encontrado. CLAW-OS requer systemd."
    fi
    ok "systemd disponível"
}

# ════════════════════════════════════════════════════════════
#  CONFIGURAÇÃO INTERATIVA
# ════════════════════════════════════════════════════════════
configure() {
    section "Configuração do CLAW-OS"

    echo ""
    echo -e "  ${DIM}Responda as perguntas abaixo para personalizar sua instalação.${RESET}"
    echo -e "  ${DIM}Pressione Enter para aceitar o valor padrão ${RESET}[entre colchetes]${DIM}.${RESET}"
    echo ""

    # ── Ollama ──────────────────────────────────────────────
    echo -e "  ${BOLD}LLM Local (Ollama)${RESET}"
    echo -e "  ${DIM}Roda modelos de IA localmente, sem depender de APIs externas.${RESET}"
    echo ""

    if confirm "Instalar Ollama (LLM local)?" "s"; then
        INSTALL_OLLAMA=true

        # Escolha do modelo baseada em RAM
        echo ""
        echo -e "  ${INFO} Modelos recomendados para ${BOLD}${DETECTED_RAM_GB}GB RAM${RESET}:"
        echo ""

        if [[ $DETECTED_RAM_GB -ge 32 ]]; then
            echo -e "  ${DIM}[1]${RESET} llama3.1:70b  ${DIM}— Mais poderoso, requer 40GB RAM${RESET}"
            echo -e "  ${DIM}[2]${RESET} llama3.2      ${DIM}— Equilibrado, requer 8GB RAM${RESET} ${GREEN}★ recomendado${RESET}"
            echo -e "  ${DIM}[3]${RESET} mistral       ${DIM}— Rápido e eficiente${RESET}"
            echo -e "  ${DIM}[4]${RESET} gemma2        ${DIM}— Google, bom para código${RESET}"
            echo -e "  ${DIM}[5]${RESET} Personalizado ${DIM}— Digite o nome do modelo${RESET}"
        elif [[ $DETECTED_RAM_GB -ge 8 ]]; then
            echo -e "  ${DIM}[1]${RESET} llama3.2      ${DIM}— Equilibrado, requer 8GB RAM${RESET} ${GREEN}★ recomendado${RESET}"
            echo -e "  ${DIM}[2]${RESET} mistral       ${DIM}— Rápido e eficiente${RESET}"
            echo -e "  ${DIM}[3]${RESET} gemma2        ${DIM}— Google, bom para código${RESET}"
            echo -e "  ${DIM}[4]${RESET} phi3          ${DIM}— Leve, Microsoft${RESET}"
            echo -e "  ${DIM}[5]${RESET} Personalizado ${DIM}— Digite o nome do modelo${RESET}"
        else
            echo -e "  ${WARN} RAM limitada (${DETECTED_RAM_GB}GB). Recomendamos modelos pequenos:"
            echo -e "  ${DIM}[1]${RESET} phi3          ${DIM}— Leve, 4GB RAM${RESET} ${GREEN}★ recomendado${RESET}"
            echo -e "  ${DIM}[2]${RESET} gemma2:2b     ${DIM}— Muito leve, 3GB RAM${RESET}"
            echo -e "  ${DIM}[3]${RESET} tinyllama     ${DIM}— Ultraleve, 2GB RAM${RESET}"
            echo -e "  ${DIM}[4]${RESET} Personalizado ${DIM}— Digite o nome do modelo${RESET}"
        fi

        echo ""
        local model_choice
        ask "Escolha o modelo padrão" "1" model_choice

        case "$model_choice" in
            1)
                if [[ $DETECTED_RAM_GB -ge 32 ]]; then OLLAMA_MODEL="llama3.1:70b"
                elif [[ $DETECTED_RAM_GB -ge 8 ]]; then OLLAMA_MODEL="llama3.2"
                else OLLAMA_MODEL="phi3"; fi ;;
            2)
                if [[ $DETECTED_RAM_GB -ge 32 ]]; then OLLAMA_MODEL="llama3.2"
                elif [[ $DETECTED_RAM_GB -ge 8 ]]; then OLLAMA_MODEL="mistral"
                else OLLAMA_MODEL="gemma2:2b"; fi ;;
            3)
                if [[ $DETECTED_RAM_GB -ge 32 ]]; then OLLAMA_MODEL="mistral"
                elif [[ $DETECTED_RAM_GB -ge 8 ]]; then OLLAMA_MODEL="gemma2"
                else OLLAMA_MODEL="tinyllama"; fi ;;
            4)
                if [[ $DETECTED_RAM_GB -ge 32 ]]; then OLLAMA_MODEL="gemma2"
                else ask "Nome do modelo (ex: llama3.2, mistral)" "llama3.2" OLLAMA_MODEL; fi ;;
            5) ask "Nome do modelo (ex: llama3.2, mistral)" "llama3.2" OLLAMA_MODEL ;;
            *) OLLAMA_MODEL="llama3.2" ;;
        esac

        ok "Modelo selecionado: ${BOLD}${OLLAMA_MODEL}${RESET}"
    else
        INSTALL_OLLAMA=false
        warn "Ollama não será instalado. CLAW-OS usará apenas APIs remotas."
    fi

    # ── APIs Remotas ─────────────────────────────────────────
    echo ""
    echo -e "  ${BOLD}APIs Remotas ${DIM}(opcional)${RESET}"
    echo -e "  ${DIM}Para usar Claude (Anthropic) ou GPT (OpenAI) além do modelo local.${RESET}"
    echo ""

    if confirm "Configurar Anthropic API (Claude)?" "n"; then
        ask "Anthropic API Key" "" ANTHROPIC_API_KEY
    fi

    if confirm "Configurar OpenAI API (GPT)?" "n"; then
        ask "OpenAI API Key" "" OPENAI_API_KEY
    fi

    # ── Resumo ────────────────────────────────────────────────
    echo ""
    section "Resumo da instalação"
    echo ""
    echo -e "  ${DIM}Sistema base:${RESET}    Ubuntu $(source /etc/os-release && echo $VERSION_ID)"
    echo -e "  ${DIM}Hardware:${RESET}        RAM ${DETECTED_RAM_GB}GB | GPU: ${DETECTED_GPU}"
    echo -e "  ${DIM}Ollama:${RESET}          $([ "$INSTALL_OLLAMA" == true ] && echo "✓ Sim — modelo: $OLLAMA_MODEL" || echo "✗ Não")"
    echo -e "  ${DIM}Anthropic API:${RESET}   $([ -n "$ANTHROPIC_API_KEY" ] && echo "✓ Configurada" || echo "✗ Não configurada")"
    echo -e "  ${DIM}OpenAI API:${RESET}      $([ -n "$OPENAI_API_KEY" ] && echo "✓ Configurada" || echo "✗ Não configurada")"
    echo -e "  ${DIM}Diretório:${RESET}       $CLAW_HOME"
    echo ""

    confirm "Iniciar instalação?" "s" || die "Instalação cancelada pelo usuário."
}

# ════════════════════════════════════════════════════════════
#  INSTALAÇÃO DAS DEPENDÊNCIAS
# ════════════════════════════════════════════════════════════
install_dependencies() {
    section "Instalando dependências do sistema..."

    local packages=(
        python3-pip python3-venv python3-dev
        build-essential git curl wget
        sqlite3 libsqlite3-dev
        jq htop
    )

    info "Atualizando índice de pacotes..."
    (apt-get update -qq >> "$LOG_FILE" 2>&1) &
    spin $! "Atualizando apt"

    local total=${#packages[@]}
    local current=0

    for pkg in "${packages[@]}"; do
        ((current++))
        progress "Instalando pacotes" "$total" "$current"
        apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1 || warn "Falha ao instalar $pkg"
    done

    ok "Dependências do sistema instaladas"
}

# ════════════════════════════════════════════════════════════
#  ESTRUTURA DE DIRETÓRIOS
# ════════════════════════════════════════════════════════════
create_directories() {
    section "Criando estrutura de diretórios..."

    local dirs=(
        "$CLAW_HOME/bin"
        "$CLAW_HOME/agents"
        "$CLAW_HOME/tools"
        "$CLAW_HOME/core"
        "$CLAW_HOME/logs"
        "$CLAW_CONF/init.d"
        "$CLAW_VAR/state"
        "$CLAW_VAR/ipc"
        "$CLAW_VAR/models"
        "$CLAW_VAR/memory/working"
        "$CLAW_VAR/memory/episodic"
        "$CLAW_VAR/memory/semantic"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log "Criado: $dir"
    done

    # Usuário de sistema para o CLAW
    if ! id -u "$CLAW_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$CLAW_HOME" -c "CLAW-OS System User" "$CLAW_USER"
        ok "Usuário de sistema '${CLAW_USER}' criado"
    fi

    chown -R "$CLAW_USER:$CLAW_USER" "$CLAW_HOME" "$CLAW_VAR"
    chmod -R 755 "$CLAW_HOME"
    chmod -R 750 "$CLAW_VAR"

    ok "Estrutura de diretórios criada"
}

# ════════════════════════════════════════════════════════════
#  AMBIENTE PYTHON
# ════════════════════════════════════════════════════════════
install_python_env() {
    section "Configurando ambiente Python..."

    python3 -m venv "$CLAW_HOME/venv" >> "$LOG_FILE" 2>&1 &
    spin $! "Criando ambiente virtual Python"

    local pip="$CLAW_HOME/venv/bin/pip"

    local packages=(
        "httpx>=0.27"
        "anthropic>=0.34"
        "openai>=1.40"
        "rich>=13.7"
        "typer>=0.12"
        "pydantic>=2.7"
        "asyncio-mqtt>=0.16"
        "aiosqlite>=0.20"
        "python-dotenv>=1.0"
        "psutil>=5.9"
    )

    local total=${#packages[@]}
    local current=0

    "$pip" install --upgrade pip >> "$LOG_FILE" 2>&1

    for pkg in "${packages[@]}"; do
        ((current++))
        progress "Instalando pacotes Python" "$total" "$current"
        "$pip" install "$pkg" >> "$LOG_FILE" 2>&1 || warn "Falha: $pkg"
    done

    ok "Ambiente Python configurado"
}

# ════════════════════════════════════════════════════════════
#  INSTALAÇÃO DO OLLAMA
# ════════════════════════════════════════════════════════════
install_ollama() {
    if [[ "$INSTALL_OLLAMA" != true ]]; then
        return 0
    fi

    section "Instalando Ollama..."

    if command -v ollama &>/dev/null; then
        ok "Ollama já instalado: $(ollama --version 2>/dev/null || echo 'versão desconhecida')"
    else
        info "Baixando instalador oficial do Ollama..."
        (curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1) &
        spin $! "Instalando Ollama"
        ok "Ollama instalado"
    fi

    # Configura variável de ambiente para modelos
    export OLLAMA_MODELS="$CLAW_VAR/models"

    # Inicia serviço temporariamente para baixar modelo
    info "Iniciando Ollama para baixar o modelo '${OLLAMA_MODEL}'..."
    systemctl start ollama >> "$LOG_FILE" 2>&1 || true
    sleep 3

    echo ""
    echo -e "  ${INFO} Baixando ${BOLD}${OLLAMA_MODEL}${RESET} — isso pode demorar alguns minutos."
    echo -e "  ${DIM}  Tamanho estimado: $(get_model_size $OLLAMA_MODEL)${RESET}"
    echo ""

    # Download com output visível
    if ollama pull "$OLLAMA_MODEL" 2>&1 | while IFS= read -r line; do
        echo -e "  ${DIM}${line}${RESET}"
    done; then
        ok "Modelo '${OLLAMA_MODEL}' baixado com sucesso"
    else
        warn "Falha ao baixar '${OLLAMA_MODEL}'. Você pode baixar depois com: ollama pull ${OLLAMA_MODEL}"
    fi
}

get_model_size() {
    case "$1" in
        "tinyllama")    echo "~600MB" ;;
        "phi3")         echo "~2.3GB" ;;
        "gemma2:2b")    echo "~1.6GB" ;;
        "gemma2")       echo "~5.4GB" ;;
        "mistral")      echo "~4.1GB" ;;
        "llama3.2")     echo "~2.0GB" ;;
        "llama3.1:70b") echo "~40GB" ;;
        *)              echo "variável" ;;
    esac
}

# ════════════════════════════════════════════════════════════
#  ARQUIVOS DE CONFIGURAÇÃO
# ════════════════════════════════════════════════════════════
write_config() {
    section "Escrevendo configurações..."

    # claw.conf principal
    cat > "$CLAW_CONF/claw.conf" << EOF
# CLAW-OS Configuration
# Gerado por: install.sh v${CLAW_VERSION}
# Data: $(date '+%Y-%m-%d %H:%M:%S')

[core]
version = ${CLAW_VERSION}
home = ${CLAW_HOME}
log_level = info
max_agents = 10

[scheduler]
tick_interval_ms = 100
agent_timeout_s = 300
max_retries = 3

[memory]
working_dir = ${CLAW_VAR}/memory/working
episodic_dir = ${CLAW_VAR}/memory/episodic
semantic_dir = ${CLAW_VAR}/memory/semantic
max_context_tokens = 8192

[resources]
detected_ram_gb = ${DETECTED_RAM_GB}
detected_gpu = ${DETECTED_GPU}
use_gpu = ${USE_GPU}
EOF

    ok "claw.conf criado"

    # models.conf
    cat > "$CLAW_CONF/models.conf" << EOF
# CLAW-OS Model Configuration
# Define quais LLMs estão disponíveis e como priorizá-los

[default]
# Modelo padrão para agentes sem modelo específico
model = ${OLLAMA_MODEL}
backend = $([ "$INSTALL_OLLAMA" == true ] && echo "ollama" || echo "anthropic")

[ollama]
enabled = ${INSTALL_OLLAMA}
host = http://127.0.0.1:11434
default_model = ${OLLAMA_MODEL}
timeout_s = 120

[anthropic]
enabled = $([ -n "$ANTHROPIC_API_KEY" ] && echo "true" || echo "false")
model = claude-sonnet-4-20250514

[openai]
enabled = $([ -n "$OPENAI_API_KEY" ] && echo "true" || echo "false")
model = gpt-4o

# Ordem de fallback: se o primeiro falhar, tenta o próximo
[fallback_chain]
order = ollama,anthropic,openai
EOF

    ok "models.conf criado"

    # .env com chaves de API
    cat > "$CLAW_CONF/.env" << EOF
# CLAW-OS Environment Variables
# NÃO compartilhe este arquivo

ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}
OLLAMA_HOST=http://127.0.0.1:11434
OLLAMA_MODELS=${CLAW_VAR}/models
CLAW_HOME=${CLAW_HOME}
CLAW_LOG_LEVEL=info
EOF

    chmod 600 "$CLAW_CONF/.env"
    ok ".env criado (permissões restritas)"
}

# ════════════════════════════════════════════════════════════
#  SERVIÇOS SYSTEMD
# ════════════════════════════════════════════════════════════
install_services() {
    section "Configurando serviços systemd..."

    # Serviço do Ollama (se instalado)
    if [[ "$INSTALL_OLLAMA" == true ]]; then
        cat > /etc/systemd/system/ollama.service << EOF
[Unit]
Description=Ollama LLM Server
Documentation=https://ollama.com
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ollama
Group=ollama
ExecStart=/usr/bin/ollama serve
Restart=always
RestartSec=3
EnvironmentFile=-${CLAW_CONF}/.env
Environment=HOME=/usr/share/ollama
Environment=OLLAMA_MODELS=${CLAW_VAR}/models

# Limites de recursos
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF
        ok "ollama.service configurado"
    fi

    # Serviço do CLAW Kernel
    cat > /etc/systemd/system/claw-kernel.service << EOF
[Unit]
Description=CLAW-OS Agent Kernel
Documentation=https://github.com/seu-usuario/claw-os
After=network-online.target $([ "$INSTALL_OLLAMA" == true ] && echo "ollama.service")
$([ "$INSTALL_OLLAMA" == true ] && echo "Wants=ollama.service")

[Service]
Type=notify
User=${CLAW_USER}
Group=${CLAW_USER}
WorkingDirectory=${CLAW_HOME}
ExecStart=${CLAW_HOME}/venv/bin/python ${CLAW_HOME}/core/kernel.py
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5
EnvironmentFile=${CLAW_CONF}/.env

# Logging via journald
StandardOutput=journal
StandardError=journal
SyslogIdentifier=claw-kernel

# Segurança
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${CLAW_VAR} ${CLAW_HOME}/logs

[Install]
WantedBy=multi-user.target
EOF
    ok "claw-kernel.service configurado"

    systemctl daemon-reload >> "$LOG_FILE" 2>&1

    # Ativa serviços no boot
    [[ "$INSTALL_OLLAMA" == true ]] && systemctl enable ollama >> "$LOG_FILE" 2>&1
    systemctl enable claw-kernel >> "$LOG_FILE" 2>&1

    ok "Serviços ativados no boot"
}

# ════════════════════════════════════════════════════════════
#  KERNEL PYTHON (core/kernel.py)
# ════════════════════════════════════════════════════════════
write_kernel() {
    section "Escrevendo CLAW Kernel..."

    cat > "$CLAW_HOME/core/kernel.py" << 'PYEOF'
#!/usr/bin/env python3
"""
CLAW-OS Kernel v0.1.0
Gerenciador central de agentes de IA
"""
import asyncio
import os
import sys
import signal
import logging
from pathlib import Path
from datetime import datetime

# Notifica systemd que está inicializando
def sd_notify(state: str):
    sock_path = os.environ.get("NOTIFY_SOCKET")
    if sock_path:
        import socket
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as s:
            s.sendto(state.encode(), sock_path)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(name)s] %(levelname)s: %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('/opt/claw/logs/kernel.log')
    ]
)
logger = logging.getLogger("claw-kernel")

class CLAWKernel:
    def __init__(self):
        self.agents = {}
        self.running = True
        self.start_time = datetime.now()
        logger.info("CLAW Kernel inicializando...")

    async def run(self):
        sd_notify("READY=1")
        logger.info("CLAW Kernel pronto. Aguardando agentes...")

        # Loop principal
        while self.running:
            await self._tick()
            await asyncio.sleep(0.1)

    async def _tick(self):
        # Placeholder para o scheduler
        pass

    def shutdown(self):
        logger.info("CLAW Kernel encerrando...")
        self.running = False

if __name__ == "__main__":
    kernel = CLAWKernel()

    def handle_signal(sig, frame):
        kernel.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    asyncio.run(kernel.run())
PYEOF

    chown "$CLAW_USER:$CLAW_USER" "$CLAW_HOME/core/kernel.py"
    ok "CLAW Kernel escrito"
}

# ════════════════════════════════════════════════════════════
#  COMANDO clawctl
# ════════════════════════════════════════════════════════════
write_clawctl() {
    cat > /usr/local/bin/clawctl << 'EOF'
#!/usr/bin/env bash
# clawctl — CLAW-OS control tool

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

case "${1:-status}" in
    status)
        echo -e "\n  ${BOLD}CLAW-OS Status${RESET}\n"
        echo -e "  ${DIM}Kernel:${RESET}   $(systemctl is-active claw-kernel 2>/dev/null | grep -q active && echo "${GREEN}●${RESET} rodando" || echo "${RED}●${RESET} parado")"
        echo -e "  ${DIM}Ollama:${RESET}   $(systemctl is-active ollama 2>/dev/null | grep -q active && echo "${GREEN}●${RESET} rodando" || echo "${YELLOW}●${RESET} parado/não instalado")"
        if command -v ollama &>/dev/null && systemctl is-active ollama &>/dev/null; then
            echo -e "  ${DIM}Modelos:${RESET}  $(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
        fi
        echo ""
        ;;
    start)
        echo "Iniciando CLAW-OS..."
        systemctl start ollama 2>/dev/null || true
        sleep 2
        systemctl start claw-kernel
        echo -e "${GREEN}✓${RESET} CLAW-OS iniciado"
        ;;
    stop)
        systemctl stop claw-kernel 2>/dev/null || true
        echo -e "${GREEN}✓${RESET} CLAW-OS parado"
        ;;
    restart)
        systemctl restart claw-kernel
        echo -e "${GREEN}✓${RESET} CLAW-OS reiniciado"
        ;;
    logs)
        journalctl -u claw-kernel -f --no-pager
        ;;
    models)
        if command -v ollama &>/dev/null; then
            echo -e "\n  ${BOLD}Modelos locais (Ollama)${RESET}\n"
            ollama list
        else
            echo "Ollama não está instalado."
        fi
        ;;
    pull)
        model="${2:-}"
        [[ -z "$model" ]] && { echo "Uso: clawctl pull <modelo>"; exit 1; }
        ollama pull "$model"
        ;;
    version)
        echo "CLAW-OS v$(cat /opt/claw/VERSION 2>/dev/null || echo '0.1.0')"
        ;;
    help|--help|-h)
        echo -e "\n  ${BOLD}clawctl${RESET} — CLAW-OS control\n"
        echo -e "  ${DIM}Comandos disponíveis:${RESET}\n"
        echo -e "    ${CYAN}status${RESET}       Estado atual do sistema"
        echo -e "    ${CYAN}start${RESET}        Inicia kernel e serviços"
        echo -e "    ${CYAN}stop${RESET}         Para o kernel"
        echo -e "    ${CYAN}restart${RESET}      Reinicia o kernel"
        echo -e "    ${CYAN}logs${RESET}         Logs em tempo real"
        echo -e "    ${CYAN}models${RESET}       Lista modelos instalados"
        echo -e "    ${CYAN}pull <model>${RESET} Baixa um novo modelo Ollama"
        echo -e "    ${CYAN}version${RESET}      Versão do CLAW-OS"
        echo ""
        ;;
    *)
        echo "Comando desconhecido: $1. Use: clawctl help"
        exit 1
        ;;
esac
EOF

    chmod +x /usr/local/bin/clawctl
    ok "clawctl instalado em /usr/local/bin/clawctl"
}

# ════════════════════════════════════════════════════════════
#  FINALIZAÇÃO
# ════════════════════════════════════════════════════════════
finalize() {
    # Versão
    echo "$CLAW_VERSION" > "$CLAW_HOME/VERSION"

    # Inicia serviços
    section "Iniciando serviços..."

    if [[ "$INSTALL_OLLAMA" == true ]]; then
        systemctl start ollama >> "$LOG_FILE" 2>&1 &
        spin $! "Iniciando Ollama"
    fi

    systemctl start claw-kernel >> "$LOG_FILE" 2>&1 &
    spin $! "Iniciando CLAW Kernel"

    sleep 2
    ok "Serviços iniciados"
}

# ════════════════════════════════════════════════════════════
#  SUMÁRIO FINAL
# ════════════════════════════════════════════════════════════
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    cat << 'EOF'
  ╔══════════════════════════════════════════════╗
  ║     CLAW-OS instalado com sucesso!  🎉       ║
  ╚══════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"

    echo -e "  ${BOLD}Próximos passos:${RESET}"
    echo ""
    echo -e "  ${CYAN}1.${RESET} Verificar status do sistema:"
    echo -e "     ${DIM}\$ clawctl status${RESET}"
    echo ""
    echo -e "  ${CYAN}2.${RESET} Ver logs em tempo real:"
    echo -e "     ${DIM}\$ clawctl logs${RESET}"
    echo ""
    if [[ "$INSTALL_OLLAMA" == true ]]; then
        echo -e "  ${CYAN}3.${RESET} Testar Ollama diretamente:"
        echo -e "     ${DIM}\$ ollama run ${OLLAMA_MODEL}${RESET}"
        echo ""
    fi
    echo -e "  ${CYAN}4.${RESET} Ver todos os comandos:"
    echo -e "     ${DIM}\$ clawctl help${RESET}"
    echo ""
    echo -e "  ${DIM}Log completo da instalação: ${LOG_FILE}${RESET}"
    echo ""
    echo -e "  ${DIM}Documentação: https://github.com/seu-usuario/claw-os${RESET}"
    echo ""
}

# ════════════════════════════════════════════════════════════
#  PONTO DE ENTRADA
# ════════════════════════════════════════════════════════════
main() {
    # Inicializa log
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "CLAW-OS Install Log — $(date)" > "$LOG_FILE"

    banner
    pre_checks
    detect_hardware
    configure
    install_dependencies
    create_directories
    install_python_env
    install_ollama
    write_config
    write_kernel
    install_services
    write_clawctl
    finalize
    print_summary
}

main "$@"