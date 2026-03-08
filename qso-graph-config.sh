#!/bin/bash
#
# qso-graph-config — Manager for QSO-Graph ham radio MCP servers.
#
# Pure bash + dialog TUI. Uses temp file for dialog results.
#
# License: GPL-3.0-or-later
#------------------------------------------------------------------------------#

VERSION="0.1.2"

# ─── Paths ───────────────────────────────────────────────────────────────────

QSO_GRAPH_HOME="$HOME/.qso-graph"
VENV_DIR="$QSO_GRAPH_HOME/venv"
BIN_DIR="$QSO_GRAPH_HOME/bin"
ETC_DIR="$QSO_GRAPH_HOME/etc"
LOG_DIR="$QSO_GRAPH_HOME/log"
STATE_FILE="$ETC_DIR/state.json"
PIP="$VENV_DIR/bin/pip"
TMP="$QSO_GRAPH_HOME/tmp"

BACKTITLE="QSO-Graph Config v${VERSION}"

# ─── Dialog theme ────────────────────────────────────────────────────────────

make_dialogrc() {
    cat > "$ETC_DIR/.dialogrc" <<'EOF_DIALOGRC'
aspect = 0
separate_widget = ""
tab_len = 0
visit_items = ON
use_shadow = ON
use_colors = ON
screen_color = (CYAN,BLUE,ON)
shadow_color = (BLACK,BLACK,ON)
dialog_color = (BLACK,WHITE,OFF)
title_color = (BLUE,WHITE,OFF)
border_color = (WHITE,WHITE,ON)
button_active_color = (WHITE,BLUE,ON)
button_inactive_color = (BLACK,WHITE,OFF)
button_key_active_color = (WHITE,BLUE,ON)
button_key_inactive_color = (RED,WHITE,OFF)
button_label_active_color = (YELLOW,BLUE,ON)
button_label_inactive_color = (BLACK,WHITE,ON)
inputbox_color = (BLACK,WHITE,OFF)
inputbox_border_color = (BLACK,WHITE,OFF)
searchbox_color = (BLACK,WHITE,OFF)
searchbox_title_color = (BLUE,WHITE,OFF)
searchbox_border_color = (WHITE,WHITE,ON)
position_indicator_color = (BLUE,WHITE,ON)
menubox_color = (BLACK,WHITE,OFF)
menubox_border_color = (WHITE,WHITE,ON)
item_color = (BLACK,WHITE,ON)
item_selected_color = (WHITE,BLUE,ON)
tag_color = (BLUE,WHITE,OFF)
tag_selected_color = (YELLOW,BLUE,ON)
tag_key_color = (RED,WHITE,OFF)
tag_key_selected_color = (RED,BLUE,ON)
check_color = (BLACK,WHITE,OFF)
check_selected_color = (WHITE,BLUE,ON)
uarrow_color = (GREEN,WHITE,ON)
darrow_color = (GREEN,WHITE,ON)
itemhelp_color = (WHITE,BLACK,OFF)
form_active_text_color = (WHITE,BLUE,ON)
form_text_color = (WHITE,CYAN,ON)
form_item_readonly_color = (CYAN,WHITE,ON)
gauge_color = (BLUE,WHITE,ON)
EOF_DIALOGRC

    export DIALOGRC="$ETC_DIR/.dialogrc"
}

# ─── Package definitions ────────────────────────────────────────────────────

BASE_PKGS="adif-mcp solar-mcp pota-mcp sota-mcp iota-mcp wspr-mcp"
AUTH_PKGS="qso-graph-auth qrz-mcp eqsl-mcp lotw-mcp hamqth-mcp"
IONIS_PKGS="ionis-mcp"

ENTRY_POINTS="adif-mcp solar-mcp pota-mcp sota-mcp iota-mcp wspr-mcp qso-auth qrz-mcp eqsl-mcp lotw-mcp hamqth-mcp ionis-mcp ionis-download"

# ─── Terminal cleanup ────────────────────────────────────────────────────────

