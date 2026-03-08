#!/bin/bash
#
# qso-graph-config — Manager for QSO-Graph ham radio MCP servers.
#
# Pure bash + dialog/whiptail TUI.
# Falls back to numbered prompts when neither is available.
#
# All state lives under ~/.qso-graph/:
#   venv/     Python virtual environment (servers installed here)
#   bin/      Wrapper scripts (user adds to PATH)
#   etc/      state.json
#   log/      Install logs
#
# License: GPL-3.0-or-later
#------------------------------------------------------------------------------#

VERSION="0.1.2"

# ─── Dialog exit status codes ────────────────────────────────────────────────

: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_HELP=2}
: ${DIALOG_EXTRA=3}
: ${DIALOG_ITEM_HELP=4}
: ${DIALOG_ESC=255}

# ─── Paths ───────────────────────────────────────────────────────────────────

QSO_GRAPH_HOME="$HOME/.qso-graph"
VENV_DIR="$QSO_GRAPH_HOME/venv"
BIN_DIR="$QSO_GRAPH_HOME/bin"
ETC_DIR="$QSO_GRAPH_HOME/etc"
LOG_DIR="$QSO_GRAPH_HOME/log"
STATE_FILE="$ETC_DIR/state.json"
PIP="$VENV_DIR/bin/pip"

BACKTITLE="QSO-Graph Config v${VERSION}"

# ─── Package definitions ────────────────────────────────────────────────────

BASE_PKGS="adif-mcp solar-mcp pota-mcp sota-mcp iota-mcp wspr-mcp"
AUTH_PKGS="qso-graph-auth qrz-mcp eqsl-mcp lotw-mcp hamqth-mcp"
IONIS_PKGS="ionis-mcp"

ENTRY_POINTS="qso-graph-config adif-mcp solar-mcp pota-mcp sota-mcp iota-mcp wspr-mcp qso-auth qrz-mcp eqsl-mcp lotw-mcp hamqth-mcp ionis-mcp ionis-download"

# ─── Dialog detection ───────────────────────────────────────────────────────

MSGCLIENT=""

detect_dialog() {
    if command -v dialog >/dev/null 2>&1; then
        MSGCLIENT="dialog"
    elif command -v whiptail >/dev/null 2>&1; then
        MSGCLIENT="whiptail"
    fi
}

# ─── Terminal cleanup ────────────────────────────────────────────────────────

unset_options() {
    set +e
    set +o pipefail
    set +u
}

clean_exit() {
    local EXIT_STATUS=$?
    unset_options
    stty sane 2>/dev/null || true
    printf '\033[?25h'
    clear
    if [ "$EXIT_STATUS" -eq 0 ]; then
        echo "QSO-Graph Config — clean exit."
    else
        echo "Exit status [ $EXIT_STATUS ]"
    fi
    trap - SIGHUP SIGINT SIGQUIT SIGTERM SIGTSTP
    exit "$EXIT_STATUS"
}

sig_catch_cleanup() {
    local EXIT_STATUS=$?
    unset_options
    stty sane 2>/dev/null || true
    printf '\033[?25h'
    clear
    echo "Signal caught, performing cleanup."
    trap - SIGHUP SIGINT SIGQUIT SIGTERM SIGTSTP
    exit "$EXIT_STATUS"
}

# ─── Helper functions ───────────────────────────────────────────────────────

get_version() {
    "$VENV_DIR/bin/python3" -c \
        "import importlib.metadata; print(importlib.metadata.version('$1'))" 2>/dev/null
}

is_installed() {
    "$VENV_DIR/bin/python3" -c \
        "import importlib.metadata; importlib.metadata.version('$1')" 2>/dev/null
}

has_auth() { is_installed "qso-graph-auth"; }
has_ionis() { is_installed "ionis-mcp"; }

current_tier() {
    if has_ionis && has_auth; then echo "full"
    elif has_ionis; then echo "ionis"
    elif has_auth; then echo "auth"
    else echo "base"
    fi
}

create_wrappers() {
    local count=0
    for name in $ENTRY_POINTS; do
        local venv_path="$VENV_DIR/bin/$name"
        [ -f "$venv_path" ] || continue
        local wrapper="$BIN_DIR/$name"
        cat > "$wrapper" <<WRAPPER
#!/bin/sh
exec $venv_path "\$@"
WRAPPER
        chmod 755 "$wrapper"
        count=$((count + 1))
    done
    echo "$count"
}

