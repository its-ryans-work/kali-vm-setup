# kali-vm-setup

Bootstrap a fresh Kali / Debian VM (arm64 or amd64) in one command.

## `clip` — copy over SSH

The reason this exists. Pipe anything to your **local** clipboard from a remote box, over OSC 52 — no X forwarding, no daemon, no remote clipboard tool. Works inside tmux too.

```bash
cat creds.txt | clip
nxc smb 10.0.0.0/24 | clip
```

## Also sets up

- **Recon tools** — gowitness, kerbrute, bangbang, kerbrutez, masscan, netexec
- **Go toolchain** — current build from go.dev
- **`tmux-save`** — dump every tmux pane's scrollback to one file
- **tmux** — 1M scrollback, vi copy mode, mouse, OSC 52 clipboard
- **tmux theme** (optional) — Tokyo Night, `minimal` or `powerline`
- **zsh** as the default shell, with the utilities above and a two-line Kali prompt (date + `user㉿host`)
- **nxc** — `Pwn3d!` → `Admin!`

## Install

```bash
scp vm-setup.sh user@vm:~/
ssh user@vm './vm-setup.sh'
```

Runs as root or any sudo user. Idempotent; backs up dotfiles before editing.

## Options

```
--wizard                  pick components interactively
--only go,bangbang        just these (+ deps)
--skip masscan            everything except these
--tmux-theme powerline    add the tmux bar (minimal | powerline)
--new-user pentest        create a user with passwordless sudo
--list                    list components
```

## tmux theme

Optional Tokyo Night status bar — `minimal` (default, works on any terminal) or `powerline` (chevron chain, needs a Nerd Font):

![powerline tmux bar](screenshots/powerline.png)
