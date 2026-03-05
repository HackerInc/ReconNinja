#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              ReconNinja v3.2.2 — Universal Installer                       ║
# ║              https://github.com/YouTubers777/ReconNinja                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Supported platforms:
#
#   LINUX (Debian/Ubuntu family)
#     · Kali Linux         · Ubuntu (all LTS)    · Debian (stable/testing)
#     · Parrot OS          · Pop!_OS             · Linux Mint
#     · Raspbian / Pi OS   · ElementaryOS        · Zorin OS
#     · Tails (live mode)
#
#   LINUX (Red Hat family)
#     · Fedora (38+)       · CentOS Stream        · RHEL 8/9
#     · Rocky Linux        · AlmaLinux            · Oracle Linux
#
#   LINUX (Arch family)
#     · Arch Linux         · Manjaro              · EndeavourOS
#     · Garuda Linux       · BlackArch            · ArcoLinux
#
#   LINUX (Other)
#     · openSUSE Leap/Tumbleweed  · SLES
#     · Alpine Linux (3.x+)
#     · Void Linux (xbps)
#     · Gentoo (portage)
#     · NixOS  (nix)
#     · Solus  (eopkg)
#     · Slackware (slackpkg, fallback)
#     · Amazon Linux 2023
#     · ChromeOS (Crostini / Linux container)
#
#   ANDROID
#     · Termux (pkg / apt)
#
#   macOS
#     · macOS 12 Monterey+  (Homebrew — auto-installed if missing)
#     · Apple Silicon (arm64) and Intel (x86_64) both supported
#
#   BSD
#     · FreeBSD (pkg)
#     · OpenBSD (pkg_add)
#     · NetBSD  (pkgin)
#
#   WSL2 / Windows
#     · WSL2 (Ubuntu, Debian, Kali, etc.)  — treated as Linux
#     · Native Windows → instructed to use WSL2
#
# What this script does:
#   1. Detects your platform with full granularity
#   2. Installs / validates Python 3.10+
#   3. Installs Python dependencies (rich)
#   4. Copies ReconNinja to ~/.reconninja/
#   5. Creates 'ReconNinja' alias in every detected shell config
#   6. Creates a standalone wrapper at ~/.local/bin/ReconNinja
#   7. Installs all recon tools (nmap, rustscan, go tools, etc.)
#   8. Runs --check-tools at the end so you know exactly what's ready
#
# Usage:
#   chmod +x install.sh && ./install.sh
#
# Flags:
#   --skip-go       Skip all Go-based tools (subfinder, httpx, nuclei, ffuf, amass…)
#   --skip-rust     Skip RustScan
#   --skip-tools    Skip all external tool installs (Python + copy + alias only)
#   --python-only   Alias for --skip-tools
#   --force         Re-install even if already installed
#   --no-update     Don't run 'apt update' / 'pkg update' / etc. before installing
#   --dry-run       Print what would be done without doing it
#   --help          Show this help

set -euo pipefail

# ── Version ───────────────────────────────────────────────────────────────────
RN_VERSION="3.2.2"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Flags ─────────────────────────────────────────────────────────────────────
SKIP_GO=false
SKIP_RUST=false
SKIP_TOOLS=false
FORCE=false
NO_UPDATE=false
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --skip-go)     SKIP_GO=true ;;
        --skip-rust)   SKIP_RUST=true ;;
        --skip-tools)  SKIP_TOOLS=true; SKIP_GO=true; SKIP_RUST=true ;;
        --python-only) SKIP_TOOLS=true; SKIP_GO=true; SKIP_RUST=true ;;
        --force)       FORCE=true ;;
        --no-update)   NO_UPDATE=true ;;
        --dry-run)     DRY_RUN=true ;;
        --help|-h)
            sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
ok()    { echo -e "${GREEN}  ✔${NC}  $*"; }
warn()  { echo -e "${YELLOW}  ⚠${NC}  $*"; }
err()   { echo -e "${RED}  ✘${NC}  $*"; }
info()  { echo -e "${CYAN}  ▶${NC}  $*"; }
step()  { echo -e "\n${BOLD}${CYAN}── $* ──${NC}"; }
note()  { echo -e "${DIM}     $*${NC}"; }