update_state() {
    local tier="$1"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local python_path=""
    local installed_at="$now"

    if [ -f "$STATE_FILE" ]; then
        python_path=$(grep -o '"python_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null \
            | sed 's/.*"python_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        local existing_installed
        existing_installed=$(grep -o '"installed_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null \
            | sed 's/.*"installed_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        [ -n "$existing_installed" ] && installed_at="$existing_installed"
    fi

    cat > "$STATE_FILE" <<STATE
{
  "tier": "$tier",
  "installed_at": "$installed_at",
  "last_upgrade": "$now",
  "python_path": "$python_path"
}
STATE
}

# ─── Menu actions ────────────────────────────────────────────────────────────

do_install() {
    local auth_default="OFF"
    local ionis_default="OFF"
    has_auth && auth_default="ON"
    has_ionis && ionis_default="ON"

    exec 3>&1
    selection=$($MSGCLIENT \
        --backtitle "$BACKTITLE" \
        --title " Install Components" \
        --checklist "Select components to install. Base is always included." \
        14 65 3 \
        "base"  "Base — 6 public servers (38 tools)"              "ON" \
        "auth"  "Auth — 4 logbook servers + qso-auth (22 tools)"  "$auth_default" \
        "ionis" "ionis-mcp — HF propagation analytics (11 tools)" "$ionis_default" \
        2>&1 1>&3)
    exit_status=$?
    exec 3>&-

    [ "$exit_status" -ne "$DIALOG_OK" ] && return

    # Build package list — base always included
    local packages="$BASE_PKGS"
    local tier="base"

    case "$selection" in
        *auth*ionis*|*ionis*auth*)
            packages="$BASE_PKGS $AUTH_PKGS $IONIS_PKGS"
            tier="full" ;;
        *auth*)
            packages="$BASE_PKGS $AUTH_PKGS"
            tier="auth" ;;
        *ionis*)
            packages="$BASE_PKGS $IONIS_PKGS"
            tier="ionis" ;;
    esac

    clear
    echo ""
    echo "Installing packages from PyPI..."
    echo ""
    # shellcheck disable=SC2086
    "$PIP" install --upgrade $packages

    local count
    count=$(create_wrappers)
    update_state "$tier"

    local msg="Installed successfully.\n\n$count commands in ~/.qso-graph/bin/"
    case "$selection" in
        *auth*) msg="$msg\n\nNext: set up credentials via Manage Credentials." ;;
    esac
    case "$selection" in
        *ionis*) msg="$msg\n\nNext: download datasets via Download Datasets." ;;
    esac

    $MSGCLIENT --backtitle "$BACKTITLE" \
        --title " Install Complete" \
        --msgbox "$msg" 14 60
}

do_credentials() {
    if ! has_auth; then
        $MSGCLIENT --backtitle "$BACKTITLE" \
            --title " Not Installed" \
            --msgbox "Auth servers are not installed.\n\nInstall them first via Install Servers." 10 55
        return
    fi

    local qso_auth="$VENV_DIR/bin/qso-auth"
    if [ ! -f "$qso_auth" ]; then
        $MSGCLIENT --backtitle "$BACKTITLE" \
            --title " Error" \
            --msgbox "qso-auth CLI not found." 8 40
        return
    fi

    while true; do
        exec 3>&1
        selection=$($MSGCLIENT \
            --backtitle "$BACKTITLE" \
            --title " Manage Credentials" \
            --menu "Set up credentials for logbook services." \
            16 55 7 \
            "persona" "Create / manage persona" \
            "eqsl"    "Set eQSL.cc credentials" \
            "qrz"     "Set QRZ.com credentials" \
            "lotw"    "Set LoTW credentials" \
            "hamqth"  "Set HamQTH credentials" \
            "doctor"  "Verify all credentials" \
            "back"    "Back to main menu" \
            2>&1 1>&3)
        exit_status=$?
        exec 3>&-

        [ "$exit_status" -ne "$DIALOG_OK" ] && return
        [ "$selection" = "back" ] && return

        clear
        case "$selection" in
            persona) "$qso_auth" persona add ;;
            doctor)
                "$qso_auth" creds doctor
                read -rp "Press Enter to continue..."
                ;;
            *)
                local persona
                persona=$("$qso_auth" persona list 2>/dev/null | head -1 | awk '{print $1}')
                [ -z "$persona" ] && persona="default"
                "$qso_auth" creds set "$persona" "$selection"
                read -rp "Press Enter to continue..."
                ;;
        esac
    done
}

