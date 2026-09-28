#!/bin/sh
# install.sh — Installer/uninstaller for passwall2-hpwnr-patch
#
# Interactive install:  sh install.sh
# Install + hpwnr:      sh install.sh --with-hpwnr
# Non-interactive:      sh install.sh --yes
# All at once:          sh install.sh --with-hpwnr --yes
# Uninstall:            sh install.sh uninstall

REPO="https://github.com/WhiteDuke-IOI/passwall2-hpwnr-patch"
REPO_RAW="https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main"

# ── Пути ─────────────────────────────────────────────────────
HPWNR_LUA="/usr/share/passwall2/hpwnr.lua"
PATCH_SCRIPT="/usr/bin/passwall2-hpwnr-patch"
INITD_SCRIPT="/etc/init.d/passwall2-hpwnr"
HPWNR_BIN="/usr/bin/hpwnr"
SYSUPGRADE_CONF="/etc/sysupgrade.conf"
APK_HOOK="/etc/apk/commit_hooks.d/passwall2-hpwnr"
OPKG_HOOK="/etc/opkg/post-install.d/passwall2-hpwnr"
SYSUPGRADE_MARKER="# passwall2-hpwnr-patch"

# ── Цвета ────────────────────────────────────────────────────
if [ -t 1 ]; then
    GREEN=$(printf '\033[0;32m'); YELLOW=$(printf '\033[1;33m')
    RED=$(printf '\033[0;31m');   CYAN=$(printf '\033[0;36m')
    BOLD=$(printf '\033[1m');     NC=$(printf '\033[0m')
else
    GREEN=''; YELLOW=''; RED=''; CYAN=''; BOLD=''; NC=''
fi


info()    { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
error()   { printf "${RED}[✗]${NC} %s\n" "$*" >&2; }
ok()      { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
section() { printf "\n${BOLD}${CYAN}── %s${NC}\n" "$*"; }

# ── Аргументы ────────────────────────────────────────────────
OPT_YES=0
OPT_WITH_HPWNR=0
OPT_UNINSTALL=0

for arg in "$@"; do
    case "$arg" in
        uninstall|remove|--uninstall|-u) OPT_UNINSTALL=1 ;;
        --with-hpwnr|-H)                OPT_WITH_HPWNR=1 ;;
        --yes|-y)                        OPT_YES=1 ;;
        install|--install|-i)            : ;;
        *)
            error "Unknown argument: $arg"
            echo "Usage: $0 [uninstall] [--with-hpwnr] [--yes]"
            exit 1
            ;;
    esac
done

# ── Утилиты ──────────────────────────────────────────────────
ask() {
    local prompt="$1"
    local default="${2:-y}"

    if [ "$OPT_YES" = "1" ]; then
        return 0
    fi

    # Проверяем что /dev/tty доступен (терминал есть)
    if [ ! -c /dev/tty ]; then
        # Нет терминала — используем default
        warn "No TTY available, using default answer for: $prompt"
        case "$default" in
            y) return 0 ;;
            *) return 1 ;;
        esac
    fi

    local hint
    case "$default" in
        y) hint="[Y/n]" ;;
        n) hint="[y/N]" ;;
    esac

    printf "${YELLOW}?${NC} %s %s " "$prompt" "$hint"
    read -r ans </dev/tty   # ← читает с терминала напрямую, минуя pipe

    if [ -z "$ans" ]; then
        ans="$default"
    fi

    case "$ans" in
        y|Y|yes|YES) return 0 ;;
        *)            return 1 ;;
    esac
}

download() {
    local url="$1"
    local dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -sSL --fail -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        error "Neither curl nor wget found!"
        exit 1
    fi
}

detect_pkg_manager() {
    if command -v apk >/dev/null 2>&1; then echo "apk"
    elif command -v opkg >/dev/null 2>&1; then echo "opkg"
    else echo "none"
    fi
}