cmd_exists()  { command -v "$1" &>/dev/null; }
is_termux()   { [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; }
is_wsl()      { [[ -f /proc/version ]] && grep -qi microsoft /proc/version; }
is_macos()    { [[ "$(uname -s)" == "Darwin" ]]; }
is_freebsd()  { [[ "$(uname -s)" == "FreeBSD" ]]; }
is_openbsd()  { [[ "$(uname -s)" == "OpenBSD" ]]; }
is_netbsd()   { [[ "$(uname -s)" == "NetBSD" ]]; }

dry() {
    if $DRY_RUN; then
        echo -e "${MAGENTA}  [DRY-RUN]${NC}  $*"
        return 0
    fi
    "$@"
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}"
cat << 'BANNER'
██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗███╗   ██╗██╗███╗   ██╗     ██╗ █████╗
██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║████╗  ██║██║████╗  ██║     ██║██╔══██╗
██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║██╔██╗ ██║██║██╔██╗ ██║     ██║███████║
██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║██║╚██╗██║██║██║╚██╗██║██   ██║██╔══██║
██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║██║ ╚████║██║██║ ╚████║╚█████╔╝██║  ██║
╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚════╝ ╚═╝  ╚═╝
BANNER
echo -e "${NC}"
echo -e "${BOLD}  ReconNinja v${RN_VERSION} — Universal Installer${NC}"
echo -e "${DIM}  https://github.com/YouTubers777/ReconNinja${NC}"
echo ""
echo -e "${RED}  ⚠  Use ONLY against systems you own or have explicit written permission to test.${NC}"
echo ""

$DRY_RUN && echo -e "${MAGENTA}${BOLD}  [DRY-RUN MODE — no changes will be made]${NC}\n"

# ── Native Windows block ──────────────────────────────────────────────────────
if [[ "${OSTYPE:-}" == "msys" || "${OSTYPE:-}" == "cygwin" || \
      "${OSTYPE:-}" == "win32" || -n "${WINDIR:-}" ]]; then
    err "Native Windows is not supported."
    echo ""
    echo "  Use WSL2 (Windows Subsystem for Linux):"
    echo "    1. Open PowerShell as Administrator"
    echo "    2. Run:  wsl --install"
    echo "    3. Restart, open WSL terminal, then re-run this script"
    echo "    Docs: https://learn.microsoft.com/en-us/windows/wsl/install"
    echo ""
    exit 1
fi

# ── Platform & package manager detection ─────────────────────────────────────
step "Detecting platform"
DISTRO_LIKE=""
PKG_MGR="unknown"
SUDO="sudo"

# Termux (Android) — detect first, has no sudo
if is_termux; then
    PKG_MGR="pkg"
    SUDO=""
    ok "Termux (Android) detected"

# macOS
elif is_macos; then
    ARCH_MAC="$(uname -m)"
    ok "macOS detected (${ARCH_MAC})"
    if cmd_exists brew; then
        PKG_MGR="brew"
        ok "Homebrew found: $(brew --version | head -1)"
    else
        warn "Homebrew not found — installing it now..."
        dry /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Apple Silicon: add brew to PATH
        if [[ "$ARCH_MAC" == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
        fi
        PKG_MGR="brew"
        ok "Homebrew installed"
    fi

# FreeBSD
elif is_freebsd; then
    PKG_MGR="freebsd_pkg"
    ok "FreeBSD detected"

# OpenBSD
elif is_openbsd; then
    PKG_MGR="openbsd_pkg"
    ok "OpenBSD detected"

# NetBSD
elif is_netbsd; then
    PKG_MGR="pkgin"
    ok "NetBSD detected"

# Linux
elif [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    DISTRO_LIKE="${ID_LIKE:-}"

    case "${ID:-}" in
        # ── Debian/Ubuntu family ──────────────────────────────────────────
        kali|ubuntu|debian|parrot|linuxmint|pop|elementary|zorin|tails| \
        raspbian|kali-rolling|deepin|mx|devuan|pureos)
            PKG_MGR="apt"
            _wsl_tag=""; is_wsl && _wsl_tag=" [WSL2]"
            ok "Detected: ${PRETTY_NAME:-$ID}${_wsl_tag} (apt)"
            ;;
        # ── Arch family ───────────────────────────────────────────────────
        arch|manjaro|endeavouros|garuda|artix|blackarch|arcolinux|cachyos)
            PKG_MGR="pacman"
            ok "Detected: ${PRETTY_NAME:-$ID} (pacman)"
            ;;
        # ── Fedora / Red Hat family ───────────────────────────────────────
        fedora)
            PKG_MGR="dnf"
            ok "Detected: ${PRETTY_NAME:-$ID} (dnf)"
            ;;
        centos|rhel|rocky|almalinux|ol|amzn)
            # amzn = Amazon Linux; try dnf first, fall back to yum
            if cmd_exists dnf; then PKG_MGR="dnf"
            else PKG_MGR="yum"; fi
            ok "Detected: ${PRETTY_NAME:-$ID} (${PKG_MGR})"
            ;;
        # ── openSUSE / SLES ───────────────────────────────────────────────
        opensuse*|sles|sled)
            PKG_MGR="zypper"
            ok "Detected: ${PRETTY_NAME:-$ID} (zypper)"
            ;;
        # ── Alpine ────────────────────────────────────────────────────────
        alpine)
            PKG_MGR="apk"
            ok "Detected: Alpine Linux $(cat /etc/alpine-release 2>/dev/null || echo '') (apk)"
            ;;
        # ── Void Linux ────────────────────────────────────────────────────
        void)
            PKG_MGR="xbps"
            ok "Detected: Void Linux (xbps)"
            ;;
        # ── Gentoo ────────────────────────────────────────────────────────
        gentoo)
            PKG_MGR="emerge"
            ok "Detected: Gentoo Linux (emerge)"
            ;;
        # ── NixOS ─────────────────────────────────────────────────────────
        nixos)
            PKG_MGR="nix"
            ok "Detected: NixOS (nix)"
            warn "NixOS: tool install is best-effort. Consider using nix-shell."
            ;;
        # ── Solus ─────────────────────────────────────────────────────────
        solus)
            PKG_MGR="eopkg"
            ok "Detected: Solus (eopkg)"
            ;;
        # ── Slackware ─────────────────────────────────────────────────────
        slackware)
            PKG_MGR="slackpkg"
            ok "Detected: Slackware (slackpkg) — limited tool support"
            ;;
        *)
            # Fallback: probe which package manager is available
            warn "Unknown distro '${ID:-?}' — probing package managers..."
            if   cmd_exists apt-get;    then PKG_MGR="apt"
            elif cmd_exists pacman;     then PKG_MGR="pacman"
            elif cmd_exists dnf;        then PKG_MGR="dnf"
            elif cmd_exists yum;        then PKG_MGR="yum"
            elif cmd_exists zypper;     then PKG_MGR="zypper"
            elif cmd_exists apk;        then PKG_MGR="apk"
            elif cmd_exists xbps-install; then PKG_MGR="xbps"
            elif cmd_exists emerge;     then PKG_MGR="emerge"
            elif cmd_exists eopkg;      then PKG_MGR="eopkg"
            elif cmd_exists nix-env;    then PKG_MGR="nix"
            elif cmd_exists pkg;        then PKG_MGR="freebsd_pkg"
            else
                warn "No known package manager found — manual installs may be needed"
                PKG_MGR="unknown"
            fi
            warn "Falling back to: $PKG_MGR"
            ;;
    esac

    # ID_LIKE fallback for derived distros not caught above
    if [[ "$PKG_MGR" == "unknown" && -n "$DISTRO_LIKE" ]]; then
        case "$DISTRO_LIKE" in
            *debian*|*ubuntu*) PKG_MGR="apt" ;;
            *arch*)            PKG_MGR="pacman" ;;
            *fedora*|*rhel*)   PKG_MGR="dnf" ;;
            *suse*)            PKG_MGR="zypper" ;;
        esac
        [[ "$PKG_MGR" != "unknown" ]] && info "Using $PKG_MGR (from ID_LIKE=$DISTRO_LIKE)"
    fi