do_datasets() {
    if ! has_ionis; then
        $MSGCLIENT --backtitle "$BACKTITLE" \
            --title " Not Installed" \
            --msgbox "ionis-mcp is not installed.\n\nInstall it first via Install Servers." 10 55
        return
    fi

    local ionis_dl="$VENV_DIR/bin/ionis-download"
    if [ ! -f "$ionis_dl" ]; then
        $MSGCLIENT --backtitle "$BACKTITLE" \
            --title " Error" \
            --msgbox "ionis-download CLI not found." 8 40
        return
    fi

    exec 3>&1
    selection=$($MSGCLIENT \
        --backtitle "$BACKTITLE" \
        --title " Download Datasets" \
        --radiolist "Select a dataset bundle for ionis-mcp.\nMinimal is required." \
        14 65 3 \
        "minimal"     "Contest + grids + solar (~430 MB)"             "ON" \
        "recommended" "Minimal + PSKR + DSCOVR + balloons (~1.1 GB)" "OFF" \
        "full"        "All 9 datasets (~15 GB)"                       "OFF" \
        2>&1 1>&3)
    exit_status=$?
    exec 3>&-

    [ "$exit_status" -ne "$DIALOG_OK" ] && return

    if [ "$selection" = "full" ]; then
        $MSGCLIENT --backtitle "$BACKTITLE" \
            --title " Confirm Download" \
            --yesno "The full dataset is approximately 15 GB.\n\nThis may take a while. Continue?" 8 55
        [ $? -ne "$DIALOG_OK" ] && return
    fi

    clear
    echo ""
    "$ionis_dl" --bundle "$selection"
    read -rp "Press Enter to continue..."
}

do_status() {
    local lines="Installed MCP servers:\n\n"
    local count=0

    for pkg in $BASE_PKGS $AUTH_PKGS $IONIS_PKGS; do
        local ver
        ver=$(get_version "$pkg" 2>/dev/null)
        if [ -n "$ver" ]; then
            lines="${lines}  $(printf '%-20s' "$pkg")  v${ver}\n"
            count=$((count + 1))
        fi
    done

    lines="${lines}\n${count} packages installed."
    lines="${lines}\nTier: $(current_tier)"
    lines="${lines}\nHome: $QSO_GRAPH_HOME"

    $MSGCLIENT --backtitle "$BACKTITLE" \
        --title " Server Status" \
        --msgbox "$lines" $((count + 10)) 55
}

do_configure() {
    exec 3>&1
    selection=$($MSGCLIENT \
        --backtitle "$BACKTITLE" \
        --title " Configure MCP Client" \
        --menu "Select your MCP client to see the config snippet." \
        18 55 9 \
        "1" "Claude Desktop" \
        "2" "Claude Code" \
        "3" "VS Code (Copilot)" \
        "4" "Cursor" \
        "5" "Windsurf" \
        "6" "ChatGPT Desktop" \
        "7" "Gemini CLI" \
        "8" "Goose" \
        "9" "Codex CLI" \
        2>&1 1>&3)
    exit_status=$?
    exec 3>&-

    [ "$exit_status" -ne "$DIALOG_OK" ] && return

    # Build server config JSON
    local servers=""
    local sep=""
    for pkg in $BASE_PKGS $AUTH_PKGS; do
        local ver
        ver=$(get_version "$pkg" 2>/dev/null)
        if [ -n "$ver" ] && [ "$pkg" != "qso-graph-auth" ]; then
            local key="${pkg%-mcp}"
            servers="${servers}${sep}    \"${key}\": { \"command\": \"$BIN_DIR/$pkg\" }"
            sep=",\n"
        fi
    done
    if has_ionis; then
        servers="${servers}${sep}    \"ionis\": { \"command\": \"$BIN_DIR/ionis-mcp\" }"
    fi

    local config="{\n  \"mcpServers\": {\n${servers}\n  }\n}"

    $MSGCLIENT --backtitle "$BACKTITLE" \
        --title " MCP Client Config" \
        --msgbox "$config" 20 70
}