# ── Определение архитектуры роутера ──────────────────────────
detect_arch() {
    local machine
    machine=$(uname -m 2>/dev/null || echo "unknown")

    case "$machine" in
        aarch64)          echo "aarch64" ;;
        x86_64)           echo "x86_64" ;;
        mips)
            # Определяем endianness
            if grep -q "mipsel" /proc/cpuinfo 2>/dev/null \
            || echo "$machine" | grep -q "el"; then
                echo "mipsel"
            else
                echo "mips"
            fi
            ;;
        mipsel)           echo "mipsel" ;;
        armv7*|armv6*)    echo "arm" ;;
        arm*)             echo "arm" ;;
        *)                echo "unknown" ;;
    esac
}

# ════════════════════════════════════════════════════════════
# INSTALL HPWNR BINARY
# ════════════════════════════════════════════════════════════
install_hpwnr_binary() {
    local arch
    arch=$(detect_arch)

    info "Detected architecture: ${BOLD}${arch}${NC}"

    if [ "$arch" = "unknown" ]; then
        warn "Cannot detect architecture automatically."
        warn "Available: aarch64, x86_64, mipsel, mips, arm"
        printf "${YELLOW}?${NC} Enter your architecture: "
        read -r arch
        if [ -z "$arch" ]; then
            warn "Skipping hpwnr binary installation."
            return 1
        fi
    fi

    local url="${REPO_RAW}/files/hpwnr/${arch}"
    info "Downloading hpwnr for ${arch}..."
    info "  URL: ${url}"

    local tmp_bin
    tmp_bin=$(mktemp)

    if ! download "$url" "$tmp_bin"; then
        error "Download failed! Binary for '${arch}' may not be in the repository yet."
        warn "Available binaries: ${REPO}/tree/main/files/hpwnr"
        warn "Or build from source: https://github.com/Omegaplexx/hpwnr"
        rm -f "$tmp_bin"
        return 1
    fi

    # Проверяем что это не HTML страница 404
    local first_bytes
    first_bytes=$(head -c 4 "$tmp_bin" 2>/dev/null | cat -v)
    if echo "$first_bytes" | grep -q "404\|<htm\|Not F"; then
        error "Downloaded file looks like an error page, not a binary."
        rm -f "$tmp_bin"
        return 1
    fi

    chmod +x "$tmp_bin"

    # Проверяем что бинарник запускается (базовая проверка)
    if ! "$tmp_bin" help >/dev/null 2>&1; then
        warn "Binary downloaded but failed to execute — may be wrong architecture."
        warn "Binary saved to $HPWNR_BIN anyway, check manually."
    fi

    mv "$tmp_bin" "$HPWNR_BIN"
    ok "hpwnr installed: $HPWNR_BIN (arch: ${arch})"
    return 0
}

# ════════════════════════════════════════════════════════════
# UNINSTALL
# ════════════════════════════════════════════════════════════
do_uninstall() {
    section "Uninstalling passwall2-hpwnr-patch"

    # 1. Снять патч с subscribe.lua
    if grep -q "HPWNR_PATCHED" /usr/share/passwall2/subscribe.lua 2>/dev/null; then
        info "Restoring subscribe.lua..."
        if [ -x "$PATCH_SCRIPT" ]; then
            "$PATCH_SCRIPT" unapply
        else
            # Скрипт уже удалён — пробуем backup напрямую
            local bak="/usr/share/passwall2/subscribe.lua.pre-hpwnr.bak"
            if [ -f "$bak" ]; then
                cp "$bak" "/usr/share/passwall2/subscribe.lua"
                rm -f "$bak"
                ok "subscribe.lua restored from backup"
            else
                warn "Backup not found, reinstalling passwall2 package..."
                local pkgmgr
                pkgmgr=$(detect_pkg_manager)
                case "$pkgmgr" in
                    apk)
                        apk fix luci-app-passwall2 >/dev/null 2>&1 \
                            && ok "passwall2 restored via apk fix" \
                            || warn "apk fix failed — restore subscribe.lua manually"
                        ;;
                    opkg)
                        opkg install --force-reinstall luci-app-passwall2 >/dev/null 2>&1 \
                            && ok "passwall2 restored via opkg" \
                            || warn "opkg failed — restore subscribe.lua manually"
                        ;;
                    *)
                        warn "No package manager found — restore subscribe.lua manually"
                        ;;
                esac
            fi
        fi
    else
        ok "subscribe.lua is already clean (no patch marker found)"
    fi

    # 2. Удаляем файлы
    section "Removing installed files"
    for f in \
        "$HPWNR_LUA" \
        "$PATCH_SCRIPT" \
        "/usr/share/passwall2/subscribe.lua.pre-hpwnr.bak" \
        "$APK_HOOK" \
        "$OPKG_HOOK"
    do
        if [ -f "$f" ]; then
            rm -f "$f"
            ok "Removed: $f"
        fi
    done

    # init.d — выключаем и удаляем
    if [ -f "$INITD_SCRIPT" ]; then
        "$INITD_SCRIPT" disable 2>/dev/null || true
        "$INITD_SCRIPT" stop 2>/dev/null || true
        rm -f "$INITD_SCRIPT"
        ok "Removed: $INITD_SCRIPT"
    fi

    # 3. hpwnr binary — спрашиваем
    if [ -f "$HPWNR_BIN" ]; then
        if ask "Remove hpwnr binary ($HPWNR_BIN)?" "n"; then
            rm -f "$HPWNR_BIN"
            ok "Removed: $HPWNR_BIN"
        else
            info "Keeping $HPWNR_BIN"
        fi
    fi

    # 4. Чистим sysupgrade.conf
    if grep -q "^${SYSUPGRADE_MARKER} begin$" "$SYSUPGRADE_CONF" 2>/dev/null; then
        sed -i "/^${SYSUPGRADE_MARKER} begin$/,/^${SYSUPGRADE_MARKER} end$/d" \
            "$SYSUPGRADE_CONF"
        ok "Cleaned sysupgrade.conf"
    fi

    echo ""
    ok "Uninstall complete. PassWall2 is back to its original state."
}

