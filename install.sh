#!/usr/bin/env bash
# ==============================================================
#  UltraClaw OS Installer v0.1.0
#  Supports: --non-interactive (for chroot/CI builds)
# ==============================================================

set -euo pipefail

# ── Non-interactive detection ──────────────────────────────
INTERACTIVE=true
for arg in "$@"; do
  [[ "$arg" == "--non-interactive" ]] && INTERACTIVE=false
done
[[ "${ULTRACLAW_NONINTERACTIVE:-}" == "1" ]] && INTERACTIVE=false

# ── Colors (disabled in non-interactive mode) ──────────────
if [[ "$INTERACTIVE" == true ]] && [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'
  DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''
  BOLD=''; DIM=''; RESET=''
fi

OK="${GREEN}[OK]${RESET}"
FAIL="${RED}[FAIL]${RESET}"
INFO="${BLUE}[INFO]${RESET}"
WARN="${YELLOW}[WARN]${RESET}"

# ── Logging ────────────────────────────────────────────────
LOG_FILE="/tmp/ultraclaw-install.log"
mkdir -p "$(dirname "$LOG_FILE")"
echo "UltraClaw Install Log -- $(date)" > "$LOG_FILE"

log()  { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }
info() { echo -e "${INFO} $*"; log "INFO: $*"; }
ok()   { echo -e "${OK} $*"; log "OK: $*"; }
warn() { echo -e "${WARN} $*"; log "WARN: $*"; }
fail() { echo -e "${FAIL} $*"; log "FAIL: $*"; }
die()  { fail "$*"; exit 1; }

section() {
  echo ""
  echo -e "${BOLD}${BLUE}==> $*${RESET}"
  echo "==> $*" >> "$LOG_FILE"
}

# ── Global config ──────────────────────────────────────────
CLAW_VERSION="0.1.0"
CLAW_HOME="/opt/claw"
CLAW_CONF="/etc/claw"
CLAW_VAR="/var/claw"
CLAW_USER="claw"

# ── Defaults for non-interactive ──────────────────────────
INSTALL_OLLAMA=true
OLLAMA_MODEL="llama3.2"
ANTHROPIC_API_KEY=""
OPENAI_API_KEY=""
DETECTED_RAM_GB=0
DETECTED_DISK_GB=0
DETECTED_GPU="CPU"
USE_GPU=false

# ════════════════════════════════════════════════════════════
#  HARDWARE DETECTION
# ════════════════════════════════════════════════════════════
detect_hardware() {
  section "Detecting hardware"

  DETECTED_RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 4)
  DETECTED_DISK_GB=$(df -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || echo 20)

  ok "RAM: ${DETECTED_RAM_GB}GB"
  ok "Disk available: ${DETECTED_DISK_GB}GB"

  if command -v nvidia-smi &>/dev/null; then
    DETECTED_GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "")
    [[ -n "$DETECTED_GPU" ]] && USE_GPU=true && ok "GPU: $DETECTED_GPU"
  fi

  [[ "$DETECTED_GPU" == "CPU" ]] && info "No GPU detected -- Ollama will run on CPU"

  # Auto-select model based on RAM
  if [[ $DETECTED_RAM_GB -ge 16 ]]; then
    OLLAMA_MODEL="llama3.2"
  elif [[ $DETECTED_RAM_GB -ge 8 ]]; then
    OLLAMA_MODEL="mistral"
  else
    OLLAMA_MODEL="phi3"
  fi

  log "Hardware: RAM=${DETECTED_RAM_GB}GB DISK=${DETECTED_DISK_GB}GB GPU=${DETECTED_GPU}"
}

# ════════════════════════════════════════════════════════════
#  PRE-CHECKS
# ════════════════════════════════════════════════════════════
pre_checks() {
  section "Pre-installation checks"

  [[ $EUID -ne 0 ]] && die "Must run as root: sudo bash install.sh"
  ok "Running as root"

  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    ok "OS: ${PRETTY_NAME:-Linux}"
  fi

  command -v python3 &>/dev/null && ok "Python3 available" || warn "Python3 not found"
  command -v curl    &>/dev/null && ok "curl available"    || apt-get install -y curl >> "$LOG_FILE" 2>&1
  command -v systemctl &>/dev/null && ok "systemd available" || warn "systemd not found"
}