else
    # No /etc/os-release — probe directly
    warn "Cannot read /etc/os-release — probing..."
    if   cmd_exists apt-get;      then PKG_MGR="apt"
    elif cmd_exists pacman;       then PKG_MGR="pacman"
    elif cmd_exists dnf;          then PKG_MGR="dnf"
    elif cmd_exists yum;          then PKG_MGR="yum"
    elif cmd_exists brew;         then PKG_MGR="brew"
    elif cmd_exists apk;          then PKG_MGR="apk"
    elif cmd_exists xbps-install; then PKG_MGR="xbps"
    elif cmd_exists pkg;          then PKG_MGR="freebsd_pkg"
    else warn "Unknown environment — proceeding with best-effort install"
    fi
fi

# No sudo in Termux or when already root
[[ "$(id -u)" -eq 0 ]] && SUDO=""
note "Package manager: ${PKG_MGR}  |  sudo: '${SUDO:-none}'"

# ── pkg_install / pkg_update central dispatchers ──────────────────────────────
pkg_install() {
    local pkg="$1"
    local apt_pkg="${2:-$pkg}"     # optional alternate name for apt
    local brew_pkg="${3:-$pkg}"    # optional alternate name for brew

    case "$PKG_MGR" in
        apt)          dry $SUDO apt-get install -y -qq "$apt_pkg" ;;
        pacman)       dry $SUDO pacman -S --noconfirm --needed "$pkg" ;;
        dnf)          dry $SUDO dnf install -y "$pkg" ;;
        yum)          dry $SUDO yum install -y "$pkg" ;;
        zypper)       dry $SUDO zypper install -y "$pkg" ;;
        apk)          dry $SUDO apk add --no-cache "$pkg" ;;
        xbps)         dry $SUDO xbps-install -y "$pkg" ;;
        emerge)       dry $SUDO emerge -q "$pkg" ;;
        nix)          dry nix-env -iA nixpkgs."$pkg" ;;
        eopkg)        dry $SUDO eopkg install -y "$pkg" ;;
        slackpkg)     dry $SUDO slackpkg install "$pkg" ;;
        freebsd_pkg)  dry $SUDO pkg install -y "$pkg" ;;
        openbsd_pkg)  dry $SUDO pkg_add "$pkg" ;;
        pkgin)        dry $SUDO pkgin -y install "$pkg" ;;
        brew)         dry brew install "$brew_pkg" ;;
        pkg)          dry pkg install -y "$pkg" ;;    # Termux
        *)            warn "Cannot auto-install '$pkg' — unknown package manager"; return 1 ;;
    esac
}

pkg_update() {
    $NO_UPDATE && return 0
    info "Updating package lists..."
    case "$PKG_MGR" in
        apt)         dry $SUDO apt-get update -qq ;;
        pacman)      dry $SUDO pacman -Sy --noconfirm ;;
        dnf)         dry $SUDO dnf check-update -q || true ;;
        yum)         dry $SUDO yum check-update -q || true ;;
        zypper)      dry $SUDO zypper refresh ;;
        apk)         dry $SUDO apk update ;;
        xbps)        dry $SUDO xbps-install -S ;;
        brew)        dry brew update ;;
        pkg)         dry pkg update ;;   # Termux
        freebsd_pkg) dry $SUDO pkg update ;;
        pkgin)       dry $SUDO pkgin update ;;
        nix)         dry nix-channel --update ;;
        *)           true ;;
    esac
}

# ── Termux extra: ensure storage & base utils ─────────────────────────────────
if is_termux; then
    step "Termux setup"
    if ! cmd_exists curl; then
        dry pkg install -y curl
    fi
    if ! cmd_exists git; then
        dry pkg install -y git
    fi
    ok "Termux base utilities ready"
fi

# ── Python 3.10+ ──────────────────────────────────────────────────────────────
step "Python 3.10+"

PYTHON=""
for py in python3.12 python3.11 python3.10 python3 python; do
    if cmd_exists "$py"; then
        _maj=$("$py" -c 'import sys; print(sys.version_info.major)' 2>/dev/null || echo 0)
        _min=$("$py" -c 'import sys; print(sys.version_info.minor)' 2>/dev/null || echo 0)
        if [[ "$_maj" -ge 3 && "$_min" -ge 10 ]]; then
            PYTHON="$py"
            ok "$py (${_maj}.${_min}) found"
            break
        fi
    fi
done

if [[ -z "$PYTHON" ]]; then
    warn "Python 3.10+ not found — attempting to install..."
    case "$PKG_MGR" in
        apt)
            dry $SUDO apt-get install -y -qq python3 python3-pip python3-venv
            ;;
        pacman)
            dry $SUDO pacman -S --noconfirm python python-pip
            ;;
        dnf|yum)
            dry $SUDO ${PKG_MGR} install -y python3 python3-pip
            ;;
        brew)
            dry brew install python3
            ;;
        apk)
            dry $SUDO apk add python3 py3-pip
            ;;
        pkg)   # Termux
            dry pkg install -y python
            ;;
        xbps)
            dry $SUDO xbps-install -y python3 python3-pip
            ;;
        eopkg)
            dry $SUDO eopkg install -y python3 python3-pip
            ;;
        freebsd_pkg)
            dry $SUDO pkg install -y python311 py311-pip
            ;;
        nix)
            warn "NixOS: run 'nix-shell -p python311' or add to configuration.nix"
            ;;
        *)
            err "Cannot auto-install Python. Get it from: https://www.python.org/downloads/"
            exit 1
            ;;
    esac

    # Re-check
    for py in python3.12 python3.11 python3.10 python3 python; do
        if cmd_exists "$py"; then
            _maj=$("$py" -c 'import sys; print(sys.version_info.major)' 2>/dev/null || echo 0)
            _min=$("$py" -c 'import sys; print(sys.version_info.minor)' 2>/dev/null || echo 0)
            if [[ "$_maj" -ge 3 && "$_min" -ge 10 ]]; then
                PYTHON="$py"; ok "$py installed (${_maj}.${_min})"; break
            fi
        fi
    done

    [[ -z "$PYTHON" ]] && { err "Python 3.10+ install failed. Install manually."; exit 1; }
