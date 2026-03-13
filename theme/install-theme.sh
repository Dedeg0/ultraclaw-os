#!/usr/bin/env bash
# ============================================================
#  UltraClaw Visual Theme Installer
#  Instala: Plymouth, GRUB theme, wallpapers
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

OK="${GREEN}✓${RESET}"; FAIL="${RED}✗${RESET}"; ARROW="${CYAN}❯${RESET}"

THEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="/tmp/ultraclaw-theme.log"

ok()   { echo -e "${OK} $*"; }
info() { echo -e "${ARROW} $*"; }
warn() { echo -e "  [WARN] $*"; }
die()  { echo -e "${FAIL} ${RED}$*${RESET}"; exit 1; }

[[ $EUID -ne 0 ]] && die "Execute como root: sudo bash install-theme.sh"

# Detecta se está rodando dentro de um chroot/CI (sem systemd real)
IN_CHROOT=false
if [ ! -d /run/systemd/system ] || ! systemctl is-system-running &>/dev/null 2>&1; then
    IN_CHROOT=true
fi

echo ""
echo -e "  ${BOLD}UltraClaw Theme Installer${RESET}"
echo -e "  ${DIM}Plymouth · GRUB · Wallpapers${RESET}"
[[ "$IN_CHROOT" == true ]] && echo -e "  ${DIM}(modo chroot detectado)${RESET}"
echo ""

# ════════════════════════════════════════════════════════════
#  DEPENDÊNCIAS
# ════════════════════════════════════════════════════════════
info "Instalando dependências..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    plymouth \
    plymouth-themes \
    python3-pil \
    grub2-common \
    >> "$LOG" 2>&1 || warn "Algumas dependências falharam — continuando..."
ok "Dependências instaladas"

# ════════════════════════════════════════════════════════════
#  GERA LOGO PNG via Python
# ════════════════════════════════════════════════════════════
info "Gerando logo PNG..."

python3 << 'PYEOF'
from PIL import Image, ImageDraw
import os

W, H = 200, 200
img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

stroke = 8

lines = [
    ((52, 36), (70, 108)),
    ((100, 28), (100, 108)),
    ((148, 36), (130, 108)),
    ((52, 108), (148, 108)),
]

for start, end in lines:
    draw.line([start, end], fill=(255, 255, 255, 230), width=stroke)

img.save('/tmp/ultraclaw-logo.png')
print("Logo gerada: /tmp/ultraclaw-logo.png")
PYEOF

ok "Logo PNG gerada"

# ════════════════════════════════════════════════════════════
#  PLYMOUTH
# ════════════════════════════════════════════════════════════
info "Instalando tema Plymouth..."

PLYMOUTH_DIR="/usr/share/plymouth/themes/ultraclaw"
mkdir -p "$PLYMOUTH_DIR"

cp "$THEME_DIR/plymouth/ultraclaw.script"   "$PLYMOUTH_DIR/"
cp "$THEME_DIR/plymouth/ultraclaw.plymouth" "$PLYMOUTH_DIR/"
cp /tmp/ultraclaw-logo.png                  "$PLYMOUTH_DIR/logo.png"

# Ativa o tema (pode falhar no chroot — não é crítico)
if command -v update-alternatives &>/dev/null; then
    update-alternatives --install \
        /usr/share/plymouth/themes/default.plymouth \
        default.plymouth \
        "$PLYMOUTH_DIR/ultraclaw.plymouth" \
        100 >> "$LOG" 2>&1 || warn "update-alternatives falhou — ignorando"
else
    warn "update-alternatives não encontrado — pulando"
fi

if command -v plymouth-set-default-theme &>/dev/null; then
    plymouth-set-default-theme ultraclaw >> "$LOG" 2>&1 \
        || warn "plymouth-set-default-theme falhou — ignorando"
else
    # Fallback: escreve direto no arquivo de configuração
    PLYM_CFG="/etc/plymouth/plymouthd.conf"
    mkdir -p /etc/plymouth
    if [ -f "$PLYM_CFG" ]; then
        sed -i 's/^Theme=.*/Theme=ultraclaw/' "$PLYM_CFG" 2>/dev/null || true
    else
        printf '[Daemon]\nTheme=ultraclaw\n' > "$PLYM_CFG"
    fi
    ok "Tema Plymouth configurado via plymouthd.conf"
fi

# update-initramfs NÃO roda no chroot — será executado automaticamente
# pelo sistema no primeiro boot real
if [[ "$IN_CHROOT" == false ]]; then
    info "Reconstruindo initramfs (pode demorar ~30s)..."
    update-initramfs -u >> "$LOG" 2>&1 \
        && ok "initramfs reconstruído" \
        || warn "update-initramfs falhou — tente manualmente: sudo update-initramfs -u"
else
    info "Pulando update-initramfs no chroot (será feito no primeiro boot)"
fi

ok "Plymouth instalado — tema: ultraclaw"

# ════════════════════════════════════════════════════════════
#  WALLPAPERS
# ════════════════════════════════════════════════════════════
info "Gerando wallpapers..."

python3 << 'PYEOF'
from PIL import Image, ImageDraw, ImageFilter
import random, math, os

W, H = 1920, 1080
os.makedirs('/usr/share/backgrounds/ultraclaw', exist_ok=True)

# ── WP-01: Grid minimalista ────────────────────────────────
img = Image.new('RGB', (W, H), (8, 8, 8))
draw = ImageDraw.Draw(img)

step = 80
for x in range(0, W+1, step):
    draw.line([(x, 0), (x, H)], fill=(18, 18, 18), width=1)