# ════════════════════════════════════════════════════════════
#  INTERACTIVE CONFIGURATION
# ════════════════════════════════════════════════════════════
configure_interactive() {
  section "Configuration"

  echo ""
  echo -e "  ${BOLD}Local LLM (Ollama)${RESET}"
  read -rp "  Install Ollama? [Y/n]: " ans
  [[ "${ans,,}" =~ ^(n|no)$ ]] && INSTALL_OLLAMA=false

  if [[ "$INSTALL_OLLAMA" == true ]]; then
    echo ""
    echo -e "  Recommended models for ${DETECTED_RAM_GB}GB RAM:"
    echo -e "  [1] ${OLLAMA_MODEL} (auto-selected)"
    echo -e "  [2] Custom"
    read -rp "  Choice [1]: " choice
    if [[ "$choice" == "2" ]]; then
      read -rp "  Model name: " OLLAMA_MODEL
    fi
  fi

  echo ""
  echo -e "  ${BOLD}Remote APIs (optional)${RESET}"
  read -rp "  Anthropic API key (Enter to skip): " ANTHROPIC_API_KEY
  read -rp "  OpenAI API key (Enter to skip): " OPENAI_API_KEY
}

# ════════════════════════════════════════════════════════════
#  INSTALL DEPENDENCIES
# ════════════════════════════════════════════════════════════
install_dependencies() {
  section "Installing system dependencies"

  export DEBIAN_FRONTEND=noninteractive

  apt-get update -qq >> "$LOG_FILE" 2>&1

  local packages=(
    python3-pip python3-venv python3-dev
    build-essential git curl wget
    sqlite3 libsqlite3-dev jq
  )

  for pkg in "${packages[@]}"; do
    info "Installing $pkg..."
    apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1 || warn "Failed: $pkg"
  done

  ok "Dependencies installed"
}

# ════════════════════════════════════════════════════════════
#  CREATE DIRECTORIES
# ════════════════════════════════════════════════════════════
create_directories() {
  section "Creating directory structure"

  local dirs=(
    "$CLAW_HOME/bin" "$CLAW_HOME/agents" "$CLAW_HOME/tools"
    "$CLAW_HOME/core" "$CLAW_HOME/logs"
    "$CLAW_CONF/init.d"
    "$CLAW_VAR/state" "$CLAW_VAR/ipc" "$CLAW_VAR/models"
    "$CLAW_VAR/memory/working" "$CLAW_VAR/memory/episodic"
    "$CLAW_VAR/memory/semantic"
  )

  for dir in "${dirs[@]}"; do
    mkdir -p "$dir"
  done

  if ! id -u "$CLAW_USER" &>/dev/null; then
    useradd -r -s /bin/false -d "$CLAW_HOME" -c "UltraClaw System User" "$CLAW_USER" \
      >> "$LOG_FILE" 2>&1 || warn "Could not create user $CLAW_USER"
  fi

  chown -R "$CLAW_USER:$CLAW_USER" "$CLAW_HOME" "$CLAW_VAR" 2>/dev/null || true
  chmod -R 755 "$CLAW_HOME"
  chmod -R 750 "$CLAW_VAR"

  ok "Directories created"
}

# ════════════════════════════════════════════════════════════
#  PYTHON ENVIRONMENT
# ════════════════════════════════════════════════════════════
install_python_env() {
  section "Setting up Python environment"

  python3 -m venv "$CLAW_HOME/venv" >> "$LOG_FILE" 2>&1
  local pip="$CLAW_HOME/venv/bin/pip"

  "$pip" install --upgrade pip >> "$LOG_FILE" 2>&1

  local packages=(
    "httpx>=0.27" "anthropic>=0.34" "openai>=1.40"
    "rich>=13.7" "typer>=0.12" "pydantic>=2.7"
    "aiosqlite>=0.20" "python-dotenv>=1.0" "psutil>=5.9"
  )

  for pkg in "${packages[@]}"; do
    info "pip install $pkg"
    "$pip" install "$pkg" >> "$LOG_FILE" 2>&1 || warn "Failed: $pkg"
  done

  ok "Python environment ready"
}