fi

# pip
PIP=""
for pip_cmd in pip3 pip; do
    if cmd_exists "$pip_cmd"; then PIP="$pip_cmd"; break; fi
done

if [[ -z "$PIP" ]]; then
    info "pip not found — installing..."
    case "$PKG_MGR" in
        apt)    dry $SUDO apt-get install -y -qq python3-pip ;;
        pacman) dry $SUDO pacman -S --noconfirm python-pip ;;
        dnf|yum) dry $SUDO ${PKG_MGR} install -y python3-pip ;;
        brew)   dry brew install python3 ;;
        apk)    dry $SUDO apk add py3-pip ;;
        pkg)    dry pkg install -y python ;;
        xbps)   dry $SUDO xbps-install -y python3-pip ;;
        freebsd_pkg) dry $SUDO pkg install -y py311-pip ;;
        *)      dry "$PYTHON" -m ensurepip --upgrade 2>/dev/null || warn "pip install failed" ;;
    esac
    for pip_cmd in pip3 pip; do
        cmd_exists "$pip_cmd" && { PIP="$pip_cmd"; break; }
    done
    [[ -z "$PIP" ]] && PIP="$PYTHON -m pip"
fi

note "Using pip: $PIP"

# ── pip install helper (handles --break-system-packages gracefully) ────────────
pip_install() {
    if $DRY_RUN; then
        echo -e "${MAGENTA}  [DRY-RUN]${NC}  pip install $*"
        return 0
    fi
    $PIP install "$@" --break-system-packages -q 2>/dev/null \
        || $PIP install "$@" -q 2>/dev/null \
        || $PYTHON -m pip install "$@" -q 2>/dev/null \
        || { warn "pip install $* failed"; return 1; }
}

# ── Python dependencies ───────────────────────────────────────────────────────
step "Python dependencies"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQ_FILE="$SCRIPT_DIR/requirements.txt"

if [[ -f "$REQ_FILE" ]]; then
    info "Installing from requirements.txt..."
    pip_install -r "$REQ_FILE" && ok "requirements.txt installed"
else
    pip_install rich && ok "rich installed"
fi

# ── Copy ReconNinja to ~/.reconninja/ ─────────────────────────────────────────
step "Installing ReconNinja to ~/.reconninja/"

INSTALL_DIR="$HOME/.reconninja"

if [[ -d "$INSTALL_DIR" ]] && ! $FORCE; then
    warn "~/.reconninja already exists — updating in place"
    info "Backing up existing install..."
    dry cp -r "$INSTALL_DIR" "${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
fi

dry mkdir -p "$INSTALL_DIR"
info "Copying files to $INSTALL_DIR ..."
dry cp -r "$SCRIPT_DIR/." "$INSTALL_DIR/"
dry chmod +x "$INSTALL_DIR/reconninja.py"
ok "ReconNinja $RN_VERSION installed to $INSTALL_DIR"

# ── Shell alias + PATH setup ──────────────────────────────────────────────────
step "Shell alias & PATH"

ALIAS_CMD="$PYTHON $INSTALL_DIR/reconninja.py"
ALIAS_LINE="alias ReconNinja='$ALIAS_CMD'"
ALIAS_COMMENT="# ReconNinja v${RN_VERSION} — https://github.com/YouTubers777/ReconNinja"

# Collect all shell config files that exist
SHELL_CONFIGS=()
[[ -f "$HOME/.bashrc"                    ]] && SHELL_CONFIGS+=("$HOME/.bashrc")
[[ -f "$HOME/.bash_profile"              ]] && SHELL_CONFIGS+=("$HOME/.bash_profile")
[[ -f "$HOME/.profile"                   ]] && SHELL_CONFIGS+=("$HOME/.profile")
[[ -f "$HOME/.zshrc"                     ]] && SHELL_CONFIGS+=("$HOME/.zshrc")
[[ -f "$HOME/.zprofile"                  ]] && SHELL_CONFIGS+=("$HOME/.zprofile")
[[ -f "$HOME/.config/fish/config.fish"   ]] && SHELL_CONFIGS+=("$HOME/.config/fish/config.fish")
[[ -f "$HOME/.kshrc"                     ]] && SHELL_CONFIGS+=("$HOME/.kshrc")
[[ -f "$HOME/.tcshrc"                    ]] && SHELL_CONFIGS+=("$HOME/.tcshrc")

# Termux: ~/.bashrc is in $HOME which is /data/data/com.termux/files/home
# Termux: ensure ~/.bashrc exists
if is_termux && [[ ! -f "$HOME/.bashrc" ]]; then
    $DRY_RUN || touch "$HOME/.bashrc"
    SHELL_CONFIGS+=("$HOME/.bashrc")
fi

# If nothing exists, create based on current shell
if [[ ${#SHELL_CONFIGS[@]} -eq 0 ]]; then
    DEFAULT_SHELL="$(basename "${SHELL:-/bin/bash}")"
    case "$DEFAULT_SHELL" in
        zsh)  $DRY_RUN || touch "$HOME/.zshrc";  SHELL_CONFIGS+=("$HOME/.zshrc") ;;
        fish) $DRY_RUN || mkdir -p "$HOME/.config/fish"
              $DRY_RUN || touch "$HOME/.config/fish/config.fish"
              SHELL_CONFIGS+=("$HOME/.config/fish/config.fish") ;;
        ksh)  $DRY_RUN || touch "$HOME/.kshrc";  SHELL_CONFIGS+=("$HOME/.kshrc") ;;
        *)    $DRY_RUN || touch "$HOME/.bashrc";  SHELL_CONFIGS+=("$HOME/.bashrc") ;;
    esac