do_upgrade() {
    local tier
    tier=$(current_tier)

    local packages="$BASE_PKGS qso-graph-config"
    case "$tier" in
        auth) packages="$BASE_PKGS $AUTH_PKGS qso-graph-config" ;;
        ionis) packages="$BASE_PKGS $IONIS_PKGS qso-graph-config" ;;
        full) packages="$BASE_PKGS $AUTH_PKGS $IONIS_PKGS qso-graph-config" ;;
    esac

    clear
    echo ""
    echo "Checking PyPI for updates ($tier tier)..."
    echo ""
    # shellcheck disable=SC2086
    "$PIP" install --upgrade $packages

    create_wrappers >/dev/null
    update_state "$tier"

    $MSGCLIENT --backtitle "$BACKTITLE" \
        --title " Update Complete" \
        --msgbox "All $tier tier packages updated to latest versions." 8 55
}

do_uninstall() {
    $MSGCLIENT --backtitle "$BACKTITLE" \
        --title " Confirm Uninstall" \
        --yesno "This will remove ~/.qso-graph/ entirely,\nincluding the venv, all servers, and wrappers.\n\nContinue?" 10 55
    [ $? -ne "$DIALOG_OK" ] && return

    clear
    echo ""
    echo "Removing $QSO_GRAPH_HOME..."
    rm -rf "$QSO_GRAPH_HOME"
    echo ""
    echo "Done. QSO-Graph has been removed."
    echo "Remove the PATH line from your .bashrc/.zshrc manually:"
    echo '  export PATH="$HOME/.qso-graph/bin:$PATH"'
    exit 0
}

# ─── Main ───────────────────────────────────────────────────────────────────

main() {
    trap sig_catch_cleanup SIGHUP SIGINT SIGQUIT SIGTERM SIGTSTP

    detect_dialog

    case "${1:-}" in
        --version)
            echo "qso-graph-config $VERSION"
            exit 0 ;;
        --upgrade)
            do_upgrade
            exit 0 ;;
        --no-tui)
            MSGCLIENT="" ;;
        --help|-h)
            echo "qso-graph-config — Manager for QSO-Graph ham radio MCP servers"
            echo ""
            echo "Usage: qso-graph-config [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --version    Show version"
            echo "  --upgrade    Non-interactive upgrade"
            echo "  --no-tui     Force plain text prompts"
            echo "  --help       Show this help"
            exit 0 ;;
    esac

    if [ ! -d "$VENV_DIR" ]; then
        echo "QSO-Graph is not installed."
        echo "Run: curl -sL https://raw.githubusercontent.com/qso-graph/qso-graph-config/main/install.sh | bash"
        exit 1
    fi

    if [ -z "$MSGCLIENT" ]; then
        echo "Neither dialog nor whiptail found."
        echo "Install one of them:"
        echo "  sudo dnf install dialog       (Fedora / RHEL / Rocky)"
        echo "  sudo apt install dialog       (Ubuntu / Debian)"
        exit 1
    fi

    # Main menu loop
    while true; do
        exec 3>&1
        selection=$($MSGCLIENT \
            --backtitle "$BACKTITLE" \
            --title " QSO-Graph Config" \
            --cancel-label "Exit" \
            --menu "Ham radio MCP servers for AI agents." \
            18 55 7 \
            "install"   "Install / Update Servers" \
            "creds"     "Manage Credentials" \
            "data"      "Download Datasets" \
            "status"    "Server Status" \
            "config"    "Configure MCP Client" \
            "update"    "Check for Updates" \
            "uninstall" "Uninstall" \
            2>&1 1>&3)
        exit_status=$?
        exec 3>&-

        case $exit_status in
            $DIALOG_CANCEL)
                clean_exit ;;
            $DIALOG_ESC)
                clean_exit ;;
        esac

        case "$selection" in
            install)   do_install ;;
            creds)     do_credentials ;;
            data)      do_datasets ;;
            status)    do_status ;;
            config)    do_configure ;;
            update)    do_upgrade ;;
            uninstall) do_uninstall ;;
        esac
    done
}

main "$@"
