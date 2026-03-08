"""QSO-Graph Config — interactive installer and manager for ham radio MCP servers.

Uses dialog/whiptail for TUI menus (raspi-config style).
Falls back to simple numbered prompts with --no-tui or when
neither dialog nor whiptail is available.

All state lives under ~/.qso-graph/:
  venv/     Python virtual environment (servers installed here)
  bin/      Wrapper scripts (user adds to PATH)
  etc/      state.json (tier choice, timestamps, python_path)
  log/      Install/upgrade logs
"""

import importlib.metadata
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

__all__ = ["main"]

VERSION = importlib.metadata.version("qso-graph-config")

# --- Paths ---

QSO_GRAPH_HOME = os.path.expanduser("~/.qso-graph")
VENV_DIR = os.path.join(QSO_GRAPH_HOME, "venv")
BIN_DIR = os.path.join(QSO_GRAPH_HOME, "bin")
ETC_DIR = os.path.join(QSO_GRAPH_HOME, "etc")
LOG_DIR = os.path.join(QSO_GRAPH_HOME, "log")
STATE_FILE = os.path.join(ETC_DIR, "state.json")

# --- Component definitions ---

BASE_PACKAGES = [
    ("adif-mcp", "ADIF 3.1.6 spec engine (8 tools)"),
    ("solar-mcp", "Space weather + band outlook (6 tools)"),
    ("pota-mcp", "Parks on the Air (6 tools)"),
    ("sota-mcp", "Summits on the Air (4 tools)"),
    ("iota-mcp", "Islands on the Air (6 tools)"),
    ("wspr-mcp", "WSPR beacon analytics (8 tools)"),
]

AUTH_PACKAGES = [
    ("qso-graph-auth", "OS keyring credential manager"),
    ("qrz-mcp", "QRZ.com lookup + logbook (5 tools)"),
    ("eqsl-mcp", "eQSL.cc integration (5 tools)"),
    ("lotw-mcp", "LoTW integration (5 tools)"),
    ("hamqth-mcp", "HamQTH.com integration (7 tools)"),
]

IONIS_PACKAGES = [
    ("ionis-mcp", "HF propagation analytics (11 tools)"),
]

# All possible server entry points (binaries in venv/bin/)
ENTRY_POINTS = [
    "qso-graph-config",
    "adif-mcp", "solar-mcp", "pota-mcp", "sota-mcp", "iota-mcp",
    "wspr-mcp", "qso-auth", "qrz-mcp", "eqsl-mcp", "lotw-mcp",
    "hamqth-mcp", "ionis-mcp", "ionis-download",
]

AUTH_PROVIDERS = ["eqsl", "qrz", "lotw", "hamqth"]

DATASET_BUNDLES = {
    "minimal": {
        "desc": "Contest + grids + solar (~430 MB)",
        "datasets": "contest, grids, solar",
    },
    "recommended": {
        "desc": "Minimal + PSKR + DSCOVR + balloons (~1.1 GB)",
        "datasets": "contest, pskr, grids, solar, dscovr, balloons",
    },
    "full": {
        "desc": "All 9 datasets (~15 GB)",
        "datasets": "wspr, rbn, contest, dxpedition, pskr, solar, dscovr, grids, balloons",
    },
}

MCP_CLIENTS = {
    "Claude Desktop": {
        "path_mac": "~/Library/Application Support/Claude/claude_desktop_config.json",
        "path_linux": "~/.config/claude/claude_desktop_config.json",
        "path_win": "%APPDATA%\\Claude\\claude_desktop_config.json",
    },
    "Claude Code": {
        "path_mac": "~/.claude.json",
        "path_linux": "~/.claude.json",
    },
    "VS Code (Copilot)": {
        "path_mac": ".vscode/mcp.json",
        "path_linux": ".vscode/mcp.json",
    },
    "Cursor": {
        "path_mac": ".cursor/mcp.json",
        "path_linux": ".cursor/mcp.json",
    },
    "Windsurf": {
        "path_mac": "~/.windsurf/mcp.json",
        "path_linux": "~/.windsurf/mcp.json",
    },
    "ChatGPT Desktop": {
        "path_mac": "~/Library/Application Support/com.openai.chat/mcp.json",
        "path_linux": "~/.config/chatgpt/mcp.json",
    },
    "Gemini CLI": {
        "path_mac": "~/.gemini/settings.json",
        "path_linux": "~/.gemini/settings.json",
    },
    "Goose": {
        "path_mac": "~/.config/goose/config.yaml",
        "path_linux": "~/.config/goose/config.yaml",
    },
    "Codex CLI": {
        "path_mac": "~/.codex/config.json",
        "path_linux": "~/.codex/config.json",
    },
}


