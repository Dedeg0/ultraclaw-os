#!/usr/bin/env bash
# ==============================================================
#  UltraClaw OS -- Rename Script
#  Renames all openclaw references to ultraclaw in the codebase
# ==============================================================

set -euo pipefail

echo "==> Starting OpenCLAW → UltraClaw rename..."

# ── Directories to skip ───────────────────────────────────────
SKIP_DIRS=(
  ".git"
  "node_modules"
  ".pnpm-store"
  "dist"
  "build"
  ".next"
)

build_find_excludes() {
  local args=()
  for d in "${SKIP_DIRS[@]}"; do
    args+=(-not -path "*/$d/*" -not -path "*/$d")
  done
  echo "${args[@]}"
}

# ── File extensions to process ────────────────────────────────
EXTENSIONS=(
  "ts" "tsx" "js" "mjs" "cjs" "json" "jsonc"
  "md" "mdx" "txt" "yaml" "yml" "toml"
  "sh" "bash" "zsh"
  "html" "css" "scss"
  "env" "example" "conf" "config"
  "xml" "svg"
)

build_ext_pattern() {
  local pattern=""
  for ext in "${EXTENSIONS[@]}"; do
    [ -n "$pattern" ] && pattern="$pattern -o"
    pattern="$pattern -name \"*.$ext\""
  done
  echo "$pattern"
}

# ── Replacement map ───────────────────────────────────────────
declare -A REPLACEMENTS=(
  # Exact casing
  ["openclaw"]="ultraclaw"
  ["OpenClaw"]="UltraClaw"
  ["OPENCLAW"]="ULTRACLAW"
  ["open-claw"]="ultra-claw"
  ["open_claw"]="ultra_claw"

  # URLs / paths
  ["openclaw.ai"]="ultraclaw.os"
  ["docs.openclaw.ai"]="docs.ultraclaw.os"
  ["clawhub.com"]="ultraclaw.os/hub"
  ["discord.gg/clawd"]="discord.gg/ultraclaw"

  # Config paths
  ["~/.openclaw"]="~/.ultraclaw"
  ["\$HOME/.openclaw"]="\$HOME/.ultraclaw"
  ["/openclaw/"]="/ultraclaw/"

  # Ports
  ["18789"]="18790"

  # Package name
  ["\"name\": \"openclaw\""]="\"name\": \"ultraclaw\""

  # npm package
  ["openclaw@latest"]="ultraclaw@latest"

  # CLI binary
  ["pnpm openclaw"]="pnpm ultraclaw"
  ["npm run openclaw"]="npm run ultraclaw"

  # Mascot (optional -- comment out to keep lobster)
  ["Molty"]="Claw"
  ["lobster.bot"]="ultraclaw.bot"
)

# ── Apply replacements to a single file ───────────────────────
process_file() {
  local file="$1"
  local changed=false

  for from in "${!REPLACEMENTS[@]}"; do
    local to="${REPLACEMENTS[$from]}"
    if grep -qF "$from" "$file" 2>/dev/null; then
      sed -i "s|${from}|${to}|g" "$file"
      changed=true
    fi
  done

  if [ "$changed" = true ]; then
    echo "  [renamed] $file"
  fi
}

export -f process_file
export -A REPLACEMENTS 2>/dev/null || true

# ── Find and process all files ────────────────────────────────
echo ""
echo "==> Processing files..."

EXCLUDE_ARGS=()
for d in "${SKIP_DIRS[@]}"; do
  EXCLUDE_ARGS+=(-not -path "*/$d/*" -not -path "*/$d")
done

# Build extension filter
EXT_ARGS=()
for ext in "${EXTENSIONS[@]}"; do
  if [ ${#EXT_ARGS[@]} -gt 0 ]; then
    EXT_ARGS+=(-o)
  fi
  EXT_ARGS+=(-name "*.$ext")
done

mapfile -t FILES < <(
  find . \
    "${EXCLUDE_ARGS[@]}" \
    \( "${EXT_ARGS[@]}" \) \
    -type f \
    2>/dev/null
)

echo "  Found ${#FILES[@]} files to process"

for file in "${FILES[@]}"; do
  process_file "$file"
done

# ── Rename directories ────────────────────────────────────────
echo ""
echo "==> Renaming directories..."

# Rename dirs containing "openclaw" in their name (bottom-up)
find . "${EXCLUDE_ARGS[@]}" -depth -type d -name "*openclaw*" 2>/dev/null | while read -r dir; do
  newdir="${dir//openclaw/ultraclaw}"
  if [ "$dir" != "$newdir" ]; then
    mv "$dir" "$newdir"
    echo "  [dir] $dir → $newdir"
  fi
done

# ── Rename files ──────────────────────────────────────────────
echo ""
echo "==> Renaming files..."

find . "${EXCLUDE_ARGS[@]}" -type f -name "*openclaw*" 2>/dev/null | while read -r file; do
  newfile="${file//openclaw/ultraclaw}"
  if [ "$file" != "$newfile" ]; then
    mv "$file" "$newfile"
    echo "  [file] $file → $newfile"
  fi
done

# ── Update package.json bin entry ────────────────────────────
echo ""
echo "==> Updating package.json bin entry..."
if [ -f "package.json" ]; then
  # Rename bin key from "openclaw" to "ultraclaw"
  node -e "
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
    if (pkg.bin && pkg.bin.openclaw) {
      pkg.bin.ultraclaw = pkg.bin.openclaw;
      delete pkg.bin.openclaw;
    }
    if (pkg.name) pkg.name = pkg.name.replace(/openclaw/g, 'ultraclaw');
    fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
    console.log('  package.json updated');
  " 2>/dev/null || echo "  Skipped (node not available or already done)"
fi

# ── Update pnpm-workspace.yaml if present ─────────────────────
echo ""
echo "==> Done!"
echo ""
echo "  Summary:"
echo "  - All 'openclaw' references renamed to 'ultraclaw'"
echo "  - Config path: ~/.openclaw → ~/.ultraclaw"
echo "  - Gateway port: 18789 → 18790"
echo "  - CLI binary: openclaw → ultraclaw"
echo ""
echo "  Next steps:"
echo "  1. Review the changes with: git diff --stat"
echo "  2. Commit: git add -A && git commit -m 'refactor: rename openclaw to ultraclaw'"
echo ""