clean_exit() {
    rm -f "$TMP"/*
    stty sane 2>/dev/null || true
    printf '\033[?25h'
    clear
    echo "QSO-Graph Config — clean exit."
    trap - SIGHUP SIGINT SIGQUIT SIGTERM SIGTSTP
    exit 0
}

sig_catch_cleanup() {
    rm -f "$TMP"/*
    stty sane 2>/dev/null || true
    printf '\033[?25h'
    clear
    echo "Signal caught, performing cleanup."
    trap - SIGHUP SIGINT SIGQUIT SIGTERM SIGTSTP
    exit 1
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

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
        cat > "$BIN_DIR/$name" <<WRAPPER
#!/bin/sh
exec $venv_path "\$@"
WRAPPER
        chmod 755 "$BIN_DIR/$name"
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

    dialog --backtitle "$BACKTITLE" \
        --title " Install Components" \
        --checklist "Select components to install. Base is always included." \
        14 65 3 \
        "base"  "Base — 6 public servers (38 tools)"              "ON" \
        "auth"  "Auth — 4 logbook servers + qso-auth (22 tools)"  "$auth_default" \
        "ionis" "ionis-mcp — HF propagation analytics (11 tools)" "$ionis_default" \
        2> "$TMP/selection"
    rc=$?
    [ $rc -ne 0 ] && return

    selection=$(cat "$TMP/selection" | tr -d '"')

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

    dialog --backtitle "$BACKTITLE" \
        --title " Install Complete" \
        --msgbox "Installed successfully.\n\n$count commands in ~/.qso-graph/bin/" 10 55
}

do_credentials() {
    if ! has_auth; then
        dialog --backtitle "$BACKTITLE" \
            --title " Not Installed" \
            --msgbox "Auth servers are not installed.\n\nInstall them first via Install Servers." 10 55
        return
    fi

    local qso_auth="$VENV_DIR/bin/qso-auth"
    if [ ! -f "$qso_auth" ]; then
        dialog --backtitle "$BACKTITLE" \
            --title " Error" --msgbox "qso-auth CLI not found." 7 40
        return
    fi

    while true; do
        dialog --backtitle "$BACKTITLE" \
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
            2> "$TMP/selection"
        rc=$?
        [ $rc -ne 0 ] && return

        selection=$(cat "$TMP/selection")
        [ "$selection" = "back" ] && return

        clear
        case "$selection" in
            persona)
                # Collect persona fields via dialog
                dialog --backtitle "$BACKTITLE" \
                    --title " Create Persona" \
                    --form "Enter persona details:" 14 55 4 \
                    "Name:"     1 1 "" 1 14 30 30 \
                    "Callsign:" 2 1 "" 2 14 12 12 \
                    "Start:"    3 1 "" 3 14 12 10 \
                    "End:"      4 1 "" 4 14 12 10 \
                    2> "$TMP/selection"
                rc=$?
                [ $rc -ne 0 ] && continue

                local p_name p_call p_start p_end
                p_name=$(sed -n '1p' "$TMP/selection")
                p_call=$(sed -n '2p' "$TMP/selection")
                p_start=$(sed -n '3p' "$TMP/selection")
                p_end=$(sed -n '4p' "$TMP/selection")

                if [ -z "$p_name" ] || [ -z "$p_call" ] || [ -z "$p_start" ]; then
                    dialog --backtitle "$BACKTITLE" \
                        --title " Error" \
                        --msgbox "Name, Callsign, and Start date are required." 7 50
                    continue
                fi

                # Ask which providers to enable
                dialog --backtitle "$BACKTITLE" \
                    --title " Enable Providers" \
                    --checklist "Select logbook services for this persona:" \
                    14 55 5 \
                    "eqsl"        "eQSL.cc"    "ON" \
                    "qrz"         "QRZ.com"    "ON" \
                    "qrz_logbook" "QRZ Logbook" "OFF" \
                    "lotw"        "LoTW"       "ON" \
                    "hamqth"      "HamQTH"     "ON" \
                    2> "$TMP/selection"
                rc=$?
                [ $rc -ne 0 ] && continue
                local providers
                providers=$(cat "$TMP/selection" | tr -d '"')

                local cmd="$qso_auth persona add --name $p_name --callsign $p_call --start $p_start"
                [ -n "$p_end" ] && cmd="$cmd --end $p_end"
                [ -n "$providers" ] && cmd="$cmd --providers $providers"

                clear
                $cmd
                rc=$?
                if [ $rc -ne 0 ]; then
                    echo ""
                    echo "Persona creation failed (exit code $rc)."
                    echo "If on a server (no desktop), install a headless keyring:"
                    echo "  ~/.qso-graph/venv/bin/pip install keyrings.alt"
                    echo ""
                fi
                read -rp "Press Enter to continue..."
                ;;
            doctor)
                "$qso_auth" creds doctor
                read -rp "Press Enter to continue..."
                ;;
            eqsl|lotw|hamqth)
                # Username + password providers
                local persona
                persona=$("$qso_auth" persona list 2>/dev/null | head -1 | awk '{print $1}')
                if [ -z "$persona" ]; then
                    dialog --backtitle "$BACKTITLE" \
                        --title " No Persona" \
                        --msgbox "Create a persona first." 7 40
                    continue
                fi

                dialog --backtitle "$BACKTITLE" \
                    --title " ${selection^^} — Username" \
                    --inputbox "Enter your ${selection} username:" 8 50 \
                    2> "$TMP/selection"
                rc=$?
                [ $rc -ne 0 ] && continue
                local cred_user
                cred_user=$(cat "$TMP/selection")
                [ -z "$cred_user" ] && continue

                dialog --backtitle "$BACKTITLE" \
                    --title " ${selection^^} — Password" \
                    --insecure --passwordbox "Enter your ${selection} password:" 8 50 \
                    2> "$TMP/selection"
                rc=$?
                [ $rc -ne 0 ] && continue
                local cred_pass
                cred_pass=$(cat "$TMP/selection")
                [ -z "$cred_pass" ] && continue

                clear
                "$qso_auth" creds set "$persona" "$selection" \
                    --username "$cred_user" --password "$cred_pass"
                read -rp "Press Enter to continue..."
                ;;
            qrz)
                # Username + API key provider
                local persona
                persona=$("$qso_auth" persona list 2>/dev/null | head -1 | awk '{print $1}')
                if [ -z "$persona" ]; then
                    dialog --backtitle "$BACKTITLE" \
                        --title " No Persona" \
                        --msgbox "Create a persona first." 7 40
                    continue
                fi

                dialog --backtitle "$BACKTITLE" \
                    --title " QRZ — Username" \
                    --inputbox "Enter your QRZ.com username:" 8 50 \
                    2> "$TMP/selection"
                rc=$?
                [ $rc -ne 0 ] && continue
                local cred_user
                cred_user=$(cat "$TMP/selection")
                [ -z "$cred_user" ] && continue

                dialog --backtitle "$BACKTITLE" \
                    --title " QRZ — API Key" \
                    --insecure --passwordbox "Enter your QRZ.com API key:" 8 50 \
                    2> "$TMP/selection"
                rc=$?
                [ $rc -ne 0 ] && continue
                local cred_key
                cred_key=$(cat "$TMP/selection")
                [ -z "$cred_key" ] && continue

                clear
                "$qso_auth" creds set "$persona" qrz \
                    --username "$cred_user" --api-key "$cred_key"
                read -rp "Press Enter to continue..."
                ;;
        esac
    done
}

do_datasets() {
    if ! has_ionis; then
        dialog --backtitle "$BACKTITLE" \
            --title " Not Installed" \
            --msgbox "ionis-mcp is not installed.\n\nInstall it first via Install Servers." 10 55
        return
    fi

    local ionis_dl="$VENV_DIR/bin/ionis-download"
    if [ ! -f "$ionis_dl" ]; then
        dialog --backtitle "$BACKTITLE" \
            --title " Error" --msgbox "ionis-download CLI not found." 7 40
        return
    fi

    dialog --backtitle "$BACKTITLE" \
        --title " Download Datasets" \
        --radiolist "Select a dataset bundle for ionis-mcp." \
        14 65 3 \
        "minimal"     "Contest + grids + solar (~430 MB)"             "ON" \
        "recommended" "Minimal + PSKR + DSCOVR + balloons (~1.1 GB)" "OFF" \
        "full"        "All 9 datasets (~15 GB)"                       "OFF" \
        2> "$TMP/selection"
    rc=$?
    [ $rc -ne 0 ] && return

    selection=$(cat "$TMP/selection" | tr -d '"')

    if [ "$selection" = "full" ]; then
        dialog --backtitle "$BACKTITLE" \
            --title " Confirm" \
            --yesno "The full dataset is ~15 GB. Continue?" 7 45
        [ $? -ne 0 ] && return
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

    dialog --backtitle "$BACKTITLE" \
        --title " Server Status" \
        --msgbox "$lines" $((count + 10)) 55
}

do_configure() {
    dialog --backtitle "$BACKTITLE" \
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
        2> "$TMP/selection"
    rc=$?
    [ $rc -ne 0 ] && return

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

    dialog --backtitle "$BACKTITLE" \
        --title " MCP Client Config" --msgbox "$config" 20 70
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

    dialog --backtitle "$BACKTITLE" \
        --title " Update Complete" \
        --msgbox "All $tier tier packages updated to latest versions." 7 55
}

do_uninstall() {
    dialog --backtitle "$BACKTITLE" \
        --title " Confirm Uninstall" \
        --yesno "Remove ~/.qso-graph/ entirely?\n\nThis deletes the venv, all servers, and wrappers." 9 55
    [ $? -ne 0 ] && return

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
    # Handle flags first (no dialog needed)
    case "${1:-}" in
        --version) echo "qso-graph-config $VERSION"; exit 0 ;;
        --help|-h)
            echo "qso-graph-config — Manager for QSO-Graph ham radio MCP servers"
            echo ""
            echo "Usage: qso-graph-config [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --version    Show version"
            echo "  --upgrade    Non-interactive upgrade"
            echo "  --help       Show this help"
            exit 0 ;;
    esac

    # Check requirements
    if [ ! -d "$VENV_DIR" ]; then
        echo "QSO-Graph is not installed."
        echo "Run: curl -sL https://raw.githubusercontent.com/qso-graph/qso-graph-config/main/install.sh | bash"
        exit 1
    fi

    if ! command -v dialog >/dev/null 2>&1; then
        echo "dialog is required but not installed."
        echo "  sudo dnf install dialog       (Fedora / RHEL / Rocky)"
        echo "  sudo apt install dialog       (Ubuntu / Debian)"
        exit 1
    fi

    # Setup
    trap sig_catch_cleanup SIGHUP SIGINT SIGQUIT SIGTERM SIGTSTP
    mkdir -p "$TMP"
    make_dialogrc

    # Non-interactive upgrade
    if [ "${1:-}" = "--upgrade" ]; then
        do_upgrade
        clean_exit
    fi

    # Main menu loop
    while true; do
        dialog --backtitle "$BACKTITLE" \
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
            2> "$TMP/selection"
        rc=$?
        [ $rc -ne 0 ] && clean_exit

        selection=$(cat "$TMP/selection")

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