# ─── TUI Backend ─────────────────────────────────────────────────────────────

class TUI:
    """Dialog/whiptail TUI backend."""

    def __init__(self):
        self.cmd = shutil.which("dialog") or shutil.which("whiptail")
        if not self.cmd:
            raise RuntimeError("Neither dialog nor whiptail found")
        self.is_dialog = os.path.basename(self.cmd) == "dialog"

    def msgbox(self, title: str, text: str, height: int = 12, width: int = 60):
        subprocess.run(
            [self.cmd, "--title", title, "--msgbox", text, str(height), str(width)]
        )

    def menu(self, title: str, text: str, choices: list[tuple[str, str]],
             height: int = 20, width: int = 60, menu_height: int = 10) -> str | None:
        args = [self.cmd, "--title", title, "--menu", text,
                str(height), str(width), str(menu_height)]
        for tag, desc in choices:
            args.extend([tag, desc])
        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode != 0:
            return None
        return result.stderr.strip()

    def checklist(self, title: str, text: str,
                  choices: list[tuple[str, str, bool]],
                  height: int = 20, width: int = 60,
                  list_height: int = 10) -> list[str] | None:
        args = [self.cmd, "--title", title, "--checklist", text,
                str(height), str(width), str(list_height)]
        for tag, desc, on in choices:
            args.extend([tag, desc, "ON" if on else "OFF"])
        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode != 0:
            return None
        selected = result.stderr.strip()
        if not selected:
            return []
        return selected.replace('"', '').split()

    def radiolist(self, title: str, text: str,
                  choices: list[tuple[str, str, bool]],
                  height: int = 20, width: int = 60,
                  list_height: int = 10) -> str | None:
        args = [self.cmd, "--title", title, "--radiolist", text,
                str(height), str(width), str(list_height)]
        for tag, desc, on in choices:
            args.extend([tag, desc, "ON" if on else "OFF"])
        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode != 0:
            return None
        return result.stderr.strip().replace('"', '')

    def yesno(self, title: str, text: str, height: int = 8, width: int = 60) -> bool:
        result = subprocess.run(
            [self.cmd, "--title", title, "--yesno", text, str(height), str(width)]
        )
        return result.returncode == 0

    def infobox(self, title: str, text: str, height: int = 6, width: int = 50):
        subprocess.run(
            [self.cmd, "--title", title, "--infobox", text, str(height), str(width)]
        )


# ─── Plain Text Backend (--no-tui or no dialog/whiptail) ─────────────────────