# ════════════════════════════════════════════════════════════
#  OLLAMA
# ════════════════════════════════════════════════════════════
install_ollama() {
  [[ "$INSTALL_OLLAMA" != true ]] && return 0

  section "Installing Ollama"

  if command -v ollama &>/dev/null; then
    ok "Ollama already installed"
  else
    info "Downloading Ollama installer..."
    curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1
    ok "Ollama installed"
  fi

  # In non-interactive/chroot mode, skip model download
  # (Ollama service won't run in chroot -- model pulled on first boot)
  if [[ "$INTERACTIVE" == false ]]; then
    info "Skipping model download in non-interactive mode"
    info "Model '${OLLAMA_MODEL}' will be pulled on first boot"

    # Create a first-boot service that pulls the model
    cat > /etc/systemd/system/ultraclaw-first-boot.service << EOF
[Unit]
Description=UltraClaw First Boot Setup
After=ollama.service
Wants=ollama.service
ConditionPathExists=!/var/claw/.first-boot-done

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/bin/bash -c 'ollama pull ${OLLAMA_MODEL} && touch /var/claw/.first-boot-done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable ultraclaw-first-boot.service >> "$LOG_FILE" 2>&1 || true
    ok "First-boot model pull scheduled: ${OLLAMA_MODEL}"
    return 0
  fi

  # Interactive: pull model now
  info "Starting Ollama service..."
  systemctl start ollama >> "$LOG_FILE" 2>&1 || true
  sleep 3
  info "Pulling model: ${OLLAMA_MODEL}"
  ollama pull "$OLLAMA_MODEL" || warn "Model pull failed -- run: ollama pull ${OLLAMA_MODEL}"
  ok "Model ready: ${OLLAMA_MODEL}"
}

# ════════════════════════════════════════════════════════════
#  WRITE CONFIG FILES
# ════════════════════════════════════════════════════════════
write_config() {
  section "Writing configuration files"

  cat > "$CLAW_CONF/claw.conf" << EOF
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

  cat > "$CLAW_CONF/models.conf" << EOF
[default]
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

[fallback_chain]
order = ollama,anthropic,openai
EOF

  cat > "$CLAW_CONF/.env" << EOF
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}
OLLAMA_HOST=http://127.0.0.1:11434
OLLAMA_MODELS=${CLAW_VAR}/models
CLAW_HOME=${CLAW_HOME}
CLAW_LOG_LEVEL=info
EOF

  chmod 600 "$CLAW_CONF/.env"
  ok "Config files written"
}

# ════════════════════════════════════════════════════════════
#  SYSTEMD SERVICES
# ════════════════════════════════════════════════════════════
install_services() {
  section "Installing systemd services"

  # Skip if systemd is not available (e.g. minimal chroot)
  if ! command -v systemctl &>/dev/null; then
    warn "systemd not available -- skipping service installation"
    return 0
  fi

  if [[ "$INSTALL_OLLAMA" == true ]]; then
    cat > /etc/systemd/system/ollama.service << EOF
[Unit]
Description=Ollama LLM Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ollama serve
Restart=always
RestartSec=3
EnvironmentFile=-${CLAW_CONF}/.env
Environment=OLLAMA_MODELS=${CLAW_VAR}/models

[Install]
WantedBy=multi-user.target
EOF
  fi

  cat > /etc/systemd/system/claw-kernel.service << EOF
[Unit]
Description=UltraClaw Agent Kernel
After=network-online.target $([ "$INSTALL_OLLAMA" == true ] && echo "ollama.service" || echo "")

[Service]
Type=notify
User=${CLAW_USER}
Group=${CLAW_USER}
WorkingDirectory=${CLAW_HOME}
ExecStart=${CLAW_HOME}/venv/bin/python ${CLAW_HOME}/core/kernel.py
Restart=on-failure
RestartSec=5
EnvironmentFile=${CLAW_CONF}/.env
StandardOutput=journal
StandardError=journal
SyslogIdentifier=claw-kernel
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  [[ "$INSTALL_OLLAMA" == true ]] && systemctl enable ollama >> "$LOG_FILE" 2>&1 || true
  systemctl enable claw-kernel >> "$LOG_FILE" 2>&1 || true

  ok "Services installed and enabled"
}