fi

# Helper: add or update a line in a config file
upsert_line() {
    local file="$1" pattern="$2" line="$3"
    $DRY_RUN && { echo -e "${MAGENTA}  [DRY-RUN]${NC}  upsert '$line' in $file"; return 0; }
    if grep -q "$pattern" "$file" 2>/dev/null; then
        if is_macos; then
            sed -i '' "s|${pattern}.*|${line}|g" "$file"
        else
            sed -i "s|${pattern}.*|${line}|g" "$file"
        fi
    else
        { echo ""; echo "$ALIAS_COMMENT"; echo "$line"; } >> "$file"
    fi
}

for cfg_file in "${SHELL_CONFIGS[@]}"; do
    # Fish uses different alias syntax
    if [[ "$cfg_file" == *"fish"* ]]; then
        fish_line="alias ReconNinja '$ALIAS_CMD'"
        upsert_line "$cfg_file" "alias ReconNinja" "$fish_line"
        # Fish PATH
        if ! grep -q ".local/bin" "$cfg_file" 2>/dev/null; then
            # fish_add_path needs double quotes so $HOME expands at write time
            $DRY_RUN || echo "fish_add_path $HOME/.local/bin" >> "$cfg_file"
        fi
        ok "Fish alias → $cfg_file"
    else
        upsert_line "$cfg_file" "alias ReconNinja=" "$ALIAS_LINE"
        # PATH entry
        if ! grep -q '\.local/bin' "$cfg_file" 2>/dev/null; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$cfg_file" 2>/dev/null || true
        fi
        ok "Bash/Zsh alias → $cfg_file"
    fi
done

# Standalone wrapper script — works from cron, scripts, non-interactive shells
WRAPPER_DIR="$HOME/.local/bin"
dry mkdir -p "$WRAPPER_DIR"

if ! $DRY_RUN; then
cat > "$WRAPPER_DIR/ReconNinja" << WRAPPER
#!/usr/bin/env bash
# ReconNinja v${RN_VERSION} wrapper — auto-generated by install.sh
exec $ALIAS_CMD "\$@"
WRAPPER
chmod +x "$WRAPPER_DIR/ReconNinja"
fi

ok "Wrapper → $WRAPPER_DIR/ReconNinja"
export PATH="$HOME/.local/bin:$PATH"

# ── Activation hint helper (defined here — used multiple times below) ─────────
_print_activate_hint() {
    echo ""
    echo -e "  ${BOLD}Activate the alias in your current terminal:${NC}"
    echo ""
    [[ -f "$HOME/.bashrc"   ]] && echo -e "  ${CYAN}source ~/.bashrc${NC}              (bash)"
    [[ -f "$HOME/.zshrc"    ]] && echo -e "  ${CYAN}source ~/.zshrc${NC}               (zsh)"
    [[ -f "$HOME/.config/fish/config.fish" ]] \
        && echo -e "  ${CYAN}source ~/.config/fish/config.fish${NC}  (fish)"
    is_termux && echo -e "  ${CYAN}source ~/.bashrc${NC}              (Termux)"
    echo ""
    echo -e "  Then just type: ${GREEN}${BOLD}ReconNinja${NC}"
    echo ""
}

# ── Early exit for --skip-tools ───────────────────────────────────────────────
if $SKIP_TOOLS; then
    echo ""
    ok "Python-only install complete."
    _print_activate_hint
    exit 0
fi

# ── Update package lists ──────────────────────────────────────────────────────
step "Updating package lists"
pkg_update || warn "Package update failed — continuing anyway"

# ── System tools (OS-aware) ───────────────────────────────────────────────────
step "System tools"

# nmap
if cmd_exists nmap && ! $FORCE; then
    ok "nmap already installed"
else
    info "Installing nmap..."
    _nmap_ok=false
    case "$PKG_MGR" in
        apt)         dry $SUDO apt-get install -y -qq nmap         && _nmap_ok=true ;;
        pacman)      dry $SUDO pacman -S --noconfirm nmap          && _nmap_ok=true ;;
        dnf|yum)     dry $SUDO ${PKG_MGR} install -y nmap         && _nmap_ok=true ;;
        brew)        dry brew install nmap                         && _nmap_ok=true ;;
        apk)         dry $SUDO apk add nmap nmap-scripts           && _nmap_ok=true ;;
        pkg)         dry pkg install -y nmap                       && _nmap_ok=true ;;
        xbps)        dry $SUDO xbps-install -y nmap                && _nmap_ok=true ;;
        zypper)      dry $SUDO zypper install -y nmap              && _nmap_ok=true ;;
        emerge)      dry $SUDO emerge -q net-analyzer/nmap         && _nmap_ok=true ;;
        freebsd_pkg) dry $SUDO pkg install -y nmap                 && _nmap_ok=true ;;
        nix)         dry nix-env -iA nixpkgs.nmap                  && _nmap_ok=true ;;
        eopkg)       dry $SUDO eopkg install -y nmap               && _nmap_ok=true ;;
        *)           warn "Cannot auto-install nmap — install manually" ;;
    esac
    { cmd_exists nmap || $_nmap_ok; } && ok "nmap installed" || warn "nmap install failed — install manually"
fi