class PlainTUI:
    """Simple numbered-prompt fallback for SSH or missing dialog."""

    def msgbox(self, title: str, text: str, **_):
        print(f"\n=== {title} ===")
        print(text)
        input("\nPress Enter to continue...")

    def menu(self, title: str, text: str, choices: list[tuple[str, str]], **_) -> str | None:
        print(f"\n=== {title} ===")
        print(text)
        print()
        for i, (tag, desc) in enumerate(choices, 1):
            print(f"  {i}. {desc}")
        print(f"  0. Cancel")
        try:
            pick = input(f"\nEnter choice [0-{len(choices)}]: ").strip()
            if pick == "0" or not pick:
                return None
            idx = int(pick) - 1
            if 0 <= idx < len(choices):
                return choices[idx][0]
        except (ValueError, EOFError):
            pass
        return None

    def checklist(self, title: str, text: str,
                  choices: list[tuple[str, str, bool]], **_) -> list[str] | None:
        print(f"\n=== {title} ===")
        print(text)
        print()
        for i, (tag, desc, on) in enumerate(choices, 1):
            mark = "X" if on else " "
            print(f"  {i}. [{mark}] {desc}")
        print()
        print("Enter numbers to toggle (e.g. '2 3'), or press Enter to accept defaults.")
        try:
            picks = input("Toggle: ").strip()
        except EOFError:
            return None
        selected = [tag for tag, _, on in choices if on]
        if picks:
            for p in picks.split():
                try:
                    idx = int(p) - 1
                    tag = choices[idx][0]
                    if tag in selected:
                        selected.remove(tag)
                    else:
                        selected.append(tag)
                except (ValueError, IndexError):
                    pass
        return selected

    def radiolist(self, title: str, text: str,
                  choices: list[tuple[str, str, bool]], **_) -> str | None:
        print(f"\n=== {title} ===")
        print(text)
        print()
        for i, (tag, desc, on) in enumerate(choices, 1):
            mark = "*" if on else " "
            print(f"  {i}. ({mark}) {desc}")
        try:
            pick = input(f"\nEnter choice [1-{len(choices)}]: ").strip()
            idx = int(pick) - 1
            if 0 <= idx < len(choices):
                return choices[idx][0]
        except (ValueError, EOFError):
            pass
        return None

    def yesno(self, title: str, text: str, **_) -> bool:
        print(f"\n=== {title} ===")
        print(text)
        try:
            answer = input("\n[y/N]: ").strip().lower()
            return answer in ("y", "yes")
        except EOFError:
            return False

    def infobox(self, title: str, text: str, **_):
        print(f"\n=== {title} ===")
        print(text)


# ─── State management ────────────────────────────────────────────────────────

def _load_state() -> dict:
    """Load state from ~/.qso-graph/etc/state.json."""
    if os.path.isfile(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}


def _save_state(state: dict):
    """Save state to ~/.qso-graph/etc/state.json."""
    os.makedirs(ETC_DIR, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)
        f.write("\n")


def _update_state(tier: str):
    """Update state after install/upgrade."""
    state = _load_state()
    now = datetime.now(timezone.utc).isoformat()
    if "installed_at" not in state:
        state["installed_at"] = now
    state["tier"] = tier
    state["last_upgrade"] = now
    # python_path is set by install.sh (system Python, not venv Python).
    # Only set it here if install.sh didn't (manual pip install case).
    if "python_path" not in state:
        state["python_path"] = sys.executable
    _save_state(state)


# ─── Package helpers ──────────────────────────────────────────────────────────

def _is_installed(package: str) -> str | None:
    """Return installed version or None."""
    try:
        return importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
        return None


def _venv_bin_dir() -> str:
    """Return the venv bin directory inside ~/.qso-graph/."""
    return os.path.join(VENV_DIR, "bin")


def _pip_install(packages: list[str]):
    """Install packages into the ~/.qso-graph/venv."""
    pip = os.path.join(_venv_bin_dir(), "pip")
    subprocess.run(
        [pip, "install", "--quiet", "--upgrade"] + packages,
        check=True,
    )


def _create_wrappers():
    """Create shell wrapper scripts in ~/.qso-graph/bin/ for all installed servers.

    Each wrapper execs into the venv binary so MCP clients can find
    servers on PATH via ~/.qso-graph/bin.
    """
    venv_bin = _venv_bin_dir()
    os.makedirs(BIN_DIR, exist_ok=True)

    created = []
    for name in ENTRY_POINTS:
        venv_path = os.path.join(venv_bin, name)
        if not os.path.isfile(venv_path):
            continue

        wrapper_path = os.path.join(BIN_DIR, name)
        wrapper_content = f"#!/bin/sh\nexec {venv_path} \"$@\"\n"

        with open(wrapper_path, "w") as f:
            f.write(wrapper_content)
        os.chmod(wrapper_path, 0o755)
        created.append(name)

    return created


def _remove_wrappers():
    """Remove wrapper scripts from ~/.qso-graph/bin/."""
    venv_bin = _venv_bin_dir()

    for name in ENTRY_POINTS:
        wrapper_path = os.path.join(BIN_DIR, name)
        if not os.path.isfile(wrapper_path):
            continue
        # Only remove if it points to our venv
        try:
            with open(wrapper_path) as f:
                content = f.read()
            if venv_bin in content:
                os.unlink(wrapper_path)
        except OSError:
            pass


