# QSO-Graph Config

Installer and manager for the [QSO-Graph](https://qso-graph.io) ham radio
MCP server suite — 12 packages, 71 tools, one command.

## Quick Start

```bash
curl -sL https://qso-graph.io/install.sh | bash
```

This creates `~/.qso-graph/` with an isolated Python environment, installs
the base MCP servers, and adds them to your PATH. Works on Linux and macOS.

After install, run `qso-graph-config` to manage servers, credentials,
datasets, and MCP client configuration.

## What Gets Installed

### Base (default — 6 servers, 38 tools)

No accounts, no credentials, no downloads. Just works.

| Server | Tools | What It Does |
|--------|:-----:|--------------:|
| [adif-mcp](https://pypi.org/project/adif-mcp/) | 8 | ADIF 3.1.6 spec — validation, parsing, geospatial |
| [solar-mcp](https://pypi.org/project/solar-mcp/) | 6 | Space weather — SFI, Kp, solar wind, band outlook |
| [pota-mcp](https://pypi.org/project/pota-mcp/) | 6 | Parks on the Air — spots, park info, schedules |
| [sota-mcp](https://pypi.org/project/sota-mcp/) | 4 | Summits on the Air — spots, alerts, summit info |
| [iota-mcp](https://pypi.org/project/iota-mcp/) | 6 | Islands on the Air — group lookup, nearby search |
| [wspr-mcp](https://pypi.org/project/wspr-mcp/) | 8 | WSPR analytics — propagation, beacons, SNR trends |

### Auth (optional — 5 packages, 22 tools)

Logbook services requiring free or paid accounts. Credentials stored in
your OS keyring via `qso-auth` CLI.

| Server | Tools | What It Does |
|--------|:-----:|--------------:|
| [qso-graph-auth](https://pypi.org/project/qso-graph-auth/) | — | OS keyring credential manager |
| [qrz-mcp](https://pypi.org/project/qrz-mcp/) | 5 | QRZ.com — callsign lookup, DXCC, logbook |
| [eqsl-mcp](https://pypi.org/project/eqsl-mcp/) | 5 | eQSL.cc — inbox, verification, AG status |
| [lotw-mcp](https://pypi.org/project/lotw-mcp/) | 5 | LoTW — confirmations, QSOs, DXCC credits |
| [hamqth-mcp](https://pypi.org/project/hamqth-mcp/) | 7 | HamQTH — lookup, DX spots, RBN, bio |

### ionis-mcp (optional — 1 package, 11 tools)

HF propagation analytics from 175M+ signatures. Requires a dataset
download (~430 MB minimal, ~15 GB full).

| Server | Tools | What It Does |
|--------|:-----:|--------------:|
| [ionis-mcp](https://pypi.org/project/ionis-mcp/) | 11 | Band openings, path analysis, solar correlation |

## How It Works

QSO-Graph Config follows the [Conda](https://docs.conda.io/) model:

1. **`install.sh`** bootstraps `~/.qso-graph/` with a Python venv
2. **`qso-graph-config`** (Python) handles all logic — TUI menus, installs,
   upgrades, credential setup, dataset downloads, MCP client config generation
3. Wrapper scripts in `~/.qso-graph/bin/` make all servers available on PATH
4. One PATH entry works on both Linux and macOS

```
~/.qso-graph/
  venv/     Python virtual environment (servers live here)
  bin/      Wrapper scripts (add to PATH)
  etc/      state.json
  log/      Install logs
```

## Usage

```bash
qso-graph-config              # Interactive TUI (dialog/whiptail or numbered prompts)
qso-graph-config --no-tui     # Force plain text prompts
qso-graph-config --upgrade    # Non-interactive upgrade
qso-graph-config --version    # Show version
```

The TUI presents a raspi-config-style menu:

- **Install Servers** — select Base, Auth, ionis-mcp tiers
- **Credentials** — set up service accounts via `qso-auth`
- **Datasets** — download IONIS propagation data
- **Status** — show installed servers and versions
- **Configure Client** — generate config for 9 MCP clients
- **Update** — check PyPI for new versions
- **Uninstall** — remove everything

## MCP Client Configuration

After installation, configure your MCP client to use the servers.
QSO-Graph Config generates config snippets for:

- Claude Desktop
- Claude Code
- VS Code (Copilot)
- Cursor
- Windsurf
- ChatGPT Desktop
- Gemini CLI
- Goose
- Codex CLI

Example for Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "solar": { "command": "/home/you/.qso-graph/bin/solar-mcp" },
    "pota":  { "command": "/home/you/.qso-graph/bin/pota-mcp" },
    "wspr":  { "command": "/home/you/.qso-graph/bin/wspr-mcp" }
  }
}
```

## Advanced: pip Install

For users who manage their own Python environments:

```bash
pip install qso-graph-config                    # Base — 6 servers
pip install "qso-graph-config[auth]"            # + logbook servers
pip install "qso-graph-config[ionis]"           # + ionis-mcp
pip install "qso-graph-config[full]"            # Everything
```

## Requirements

- Python 3.11+ (Linux or macOS)
- `dialog` or `whiptail` for TUI menus (optional — falls back to numbered prompts)

## Windows

Windows users install via the QSO-Graph Installer (.exe) available from
[SourceForge](https://sourceforge.net/projects/qso-graph/). The Windows
installer uses PyInstaller + InnoSetup and does not require Python.

## Links

- **Website**: [qso-graph.io](https://qso-graph.io)
- **Source**: [github.com/qso-graph](https://github.com/qso-graph)
- **Demo**: [qso-graph-demo.vercel.app](https://qso-graph-demo.vercel.app)
- **All servers on PyPI**: [pypi.org/search/?q=qso-graph](https://pypi.org/search/?q=qso-graph)

## License

[GPL-3.0-or-later](LICENSE)