# ════════════════════════════════════════════════════════════
# INSTALL
# ════════════════════════════════════════════════════════════
do_install() {
    echo ""
    printf "${BOLD}${CYAN}passwall2-hpwnr-patch${NC}\n"
    printf "  %s\n\n" "$REPO"

    # ── Проверки окружения ────────────────────────────────────
    section "Checking environment"

    if [ ! -f /etc/openwrt_release ]; then
        error "This script is designed for OpenWrt only."
        exit 1
    fi

    local owrt_ver pkgmgr
    owrt_ver=$(grep "DISTRIB_RELEASE" /etc/openwrt_release \
        | cut -d= -f2 | tr -d '"')
    pkgmgr=$(detect_pkg_manager)

    ok "OpenWrt: ${owrt_ver}"
    ok "Package manager: ${pkgmgr}"

    if [ ! -d /usr/share/passwall2 ]; then
        warn "PassWall2 not found — install it first."
        warn "Patch will auto-apply on next boot after PassWall2 is installed."
    else
        ok "PassWall2: found"
    fi

    # ── hpwnr binary ──────────────────────────────────────────
    section "hpwnr binary"

    if command -v hpwnr >/dev/null 2>&1; then
        ok "hpwnr already installed: $(command -v hpwnr)"
        hpwnr help 2>/dev/null | head -1 || true

        if ask "Re-download hpwnr from this repository?" "n"; then
            install_hpwnr_binary || warn "hpwnr download failed, keeping existing binary."
        fi
    else
        warn "hpwnr not found in PATH."

        # Проверяем флаг --with-hpwnr или спрашиваем
        if [ "$OPT_WITH_HPWNR" = "1" ] || ask "Download hpwnr binary from this repository?" "y"; then
            install_hpwnr_binary || warn "Continuing without hpwnr binary."
        else
            warn "Skipped. Install hpwnr manually before using encrypted subscriptions."
        fi
    fi

    # ── Основные файлы ───────────────────────────────────────
    section "Downloading patch files"

    info "hpwnr.lua..."
    mkdir -p /usr/share/passwall2
    download "${REPO_RAW}/files/hpwnr.lua" "$HPWNR_LUA"
    ok "$HPWNR_LUA"

    info "passwall2-hpwnr-patch..."
    download "${REPO_RAW}/files/passwall2-hpwnr-patch" "$PATCH_SCRIPT"
    chmod +x "$PATCH_SCRIPT"
    ok "$PATCH_SCRIPT"

    # ── init.d ───────────────────────────────────────────────
    section "Setting up auto-patch hooks"

    info "Creating init.d service..."
    cat > "$INITD_SCRIPT" << 'INITD_EOF'
#!/bin/sh /etc/rc.common
# passwall2-hpwnr-patch — re-apply hpwnr patch on boot
START=99
STOP=10

start() {
    /usr/bin/passwall2-hpwnr-patch
}
INITD_EOF
    chmod +x "$INITD_SCRIPT"
    "$INITD_SCRIPT" enable 2>/dev/null || true
    ok "init.d service: $INITD_SCRIPT (START=99)"

    # ── Хук пакетного менеджера ───────────────────────────────
    case "$pkgmgr" in
        apk)
            mkdir -p /etc/apk/commit_hooks.d
            cat > "$APK_HOOK" << 'APK_EOF'