def _installed_servers() -> list[tuple[str, str]]:
    """Return list of (name, version) for installed MCP servers."""
    all_pkgs = BASE_PACKAGES + AUTH_PACKAGES + IONIS_PACKAGES
    installed = []
    for name, _ in all_pkgs:
        ver = _is_installed(name)
        if ver:
            installed.append((name, ver))
    return installed


def _has_auth() -> bool:
    return _is_installed("qso-graph-auth") is not None


def _has_ionis() -> bool:
    return _is_installed("ionis-mcp") is not None


def _current_tier() -> str:
    """Determine current install tier from installed packages."""
    if _has_ionis() and _has_auth():
        return "full"
    if _has_ionis():
        return "ionis"
    if _has_auth():
        return "auth"
    return "base"


# ─── Menu Actions ─────────────────────────────────────────────────────────────

def do_install(tui):
    """Install/update server components."""
    choices = [
        ("base", "Base — 6 public servers (38 tools)", True),
        ("auth", "Auth — 4 logbook servers + qso-auth (22 tools)", _has_auth()),
        ("ionis", "ionis-mcp — HF propagation analytics (11 tools)", _has_ionis()),
    ]
    selected = tui.checklist(
        "Install Components",
        "Select components to install. Base is always included.",
        choices, height=14, width=65, list_height=5,
    )
    if selected is None:
        return

    # Base is always installed
    packages = [p for p, _ in BASE_PACKAGES]

    if "auth" in selected:
        packages += [p for p, _ in AUTH_PACKAGES]
    if "ionis" in selected:
        packages += [p for p, _ in IONIS_PACKAGES]

    tui.infobox("Installing", f"Installing {len(packages)} packages from PyPI...")

    try:
        _pip_install(packages)
        created = _create_wrappers()

        # Determine tier and save state
        tier = "base"
        if "auth" in selected and "ionis" in selected:
            tier = "full"
        elif "auth" in selected:
            tier = "auth"
        elif "ionis" in selected:
            tier = "ionis"
        _update_state(tier)

        msg = f"Installed {len(packages)} packages successfully."
        msg += f"\n\n{len(created)} commands available in ~/.qso-graph/bin/"
        if "auth" in selected:
            msg += "\n\nNext: set up credentials via Manage Credentials menu."
        if "ionis" in selected:
            msg += "\n\nNext: download datasets via Download Datasets menu."
        tui.msgbox("Install Complete", msg, height=14)
    except subprocess.CalledProcessError:
        tui.msgbox("Install Failed", "pip install failed. Check your network connection.")


def do_credentials(tui):
    """Manage credentials for authenticated servers."""
    if not _has_auth():
        tui.msgbox("Not Installed",
                    "Auth servers are not installed.\n\n"
                    "Install them first via Install / Update Servers.")
        return

    qso_auth = os.path.join(BIN_DIR, "qso-auth")
    if not os.path.isfile(qso_auth):
        qso_auth = os.path.join(_venv_bin_dir(), "qso-auth")
    if not os.path.isfile(qso_auth):
        tui.msgbox("Error", "qso-auth CLI not found.")
        return

    while True:
        choice = tui.menu(
            "Manage Credentials",
            "Set up credentials for logbook services.",
            [
                ("persona", "Create / manage persona"),
                ("eqsl", "Set eQSL.cc credentials"),
                ("qrz", "Set QRZ.com credentials"),
                ("lotw", "Set LoTW credentials"),
                ("hamqth", "Set HamQTH credentials"),
                ("doctor", "Verify all credentials"),
                ("back", "Back to main menu"),
            ],
            height=16, width=55, menu_height=7,
        )
        if choice is None or choice == "back":
            return

        if choice == "persona":
            subprocess.run([qso_auth, "persona", "add"])
        elif choice == "doctor":
            subprocess.run([qso_auth, "creds", "doctor"])
            input("\nPress Enter to continue...")
        else:
            # Determine persona name
            try:
                result = subprocess.run(
                    [qso_auth, "persona", "list"],
                    capture_output=True, text=True,
                )
                lines = [l.strip() for l in result.stdout.strip().split("\n") if l.strip()]
                if not lines:
                    tui.msgbox("No Persona",
                               "No persona configured yet.\n\n"
                               "Create one first via 'Create / manage persona'.")
                    continue
                if len(lines) == 1:
                    persona = lines[0].split()[0]
                else:
                    persona_choices = [(l.split()[0], l, False) for l in lines]
                    persona_choices[0] = (persona_choices[0][0], persona_choices[0][1], True)
                    persona = tui.radiolist("Select Persona", "Which persona?",
                                           persona_choices, height=12, width=50, list_height=5)
                    if not persona:
                        continue
            except Exception:
                persona = "default"

            subprocess.run([qso_auth, "creds", "set", persona, choice])