# masscan (not available on Termux, BSD — skip gracefully)
if ! is_termux && ! is_openbsd && ! is_netbsd; then
    if cmd_exists masscan && ! $FORCE; then
        ok "masscan already installed"
    else
        info "Installing masscan..."
        _masscan_ok=false
        case "$PKG_MGR" in
            apt)         dry $SUDO apt-get install -y -qq masscan        && _masscan_ok=true ;;
            pacman)      dry $SUDO pacman -S --noconfirm masscan          && _masscan_ok=true ;;
            dnf|yum)
                warn "masscan not in default repo — building from source..."
                dry $SUDO ${PKG_MGR} install -y gcc git libpcap-devel \
                    && dry git clone --depth 1 https://github.com/robertdavidgraham/masscan /tmp/masscan_src \
                    && dry make -C /tmp/masscan_src -j"$(nproc)" \
                    && dry $SUDO cp /tmp/masscan_src/bin/masscan /usr/local/bin/ \
                    && dry rm -rf /tmp/masscan_src \
                    && _masscan_ok=true \
                    || warn "masscan build failed"
                ;;
            brew)        dry brew install masscan                         && _masscan_ok=true ;;
            apk)         dry $SUDO apk add masscan                        && _masscan_ok=true ;;
            xbps)        dry $SUDO xbps-install -y masscan                && _masscan_ok=true ;;
            zypper)      dry $SUDO zypper install -y masscan               && _masscan_ok=true ;;
            freebsd_pkg) dry $SUDO pkg install -y masscan                 && _masscan_ok=true ;;
            nix)         dry nix-env -iA nixpkgs.masscan                  && _masscan_ok=true ;;
            *)           warn "masscan not available on this platform" ;;
        esac
        { cmd_exists masscan || $_masscan_ok; } && ok "masscan installed" || warn "masscan unavailable — skipped"
    fi
fi

# nikto
if cmd_exists nikto && ! $FORCE; then
    ok "nikto already installed"
else
    info "Installing nikto..."
    _nikto_ok=false
    case "$PKG_MGR" in
        apt)         dry $SUDO apt-get install -y -qq nikto                      && _nikto_ok=true ;;
        pacman)      dry $SUDO pacman -S --noconfirm nikto                       && _nikto_ok=true ;;
        brew)        dry brew install nikto                                      && _nikto_ok=true ;;
        dnf|yum)     dry $SUDO ${PKG_MGR} install -y nikto 2>/dev/null          && _nikto_ok=true \
                         || { pip_install nikto                                  && _nikto_ok=true; } ;;
        apk)         dry $SUDO apk add nikto                                     && _nikto_ok=true ;;
        xbps)        dry $SUDO xbps-install -y nikto                             && _nikto_ok=true ;;
        pkg)         dry pkg install -y nikto                                    && _nikto_ok=true ;;
        freebsd_pkg) dry $SUDO pkg install -y nikto                              && _nikto_ok=true ;;
        nix)         dry nix-env -iA nixpkgs.nikto                               && _nikto_ok=true ;;
        *)           warn "nikto not available — skipped" ;;
    esac
    { cmd_exists nikto || $_nikto_ok; } && ok "nikto installed" || warn "nikto unavailable — skipped"
fi

# whatweb
if cmd_exists whatweb && ! $FORCE; then
    ok "whatweb already installed"
else
    info "Installing whatweb..."
    _whatweb_ok=false
    case "$PKG_MGR" in
        apt)    dry $SUDO apt-get install -y -qq whatweb                     && _whatweb_ok=true ;;
        pacman) dry $SUDO pacman -S --noconfirm whatweb                      && _whatweb_ok=true ;;
        brew)   dry brew install whatweb                                     && _whatweb_ok=true ;;
        apk)
            # whatweb needs ruby
            dry $SUDO apk add ruby && dry $SUDO gem install whatweb 2>/dev/null \
                && ok "whatweb installed via gem" && _whatweb_ok=true \
                || warn "whatweb unavailable on Alpine"
            ;;
        dnf|yum)
            # whatweb not in default repos — install via gem
            if cmd_exists gem; then
                dry gem install whatweb && _whatweb_ok=true && ok "whatweb installed via gem"
            else
                warn "whatweb not in repos — install ruby + gem install whatweb"
            fi
            ;;
        nix) dry nix-env -iA nixpkgs.whatweb                                && _whatweb_ok=true ;;
        *)   warn "whatweb not available on this platform — skipped" ;;
    esac
    { cmd_exists whatweb || $_whatweb_ok; } && ok "whatweb installed" || true
fi

# ── SecLists wordlists ─────────────────────────────────────────────────────────
step "SecLists wordlists"

SECLISTS_PATHS=(
    "/usr/share/seclists"
    "/usr/share/SecLists"
    "$HOME/seclists"
    "$HOME/SecLists"
    "/opt/SecLists"
    "/usr/local/share/seclists"
)
SECLISTS_FOUND=false
for p in "${SECLISTS_PATHS[@]}"; do
    if [[ -d "$p" ]]; then
        ok "SecLists found at $p"
        SECLISTS_FOUND=true
        break
    fi
done

if ! $SECLISTS_FOUND; then
    info "SecLists not found — installing..."
    if [[ "$PKG_MGR" == "apt" ]]; then
        dry $SUDO apt-get install -y -qq seclists 2>/dev/null && ok "SecLists installed via apt" || {
            warn "apt seclists failed — cloning from GitHub (~900 MB)..."
            dry $SUDO git clone --depth 1 \
                https://github.com/danielmiessler/SecLists.git \
                /usr/share/seclists 2>/dev/null \
                && ok "SecLists cloned to /usr/share/seclists" \
                || warn "SecLists install failed — built-in wordlist will be used"
        }
    elif is_termux; then
        # Termux: clone to home (no /usr/share)
        dry git clone --depth 1 \
            https://github.com/danielmiessler/SecLists.git \
            "$HOME/seclists" 2>/dev/null \
            && ok "SecLists cloned to ~/seclists" \
            || warn "SecLists clone failed — built-in wordlist will be used"
    elif [[ "$PKG_MGR" == "brew" ]]; then
        { dry brew install seclists 2>/dev/null \
            || dry git clone --depth 1 \
               https://github.com/danielmiessler/SecLists.git \
               "$HOME/seclists"; } \
        && ok "SecLists installed" \
        || warn "SecLists install failed — built-in wordlist will be used"
    else
        warn "SecLists not auto-installed on this platform."
        note "Install manually: git clone --depth 1 https://github.com/danielmiessler/SecLists ~/seclists"
    fi