#!/bin/sh
# passwall2-hpwnr-patch: re-apply patch after any apk transaction
[ -x /usr/bin/passwall2-hpwnr-patch ] && /usr/bin/passwall2-hpwnr-patch
APK_EOF
            chmod +x "$APK_HOOK"
            ok "apk commit hook: $APK_HOOK"
            ;;
        opkg)
            mkdir -p /etc/opkg/post-install.d
            cat > "$OPKG_HOOK" << 'OPKG_EOF'
#!/bin/sh
[ -x /usr/bin/passwall2-hpwnr-patch ] && /usr/bin/passwall2-hpwnr-patch
OPKG_EOF
            chmod +x "$OPKG_HOOK"
            ok "opkg post-install hook: $OPKG_HOOK"
            ;;
        *)
            warn "Unknown package manager — no package hook created."
            warn "Patch will still re-apply on every boot via init.d."
            ;;
    esac

    # ── sysupgrade.conf ──────────────────────────────────────
    section "Updating sysupgrade.conf"

    # Удаляем старый блок (идемпотентность)
    sed -i "/^${SYSUPGRADE_MARKER} begin$/,/^${SYSUPGRADE_MARKER} end$/d" \
        "$SYSUPGRADE_CONF" 2>/dev/null || true

    {
        printf "\n%s begin\n" "$SYSUPGRADE_MARKER"
        printf "%s\n" "$HPWNR_LUA"
        printf "%s\n" "$PATCH_SCRIPT"
        printf "%s\n" "$INITD_SCRIPT"
        case "$pkgmgr" in
            apk)  printf "%s\n" "$APK_HOOK" ;;
            opkg) printf "%s\n" "$OPKG_HOOK" ;;
        esac
        # hpwnr binary — только если установлен
        if command -v hpwnr >/dev/null 2>&1; then
            printf "%s\n" "$(command -v hpwnr)"
        fi
        printf "%s end\n" "$SYSUPGRADE_MARKER"
    } >> "$SYSUPGRADE_CONF"

    ok "sysupgrade.conf updated"
    info "Verify with: ${CYAN}sysupgrade -l | grep hpwnr${NC}"

    # ── Применяем патч ───────────────────────────────────────
    section "Applying patch"
    "$PATCH_SCRIPT"

    # ── Итог ─────────────────────────────────────────────────
    section "Installation complete"
    echo ""
    echo "  Auto-patch triggers:"
    echo "    ${GREEN}✓${NC} Every boot              (init.d START=99)"
    case "$pkgmgr" in
        apk)  echo "    ${GREEN}✓${NC} After apk install/upgrade  (commit hook)" ;;
        opkg) echo "    ${GREEN}✓${NC} After opkg install/upgrade (post-install hook)" ;;
    esac
    echo "    ${GREEN}✓${NC} After sysupgrade         (files in sysupgrade.conf)"
    echo ""
    echo "  Verify:"
    printf "    %s\n" "${CYAN}sysupgrade -l | grep hpwnr${NC}"
    printf "    %s\n" "${CYAN}cat /tmp/log/passwall2.log | grep hpwnr${NC}"
    echo ""
    echo "  To uninstall:"
    printf "    %s\n" "${CYAN}sh install.sh uninstall${NC}"
    echo ""
}

# ════════════════════════════════════════════════════════════
# ENTRYPOINT
# ════════════════════════════════════════════════════════════
if [ "$OPT_UNINSTALL" = "1" ]; then
    do_uninstall
else
    do_install
fi