def do_datasets(tui):
    """Download datasets for ionis-mcp."""
    if not _has_ionis():
        tui.msgbox("Not Installed",
                    "ionis-mcp is not installed.\n\n"
                    "Install it first via Install / Update Servers.")
        return

    ionis_dl = os.path.join(BIN_DIR, "ionis-download")
    if not os.path.isfile(ionis_dl):
        ionis_dl = os.path.join(_venv_bin_dir(), "ionis-download")
    if not os.path.isfile(ionis_dl):
        tui.msgbox("Error", "ionis-download CLI not found.")
        return

    choice = tui.radiolist(
        "Download Datasets",
        "Select a dataset bundle for ionis-mcp.\n"
        "Minimal is required. Recommended and Full are upgrades.",
        [
            ("minimal", "Contest + grids + solar (~430 MB)", True),
            ("recommended", "Minimal + PSKR + DSCOVR + balloons (~1.1 GB)", False),
            ("full", "All 9 datasets (~15 GB)", False),
        ],
        height=14, width=65, list_height=5,
    )
    if not choice:
        return

    if choice == "full":
        if not tui.yesno("Confirm Download",
                         "The full dataset is approximately 15 GB.\n\n"
                         "This may take a while. Continue?"):
            return

    tui.infobox("Downloading", f"Downloading {choice} dataset bundle...")
    subprocess.run([ionis_dl, "--bundle", choice])
    input("\nPress Enter to continue...")


def do_status(tui):
    """Show installed server status."""
    installed = _installed_servers()
    if not installed:
        tui.msgbox("Server Status", "No MCP servers installed.")
        return

    lines = ["Installed MCP servers:\n"]
    for name, ver in installed:
        lines.append(f"  {name:20s}  v{ver}")

    lines.append(f"\n{len(installed)} packages installed.")
    lines.append(f"Tier: {_current_tier()}")
    lines.append(f"Home: {QSO_GRAPH_HOME}")

    # Check for ionis-mcp datasets
    if _has_ionis():
        data_dir = os.environ.get("IONIS_DATA_DIR", "")
        if data_dir and os.path.isdir(data_dir):
            lines.append(f"Datasets: {data_dir}")
        else:
            lines.append("Datasets: not configured (set IONIS_DATA_DIR)")

    tui.msgbox("Server Status", "\n".join(lines), height=max(14, len(installed) + 10))


def do_configure(tui):
    """Show MCP client configuration snippets."""
    client_names = list(MCP_CLIENTS.keys())
    choices = [(str(i + 1), name) for i, name in enumerate(client_names)]
    choices.append(("0", "Back to main menu"))

    choice = tui.menu(
        "Configure MCP Client",
        "Select your MCP client to see the config snippet.",
        choices, height=18, width=55, menu_height=len(choices),
    )
    if choice is None or choice == "0":
        return

    idx = int(choice) - 1
    client_name = client_names[idx]
    client = MCP_CLIENTS[client_name]

    # Build server config — point to ~/.qso-graph/bin/ wrappers
    servers = {}
    for name, _ in BASE_PACKAGES:
        if _is_installed(name):
            server_key = name.replace("-mcp", "")
            cmd_path = os.path.join(BIN_DIR, name)
            servers[server_key] = {"command": cmd_path}
    for name, _ in AUTH_PACKAGES:
        if _is_installed(name) and name != "qso-graph-auth":
            server_key = name.replace("-mcp", "")
            cmd_path = os.path.join(BIN_DIR, name)
            servers[server_key] = {"command": cmd_path}
    if _has_ionis():
        cmd_path = os.path.join(BIN_DIR, "ionis-mcp")
        servers["ionis"] = {"command": cmd_path}

    config = json.dumps({"mcpServers": servers}, indent=2)

    is_linux = sys.platform.startswith("linux")
    path_key = "path_linux" if is_linux else "path_mac"
    config_path = client.get(path_key, client.get("path_linux", ""))

    msg = f"Config for {client_name}:\n\nFile: {config_path}\n\n{config}"
    tui.msgbox(f"Config — {client_name}", msg, height=max(16, len(config.split("\n")) + 8),
               width=70)