fi

# ── Go language ───────────────────────────────────────────────────────────────
if ! $SKIP_GO; then
    step "Go language"

    if cmd_exists go && ! $FORCE; then
        ok "Go $(go version | awk '{print $3}') already installed"
    else
        info "Installing Go..."
        case "$PKG_MGR" in
            apt)
                dry $SUDO apt-get install -y -qq golang-go \
                    && ok "Go installed via apt" || {
                    warn "apt golang-go failed — install Go manually from: https://go.dev/dl/"
                    SKIP_GO=true
                }
                ;;
            pacman) dry $SUDO pacman -S --noconfirm go && ok "Go installed" ;;
            dnf|yum) dry $SUDO ${PKG_MGR} install -y golang && ok "Go installed" ;;
            brew)   dry brew install go && ok "Go installed" ;;
            apk)    dry $SUDO apk add go && ok "Go installed" ;;
            xbps)   dry $SUDO xbps-install -y go && ok "Go installed" ;;
            zypper) dry $SUDO zypper install -y go && ok "Go installed" ;;
            pkg)    dry pkg install -y golang && ok "Go installed" ;;   # Termux
            freebsd_pkg) dry $SUDO pkg install -y go && ok "Go installed" ;;
            emerge) dry $SUDO emerge -q dev-lang/go && ok "Go installed" ;;
            nix)    dry nix-env -iA nixpkgs.go && ok "Go installed" ;;
            eopkg)  dry $SUDO eopkg install -y golang && ok "Go installed" ;;
            *)
                err "Cannot auto-install Go. Get it from: https://go.dev/dl/"
                warn "Skipping all Go tools"
                SKIP_GO=true
                ;;
        esac
        cmd_exists go || SKIP_GO=true
    fi

    if ! $SKIP_GO; then
        export PATH="$PATH:$(go env GOPATH 2>/dev/null)/bin"
        dry mkdir -p "$(go env GOPATH 2>/dev/null)/bin" 2>/dev/null || true

        # Persist GOPATH/bin across shells
        GOBIN="$(go env GOPATH 2>/dev/null)/bin"
        for cfg_file in "${SHELL_CONFIGS[@]}"; do
            if ! grep -q "$GOBIN" "$cfg_file" 2>/dev/null; then
                if [[ "$cfg_file" == *"fish"* ]]; then
                    $DRY_RUN || echo "fish_add_path $GOBIN" >> "$cfg_file" 2>/dev/null || true
                else
                    echo "export PATH=\"\$PATH:$GOBIN\"" >> "$cfg_file" 2>/dev/null || true
                fi
            fi
        done

        step "Go recon tools"

        _go_install() {
            local bin="$1" pkg="$2"
            if cmd_exists "$bin" && ! $FORCE; then
                ok "$bin already installed"
            else
                info "Installing $bin..."
                dry go install "$pkg" 2>/dev/null \
                    && ok "$bin installed" \
                    || warn "$bin install failed — install manually: go install $pkg"
            fi
        }

        _go_install subfinder   "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
        _go_install httpx       "github.com/projectdiscovery/httpx/cmd/httpx@latest"
        _go_install nuclei      "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
        _go_install ffuf        "github.com/ffuf/ffuf/v2@latest"
        _go_install assetfinder "github.com/tomnomnom/assetfinder@latest"
        _go_install gowitness   "github.com/sensepost/gowitness@latest"
        _go_install katana      "github.com/projectdiscovery/katana/cmd/katana@latest"

        # amass (large — separate notice)
        if cmd_exists amass && ! $FORCE; then
            ok "amass already installed"
        else
            info "Installing amass (this may take 1-3 minutes)..."
            dry go install github.com/owasp-amass/amass/v4/...@master 2>/dev/null \
                && ok "amass installed" \
                || warn "amass install failed — install manually"
        fi
    fi
fi

# ── RustScan ──────────────────────────────────────────────────────────────────
if ! $SKIP_RUST; then
    step "RustScan (primary port scanner)"

    _rs_via_pkg=false
    _rs_deb_ok=false
    ARCH="$(uname -m)"

    if cmd_exists rustscan && ! $FORCE; then
        ok "RustScan already installed"
    else
        case "$PKG_MGR" in
            brew)        dry brew install rustscan && _rs_via_pkg=true ;;
            pacman)      dry $SUDO pacman -S --noconfirm rustscan 2>/dev/null && _rs_via_pkg=true ;;
            pkg)         dry pkg install -y rustscan 2>/dev/null && _rs_via_pkg=true ;;  # Termux
            freebsd_pkg) dry $SUDO pkg install -y rustscan 2>/dev/null && _rs_via_pkg=true ;;
            nix)         dry nix-env -iA nixpkgs.rustscan 2>/dev/null && _rs_via_pkg=true ;;
        esac

        if ! $_rs_via_pkg; then
            # Try pre-built .deb on apt systems
            _rs_deb_ok=false
            if [[ "$PKG_MGR" == "apt" ]]; then
                RS_DEB=""
                case "$ARCH" in
                    x86_64)  RS_DEB="rustscan_amd64.deb" ;;
                    aarch64) RS_DEB="rustscan_arm64.deb" ;;
                    armv7l)  RS_DEB="rustscan_armhf.deb" ;;
                esac
                if [[ -n "$RS_DEB" ]]; then
                    TMP=$(mktemp /tmp/rustscan_XXXXXX.deb)
                    if dry curl -fsSL \
                        "https://github.com/RustScan/RustScan/releases/latest/download/$RS_DEB" \
                        -o "$TMP" 2>/dev/null \
                    && dry $SUDO dpkg -i "$TMP"; then
                        ok "RustScan installed from .deb"
                        _rs_deb_ok=true
                    else
                        warn "Pre-built .deb failed"
                    fi
                    rm -f "$TMP"
                fi
            fi

            # Cargo fallback — only if .deb didn't work and not dry-run installed
            if ! $_rs_deb_ok && ! cmd_exists rustscan; then
                if ! cmd_exists cargo; then
                    info "Rust toolchain not found — installing via rustup..."
                    if $DRY_RUN; then
                        echo -e "${MAGENTA}  [DRY-RUN]${NC}  curl https://sh.rustup.rs | sh"
                    else
                        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
                            | sh -s -- -y --no-modify-path 2>/dev/null \
                        && export PATH="$HOME/.cargo/bin:$PATH" \
                        && ok "Rust toolchain installed" \
                        || warn "Rust install failed"
                    fi
                fi

                if cmd_exists cargo; then
                    info "Building RustScan from source (takes a few minutes)..."
                    dry cargo install rustscan && ok "RustScan installed via cargo" \
                        || warn "cargo install rustscan failed"
                    # Persist cargo bin
                    for cfg_file in "${SHELL_CONFIGS[@]}"; do
                        if ! grep -q '\.cargo/bin' "$cfg_file" 2>/dev/null; then
                            echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$cfg_file" 2>/dev/null || true
                        fi
                    done
                else
                    warn "Cannot install RustScan — Rust toolchain unavailable"
                    note "Manual install: https://github.com/RustScan/RustScan"
                fi
            fi
        fi

        { cmd_exists rustscan || $_rs_deb_ok || $_rs_via_pkg; } && ok "RustScan installed" || warn "RustScan unavailable on this platform"
    fi