# ════════════════════════════════════════════════════════════
#  CLAW KERNEL
# ════════════════════════════════════════════════════════════
write_kernel() {
  section "Writing CLAW kernel"

  cat > "$CLAW_HOME/core/kernel.py" << 'PYEOF'
#!/usr/bin/env python3
"""UltraClaw Kernel v0.1.0"""
import asyncio, os, sys, signal, logging
from datetime import datetime

def sd_notify(state):
    sock = os.environ.get("NOTIFY_SOCKET")
    if sock:
        import socket
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as s:
            s.sendto(state.encode(), sock)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(name)s] %(levelname)s: %(message)s',
    handlers=[logging.StreamHandler(), logging.FileHandler('/opt/claw/logs/kernel.log')]
)
logger = logging.getLogger("claw-kernel")

class CLAWKernel:
    def __init__(self):
        self.agents = {}
        self.running = True
        logger.info("UltraClaw Kernel starting...")

    async def run(self):
        sd_notify("READY=1")
        logger.info("Kernel ready.")
        while self.running:
            await asyncio.sleep(0.1)

    def shutdown(self):
        logger.info("Kernel shutting down...")
        self.running = False

if __name__ == "__main__":
    kernel = CLAWKernel()
    def handle(sig, frame): kernel.shutdown(); sys.exit(0)
    signal.signal(signal.SIGTERM, handle)
    signal.signal(signal.SIGINT, handle)
    asyncio.run(kernel.run())
PYEOF

  chown "$CLAW_USER:$CLAW_USER" "$CLAW_HOME/core/kernel.py" 2>/dev/null || true
  ok "Kernel written"
}

# ════════════════════════════════════════════════════════════
#  clawctl COMMAND
# ════════════════════════════════════════════════════════════
write_clawctl() {
  cat > /usr/local/bin/clawctl << 'EOF'
#!/usr/bin/env bash
# clawctl -- UltraClaw OS control tool
case "${1:-status}" in
  status)
    echo ""
    echo "  UltraClaw OS Status"
    echo ""
    echo "  Kernel: $(systemctl is-active claw-kernel 2>/dev/null)"
    echo "  Ollama: $(systemctl is-active ollama 2>/dev/null)"
    command -v ollama &>/dev/null && ollama list 2>/dev/null | tail -n +2 | awk '{print "  Model: "$1}'
    echo ""
    ;;
  start)   systemctl start ollama 2>/dev/null; sleep 2; systemctl start claw-kernel ;;
  stop)    systemctl stop claw-kernel ;;
  restart) systemctl restart claw-kernel ;;
  logs)    journalctl -u claw-kernel -f --no-pager ;;
  models)  ollama list ;;
  pull)    ollama pull "${2:-}" ;;
  version) cat /opt/claw/VERSION 2>/dev/null || echo "0.1.0" ;;
  help)
    echo "Usage: clawctl [status|start|stop|restart|logs|models|pull <model>|version]"
    ;;
  *) echo "Unknown command. Use: clawctl help"; exit 1 ;;
esac
EOF
  chmod +x /usr/local/bin/clawctl
  ok "clawctl installed"
}

# ════════════════════════════════════════════════════════════
#  FINALIZE
# ════════════════════════════════════════════════════════════
finalize() {
  echo "$CLAW_VERSION" > "$CLAW_HOME/VERSION"

  if [[ "$INTERACTIVE" == true ]]; then
    section "Starting services"
    systemctl start ollama  >> "$LOG_FILE" 2>&1 || true
    sleep 2
    systemctl start claw-kernel >> "$LOG_FILE" 2>&1 || true
  fi

  echo ""
  echo "========================================"
  echo "  UltraClaw OS v${CLAW_VERSION} installed!"
  echo "========================================"
  echo ""
  echo "  Run: clawctl status"
  echo "  Log: $LOG_FILE"
  echo ""
}

# ════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════
main() {
  echo "UltraClaw OS Installer v${CLAW_VERSION}"
  echo "Mode: $( [[ "$INTERACTIVE" == true ]] && echo "interactive" || echo "non-interactive" )"
  echo ""

  pre_checks
  detect_hardware

  if [[ "$INTERACTIVE" == true ]]; then
    configure_interactive
  else
    info "Non-interactive mode -- using defaults"
    info "Ollama: ${INSTALL_OLLAMA}, Model: ${OLLAMA_MODEL}"
  fi

  install_dependencies
  create_directories
  install_python_env
  install_ollama
  write_config
  write_kernel
  install_services
  write_clawctl
  finalize
}

main "$@"