def do_upgrade(tui):
    """Check for and install updates."""
    state = _load_state()
    tier = state.get("tier", _current_tier())

    packages = [p for p, _ in BASE_PACKAGES]
    packages.append("qso-graph-config")
    if tier in ("auth", "full"):
        packages += [p for p, _ in AUTH_PACKAGES]
    if tier in ("ionis", "full"):
        packages += [p for p, _ in IONIS_PACKAGES]

    tui.infobox("Updating", f"Checking PyPI for updates ({tier} tier)...")

    try:
        _pip_install(packages)
        _create_wrappers()
        _update_state(tier)
        tui.msgbox("Update Complete", f"All {tier} tier packages updated to latest versions.")
    except subprocess.CalledProcessError:
        tui.msgbox("Update Failed", "pip upgrade failed. Check your network connection.")


def do_uninstall(tui):
    """Uninstall everything."""
    if not tui.yesno("Confirm Uninstall",
                     "This will remove ~/.qso-graph/ entirely,\n"
                     "including the venv, all servers, and wrappers.\n\n"
                     "Continue?"):
        return

    _remove_wrappers()

    print(f"\nRemoving {QSO_GRAPH_HOME}...")
    shutil.rmtree(QSO_GRAPH_HOME, ignore_errors=True)

    print("Done. QSO-Graph has been removed.")
    print("Remove the PATH line from your .bashrc/.zshrc manually:")
    print(f'  export PATH="$HOME/.qso-graph/bin:$PATH"')
    sys.exit(0)


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    import argparse

    parser = argparse.ArgumentParser(
        prog="qso-graph-config",
        description="QSO-Graph — installer and manager for ham radio MCP servers",
    )
    parser.add_argument("--version", action="version", version=f"qso-graph-config {VERSION}")
    parser.add_argument("--no-tui", action="store_true",
                        help="Use plain text prompts instead of dialog/whiptail")
    parser.add_argument("--upgrade", action="store_true",
                        help="Non-interactive upgrade of all installed packages")
    args = parser.parse_args()

    # Non-interactive upgrade
    if args.upgrade:
        tui = PlainTUI()
        do_upgrade(tui)
        return

    # Select TUI backend
    if args.no_tui:
        tui = PlainTUI()
    else:
        try:
            tui = TUI()
        except RuntimeError:
            tui = PlainTUI()

    # First-run detection: if only base is installed and no auth/ionis,
    # go straight to the install checklist
    if not _has_auth() and not _has_ionis():
        first_run = len(_installed_servers()) <= len(BASE_PACKAGES)
        if first_run:
            do_install(tui)

    # Main menu loop
    while True:
        choice = tui.menu(
            f"QSO-Graph Config v{VERSION}",
            "Ham radio MCP servers for AI agents.",
            [
                ("install", "Install / Update Servers"),
                ("creds", "Manage Credentials"),
                ("data", "Download Datasets"),
                ("status", "Server Status"),
                ("config", "Configure MCP Client"),
                ("update", "Check for Updates"),
                ("uninstall", "Uninstall"),
            ],
            height=18, width=55, menu_height=7,
        )

        if choice is None:
            break
        elif choice == "install":
            do_install(tui)
        elif choice == "creds":
            do_credentials(tui)
        elif choice == "data":
            do_datasets(tui)
        elif choice == "status":
            do_status(tui)
        elif choice == "config":
            do_configure(tui)
        elif choice == "update":
            do_upgrade(tui)
        elif choice == "uninstall":
            do_uninstall(tui)