fi

# ── feroxbuster ───────────────────────────────────────────────────────────────
step "feroxbuster (directory scanner)"

if cmd_exists feroxbuster && ! $FORCE; then
    ok "feroxbuster already installed"
else
    info "Installing feroxbuster..."
    case "$PKG_MGR" in
        apt)
            dry $SUDO apt-get install -y -qq feroxbuster 2>/dev/null && ok "feroxbuster installed" || {
                info "apt failed — using curl installer..."
                dry curl -sL \
                    https://raw.githubusercontent.com/epi052/feroxbuster/main/install-nix.sh \
                    | bash -s "$HOME/.local/bin" 2>/dev/null \
                    && ok "feroxbuster installed to ~/.local/bin" \
                    || warn "feroxbuster install failed — ffuf/dirsearch fallback will be used"
            }
            ;;
        brew)    dry brew install feroxbuster && ok "feroxbuster installed" ;;
        pacman)  dry $SUDO pacman -S --noconfirm feroxbuster && ok "feroxbuster installed" ;;
        nix)     dry nix-env -iA nixpkgs.feroxbuster && ok "feroxbuster installed" ;;
        pkg)
            # Termux: no pre-built — skip, use ffuf fallback
            warn "feroxbuster not available in Termux — ffuf/dirsearch will be used"
            ;;
        *)
            # Try cargo
            if cmd_exists cargo; then
                dry cargo install feroxbuster && ok "feroxbuster installed via cargo" \
                    || warn "feroxbuster unavailable — ffuf/dirsearch fallback will be used"
            else
                warn "feroxbuster unavailable on this platform — ffuf/dirsearch fallback will be used"
            fi
            ;;
    esac
fi

# ── dirsearch (pip — universal) ───────────────────────────────────────────────
step "dirsearch (directory scanner fallback)"

if cmd_exists dirsearch && ! $FORCE; then
    ok "dirsearch already installed"
else
    pip_install dirsearch && ok "dirsearch installed" || warn "dirsearch install failed"
fi

# ── Nuclei templates ──────────────────────────────────────────────────────────
step "Nuclei templates"

if cmd_exists nuclei; then
    info "Updating nuclei templates..."
    dry nuclei -update-templates -silent 2>/dev/null \
        && ok "Nuclei templates updated" \
        || ok "Templates will auto-download on first run"
else
    warn "nuclei not installed — vulnerability scanning will be skipped"
    note "Install manually: go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
fi

# ── Termux extras: aquatone alternative ───────────────────────────────────────
if is_termux; then
    step "Termux extras"
    # gowitness is the screenshot tool and is installed via go above
    # aquatone has no arm binary — skip it
    note "aquatone not available on Android/Termux — gowitness will be used for screenshots"
    # Ensure termux storage is set up for reports
    if [[ ! -d "$HOME/storage" ]]; then
        warn "Run 'termux-setup-storage' once to enable file access from Android gallery"
    fi
fi

# ── Final tool status ─────────────────────────────────────────────────────────
step "Final tool check"
echo ""
$DRY_RUN || "$PYTHON" "$INSTALL_DIR/reconninja.py" --check-tools
echo ""

# ── Done banner ───────────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════════╗"
echo "  ║                                                               ║"
printf "  ║   ✔  ReconNinja v%-6s installed to ~/.reconninja/          ║\n" "${RN_VERSION}"
echo "  ║   ✔  'ReconNinja' alias created in all detected shell files   ║"
echo "  ║   ✔  Wrapper script at ~/.local/bin/ReconNinja                ║"
echo "  ║                                                               ║"
echo "  ║   Supported platforms: Kali · Ubuntu · Debian · Parrot       ║"
echo "  ║     Arch · Manjaro · Fedora · CentOS · Rocky · AlmaLinux     ║"
echo "  ║     openSUSE · Alpine · Void · Gentoo · NixOS · Solus        ║"
echo "  ║     macOS · FreeBSD · OpenBSD · NetBSD · WSL2 · Termux       ║"
echo "  ║                                                               ║"
echo "  ║   Docs: https://github.com/YouTubers777/ReconNinja            ║"
echo "  ╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

_print_activate_hint

echo -e "${RED}  ⚠  Only scan systems you own or have explicit written permission to test.${NC}"
echo ""
