# kali-vm-setup

One-shot bootstrap for a fresh engagement VM (Kali / Debian, `arm64` or `amd64`).
Installs a working recon toolchain, a sane tmux + zsh setup, and two shell
utilities — in a single idempotent script that runs as **root by default** or as a
normal user with `sudo`.

## Screenshots

**Powerline tmux bar** (`--tmux-theme powerline`) — seamless chevron chain:

![powerline status bar](screenshots/powerline.png)

**Minimal tmux bar** (`--tmux-theme minimal`, default) — flat blocks, no glyphs, font-safe:

![minimal status bar](screenshots/minimal.png)

*Rendered previews; exact appearance depends on your terminal font.*

## Quick start

```bash
scp vm-setup.sh user@vm:~/
ssh user@vm './vm-setup.sh'          # installs everything (default)
```

Run it as root (the default on these images) or as any user with `sudo`. It is
**idempotent** — re-running replaces only its own managed blocks and backs up
`~/.zshrc`, `~/.tmux.conf`, and the nxc config with a timestamp before editing.

## What it installs

| Component | Source | Notes |
|---|---|---|
| `apt` base | apt | tmux, zsh, chromium, curl, ca-certificates |
| `go` | go.dev tarball | latest stable, arch-matched (apt Go is too old for gowitness) |
| `gowitness` | `go install` | web screenshotting; needs Go + chromium |
| `kerbrute` | `go install` | Kerberos pre-auth bruteforcing |
| `bangbang` | GitHub release | CVE / PoC search; arch-gated binary |
| `kerbrutez` | GitHub release | Kerberos tooling; arch-gated (Zig, musl-static) |
| `masscan` | apt | mass port scanner (C, needs root for raw sockets) |
| `netexec` (`nxc`) | apt (Kali) | sets `pwn3d_label = Admin!` |
| `tmuxconf` | writes `~/.tmux.conf` | 1M history, vi mode, mouse, OSC 52 clipboard |
| `tmuxtheme` | writes status bar | Tokyo Night; `minimal` or `powerline` (opt-in) |
| `zshfns` | writes `~/.zshrc` block | `clipboard` / `clip`, `tmux-save` |

Architecture is auto-detected. Release binaries are downloaded only for the
architectures that are actually published, and verified as ELF before install.

## Usage

```
./vm-setup.sh                      # install EVERYTHING (default)
./vm-setup.sh --wizard             # pick components interactively (checklist)
./vm-setup.sh --only go,bangbang   # only these (prerequisites auto-added)
./vm-setup.sh --skip masscan       # everything except these
./vm-setup.sh --tmux-theme [minimal|powerline]   # add ONLY the tmux bar
./vm-setup.sh --list               # show component keys and exit
./vm-setup.sh --new-user pentest   # create a user with passwordless sudo
./vm-setup.sh --current-user       # non-interactive; target the current user
./vm-setup.sh --help
```

Selecting a component pulls in its prerequisites automatically (e.g. `--only
gowitness` also enables `go` and `chromium`), and the script reports what it added.

### New user

`--new-user <name>` creates the account with a `zsh` shell, adds it to `sudo`, and
installs a **passwordless** sudoers drop-in. The rule is validated with `visudo -cf`
in a temp file before it is installed, so a bad entry can never break sudo, and the
username is strictly validated before it touches `/etc/sudoers.d`.

## tmux theme

Two styles, opt-in via `--tmux-theme [style]` (excluded from the default install):

- **`minimal`** (default) — flat colour-block segments, no separator glyphs. Renders
  on any terminal, no special font required.
- **`powerline`** — a solid Tokyo Night bar with a seamless chevron chain: every
  window shows a two-tone `#I`/`#W` banner. Requires a powerline / Nerd Font in the
  terminal you connect from.

## Shell utilities

Added to `~/.zshrc`:

- **`clipboard`** / **`clip`** — pipe stdin to your **local** clipboard over SSH via
  the OSC 52 escape sequence. No daemon, no X forwarding.
  ```bash
  cat loot.txt | clip
  ```
- **`tmux-save`** — dump the scrollback of every tmux pane to one file.
  ```bash
  tmux-save --file ~/engagement-scrollback.txt
  ```

Reload your shell with `exec zsh` after running (sourcing alone cannot replace a
function that is already defined in the running shell).

## Notes

- `masscan` needs root for raw sockets.
- The OSC 52 clipboard and the powerline glyphs render **client-side** — support
  depends on the terminal you connect from, not the VM.
- Everything user-facing is written to the target user's home and owned by them.