for y in range(0, H+1, step):
    draw.line([(0, y), (W, y)], fill=(18, 18, 18), width=1)

draw.line([(0, int(H*0.55)), (W, int(H*0.55))], fill=(35, 35, 35), width=1)
img.save('/usr/share/backgrounds/ultraclaw/uc-01-grid.png')
print("WP-01 salvo")

# ── WP-02: Claw mark grande ────────────────────────────────
img = Image.new('RGB', (W, H), (8, 8, 8))
draw = ImageDraw.Draw(img)

scale = 12
cx, cy_logo = W//2, H//2 - 80

pts = [
    ((26, 18), (35, 54)),
    ((40, 14), (40, 54)),
    ((54, 18), (45, 54)),
    ((26, 54), (54, 54)),
]
for (x1, y1), (x2, y2) in pts:
    sx1 = cx + (x1 - 40) * scale
    sy1 = cy_logo + (y1 - 34) * scale
    sx2 = cx + (x2 - 40) * scale
    sy2 = cy_logo + (y2 - 34) * scale
    draw.line([(sx1, sy1), (sx2, sy2)], fill=(20, 20, 20), width=int(5 * scale * 0.18))

line_y = H - 100
draw.line([(W//2 - 160, line_y), (W//2 + 160, line_y)], fill=(20, 20, 20), width=1)
img = img.filter(ImageFilter.GaussianBlur(radius=0.5))
img.save('/usr/share/backgrounds/ultraclaw/uc-02-claw.png')
print("WP-02 salvo")

# ── WP-03: Noise / grain ───────────────────────────────────
pixels = []
for y in range(H):
    for x in range(W):
        v = int(random.gauss(10, 6))
        v = max(0, min(25, v))
        dx = (x - W/2) / (W/2)
        dy = (y - H/2) / (H/2)
        dist = math.sqrt(dx*dx + dy*dy)
        vignette = max(0, 1 - dist * 0.7)
        v = int(v * vignette)
        pixels.append((v, v, v))

img = Image.new('RGB', (W, H))
img.putdata(pixels)
img.save('/usr/share/backgrounds/ultraclaw/uc-03-noise.png')
print("WP-03 salvo")

print("Todos os wallpapers gerados em /usr/share/backgrounds/ultraclaw/")
PYEOF

ok "Wallpapers instalados em /usr/share/backgrounds/ultraclaw/"

# ════════════════════════════════════════════════════════════
#  GRUB THEME
# ════════════════════════════════════════════════════════════
info "Instalando tema GRUB..."

GRUB_THEME_DIR="/boot/grub/themes/ultraclaw"
mkdir -p "$GRUB_THEME_DIR"

cp "$THEME_DIR/grub/theme.txt" "$GRUB_THEME_DIR/"

python3 << 'PYEOF'
from PIL import Image, ImageDraw

W, H = 1920, 1080
img = Image.new('RGB', (W, H), (8, 8, 8))
draw = ImageDraw.Draw(img)

for x in range(0, W+1, 80):
    draw.line([(x, 0), (x, H)], fill=(14, 14, 14), width=1)
for y in range(0, H+1, 80):
    draw.line([(0, y), (W, y)], fill=(14, 14, 14), width=1)

draw.line([(W//2, 80), (W//2, H-80)], fill=(22, 22, 22), width=1)
img.save('/boot/grub/themes/ultraclaw/background.png')
print("Background GRUB gerado")
PYEOF

# Aplica o tema no /etc/default/grub
if [ -f /etc/default/grub ]; then
    if grep -q "GRUB_THEME" /etc/default/grub; then
        sed -i 's|.*GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/ultraclaw/theme.txt"|' /etc/default/grub
    else
        echo 'GRUB_THEME="/boot/grub/themes/ultraclaw/theme.txt"' >> /etc/default/grub
    fi

    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub

    if ! grep -q "GRUB_GFXMODE" /etc/default/grub; then
        echo 'GRUB_GFXMODE=1920x1080x32,auto' >> /etc/default/grub
    fi
else
    warn "/etc/default/grub não encontrado — criando..."
    mkdir -p /etc/default
    cat > /etc/default/grub << 'GRUBEOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="UltraClaw OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_THEME="/boot/grub/themes/ultraclaw/theme.txt"
GRUB_GFXMODE=1920x1080x32,auto
GRUBEOF
fi

# update-grub também não roda em chroot
if [[ "$IN_CHROOT" == false ]]; then
    update-grub >> "$LOG" 2>&1 \
        && ok "GRUB atualizado" \
        || warn "update-grub falhou — tente manualmente: sudo update-grub"
else
    info "Pulando update-grub no chroot (será feito no primeiro boot)"
fi

ok "Tema GRUB instalado"

# ════════════════════════════════════════════════════════════
#  SUMÁRIO
# ════════════════════════════════════════════════════════════
echo ""
echo -e "  ${BOLD}${GREEN}UltraClaw Theme instalado!${RESET}"
echo ""
echo -e "  ${DIM}Plymouth:${RESET}    /usr/share/plymouth/themes/ultraclaw/"
echo -e "  ${DIM}GRUB:${RESET}        /boot/grub/themes/ultraclaw/"
echo -e "  ${DIM}Wallpapers:${RESET}  /usr/share/backgrounds/ultraclaw/"
echo ""
if [[ "$IN_CHROOT" == true ]]; then
    echo -e "  ${DIM}initramfs e GRUB serão atualizados no primeiro boot.${RESET}"
else
    echo -e "  ${DIM}Reinicie para ver o boot animation: ${RESET}sudo reboot"
fi
echo ""