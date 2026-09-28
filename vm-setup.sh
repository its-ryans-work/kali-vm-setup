#!/usr/bin/env bash
# vm-setup.sh — new-client VM bootstrap (Kali/Debian, arm64 or amd64)
# Runs as root (the default on these boxes) or as a normal user with sudo.
# Idempotent: re-running replaces its own managed blocks. Backs up before editing.
#
# Usage:
#   ./vm-setup.sh                      # install EVERYTHING (default)
#   ./vm-setup.sh --wizard             # pick components interactively
#   ./vm-setup.sh --only go,bangbang   # only these (deps auto-added)
#   ./vm-setup.sh --skip masscan       # everything except these
#   ./vm-setup.sh --tmux-theme [minimal|powerline]  # ONLY add the tmux bar (default minimal; powerline needs a Nerd Font)
#   ./vm-setup.sh --list               # show component keys and exit
#   ./vm-setup.sh --new-user pentest   # create user w/ NOPASSWD sudo
#   ./vm-setup.sh --current-user       # non-interactive target = current user
#
# tmuxtheme is OPT-IN (a Tokyo Night powerline bar; font-safe ASCII); not in the default set.
set -euo pipefail

# Print the leading comment block for --help (robust to header length changes).
for a in "$@"; do case "$a" in -h|--help) awk 'NR>1&&/^#/{print} NR>1&&!/^#/{exit}' "$0"; exit 0 ;; esac; done

BB_REPO="its-ryans-work/bangbang"
KZ_REPO="its-ryans-work/kerbrutez"
GOBIN_DIR="/usr/local/bin"
THEME_STYLE="minimal"   # tmux bar style: minimal (font-safe) | powerline
STAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
skip() { printf '\033[2m    (skipped: %s)\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------- components
COMP_KEYS=(apt masscan netexec go gowitness kerbrute bangbang kerbrutez tmuxconf tmuxtheme zshfns)
# Installed by default (no flags). tmuxtheme is excluded: it REQUIRES a Nerd Font,
# and the user may connect from a terminal without one. Opt in via --wizard/--only.
DEFAULT_KEYS=(apt masscan netexec go gowitness kerbrute bangbang kerbrutez tmuxconf zshfns)
comp_desc() {
  case "$1" in
    apt)       echo "Base apt packages (tmux, zsh, chromium, curl)";;
    masscan)   echo "masscan (apt, C - not Go)";;
    netexec)   echo "netexec/nxc + pwn3d_label = Admin!";;
    go)        echo "Go toolchain (go.dev tarball)";;
    gowitness) echo "gowitness (needs go, chromium)";;
    kerbrute)  echo "kerbrute (needs go)";;
    bangbang)  echo "bangbang (release binary, arch-gated)";;
    kerbrutez) echo "kerbrutez (release binary, arch-gated)";;
    tmuxconf)  echo "tmux config (history/vi/mouse/clipboard)";;
    tmuxtheme) echo "tmux tokyo-night bar (minimal | --tmux-theme powerline)";;
    zshfns)    echo "zsh fns: clipboard/clip, tmux-save";;
  esac
}
ENABLED=":"
want()      { case "$ENABLED" in *":$1:"*) return 0;; *) return 1;; esac; }
enable_c()  { want "$1" || ENABLED="${ENABLED}$1:"; }
disable_c() { ENABLED="$(printf '%s' "$ENABLED" | sed "s/:$1:/:/")"; }
enable_all(){ ENABLED=":"; local k; for k in "${COMP_KEYS[@]}"; do enable_c "$k"; done; }
enable_default(){ ENABLED=":"; local k; for k in "${DEFAULT_KEYS[@]}"; do enable_c "$k"; done; }
is_default(){ case " ${DEFAULT_KEYS[*]} " in *" $1 "*) return 0;; *) return 1;; esac; }
valid_key() { local k; for k in "${COMP_KEYS[@]}"; do [[ "$k" == "$1" ]] && return 0; done; return 1; }
resolve_deps() {
  local ch=""
  if want gowitness || want kerbrute; then want go || { enable_c go; ch="$ch go"; }; fi
  if want gowitness;                   then want apt || { enable_c apt; ch="$ch apt(chromium)"; }; fi
  if want netexec || want masscan;     then want apt || { enable_c apt; ch="$ch apt"; }; fi
  if want tmuxtheme; then
    want tmuxconf || { enable_c tmuxconf; ch="$ch tmuxconf"; }
    want apt      || { enable_c apt;      ch="$ch apt(tmux)"; }
  fi
  [[ -n "$ch" ]] && echo "    auto-enabled prerequisites:$ch"
  return 0
}

wizard() {
  local sel k
  if command -v whiptail >/dev/null 2>&1; then
    local args=()
    for k in "${COMP_KEYS[@]}"; do
      if is_default "$k"; then args+=("$k" "$(comp_desc "$k")" ON)
      else args+=("$k" "$(comp_desc "$k")" OFF); fi
    done
    sel="$(whiptail --title "vm-setup" --checklist \
      "Space toggles, Tab to OK. Prerequisites are added automatically." \
      22 76 12 "${args[@]}" 3>&1 1>&2 2>&3)" || die "cancelled"
    ENABLED=":"
    for k in $(printf '%s' "$sel" | tr -d '"'); do enable_c "$k"; done
  else
    # No whiptail: numbered toggle list. Same result, no dependency.
    enable_default
    while :; do
      printf '\n  Components (defaults preselected; tmuxtheme needs a Nerd Font):\n'
      local i=1
      for k in "${COMP_KEYS[@]}"; do
        want "$k" && printf '   %2d) [x] %-10s %s\n' "$i" "$k" "$(comp_desc "$k")" \
                  || printf '   %2d) [ ] %-10s %s\n' "$i" "$k" "$(comp_desc "$k")"
        i=$((i+1))
      done
      printf '\n  number=toggle  a=all  n=none  ENTER=accept : '
      read -r ans || true
      case "$ans" in
        "") break ;;
        a)  enable_all ;;
        n)  ENABLED=":" ;;
        ''|*[!0-9]*) warn "not a number" ;;
        *)  if [[ "$ans" -ge 1 && "$ans" -le ${#COMP_KEYS[@]} ]]; then
              k="${COMP_KEYS[$((ans-1))]}"
              want "$k" && disable_c "$k" || enable_c "$k"
            else warn "out of range"; fi ;;
      esac
    done
  fi
}

# ------------------------------------------------------------ arg parsing
NEW_USER=""; TARGET_USER=""; MODE_SEL="all"; ONLY=""; SKIPL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wizard|--configure) MODE_SEL="wizard"; shift ;;
    --only) ONLY="${2:-}"; [[ -n "$ONLY" ]] || die "--only needs a comma list (see --list)"; MODE_SEL="only"; shift 2 ;;
    --skip) SKIPL="${2:-}"; [[ -n "$SKIPL" ]] || die "--skip needs a comma list (see --list)"; shift 2 ;;
    --tmux-theme)
      ONLY="tmuxtheme"; MODE_SEL="only"
      case "${2:-}" in
        powerline|minimal) THEME_STYLE="$2"; shift 2 ;;
        *) shift ;;                      # no style given -> default (minimal)
      esac ;;
    --list) for k in "${COMP_KEYS[@]}"; do printf '  %-10s %s\n' "$k" "$(comp_desc "$k")"; done; exit 0 ;;
    --current-user) TARGET_USER="$(id -un)"; shift ;;
    --new-user) NEW_USER="${2:-}"; [[ -n "$NEW_USER" ]] || die "--new-user needs a name"; shift 2 ;;
    *) die "Unknown option: $1  (try --help or --list)" ;;
  esac
done

# ---------------------------------------------------------------- preflight
say "Preflight"
if [[ $EUID -eq 0 ]]; then SUDO=""; MODE="root"
else command -v sudo >/dev/null || die "Not root and sudo not found."; SUDO="sudo"; MODE="user+sudo"; fi
# curl is needed before the apt stage (Go version fetch, all downloads use it),
# so bootstrap it here rather than dying — minimal images ship without it.
if ! command -v curl >/dev/null 2>&1; then
  echo "    curl missing, installing it first"
  $SUDO apt-get update -qq && $SUDO apt-get install -y curl ca-certificates || die "could not install curl"
fi

# A fresh VM often has a wrong clock, which makes every HTTPS fetch fail with a
# certificate "not yet valid" error. If TLS is broken, fix the clock: enable NTP
# for the long run, and force an immediate correction from an HTTP Date header
# (plain HTTP has no certificate to validate, so a wrong clock cannot block it).
if ! curl -fsI --max-time 8 https://go.dev >/dev/null 2>&1; then
  warn "HTTPS check failed (often a wrong VM clock) - correcting the clock"
  command -v timedatectl >/dev/null 2>&1 && $SUDO timedatectl set-ntp true >/dev/null 2>&1 || true
  _httpdate="$(curl -sI --max-time 10 http://cloudflare.com 2>/dev/null | grep -i '^date:' | head -1 | cut -d' ' -f2- | tr -d '\r')"
  [ -n "$_httpdate" ] && $SUDO date -s "$_httpdate" >/dev/null 2>&1 && echo "    clock set to $(date -u +%FT%TZ)"
  curl -fsI --max-time 8 https://go.dev >/dev/null 2>&1 || warn "HTTPS still failing after clock fix - downloads may fail"
fi
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  arm64) ZIG_TRIPLE="aarch64-linux-musl" ;;
  amd64) ZIG_TRIPLE="x86_64-linux-musl"  ;;
  *) die "Unsupported arch: $ARCH" ;;
esac
echo "    user=$(id -un)  mode=$MODE  arch=$ARCH"

# ------------------------------------------------------------ selection
say "Component selection"
case "$MODE_SEL" in
  all)    enable_default ;;
  wizard) wizard ;;
  only)   ENABLED=":"
          for k in ${ONLY//,/ }; do valid_key "$k" || die "unknown component '$k' (see --list)"; enable_c "$k"; done ;;
esac
for k in ${SKIPL//,/ }; do valid_key "$k" || die "unknown component '$k' (see --list)"; disable_c "$k"; done
resolve_deps
printf '    selected:'; for k in "${COMP_KEYS[@]}"; do want "$k" && printf ' %s' "$k"; done; printf '\n'
[[ "$ENABLED" == ":" ]] && { warn "nothing selected, exiting"; exit 0; }

# ------------------------------------------------------------ target user
if [[ -z "$TARGET_USER" && -z "$NEW_USER" ]]; then
  if [[ -t 0 ]]; then
    say "Install target"
    printf '      1) current user (%s)\n      2) a new user\n' "$(id -un)"
    read -r -p "    Choice [1/2] (default 1): " _c
    if [[ "$_c" == "2" ]]; then read -r -p "    New username: " NEW_USER; [[ -n "$NEW_USER" ]] || die "no username"; 
    else TARGET_USER="$(id -un)"; fi
  else
    TARGET_USER="$(id -un)"; echo "    non-interactive, using current user ($TARGET_USER)"
  fi
fi
if [[ -n "$NEW_USER" ]]; then
  # This string is interpolated into /etc/sudoers.d. Reject anything that could
  # break it; no dots, because sudo's #includedir silently ignores such files.
  [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Invalid username '$NEW_USER'"
  say "User '$NEW_USER'"
  id "$NEW_USER" >/dev/null 2>&1 && echo "    exists, reusing" || { $SUDO useradd -m -s /bin/zsh "$NEW_USER"; echo "    created"; }
  $SUDO usermod -aG sudo "$NEW_USER"
  # Validate in a TEMP file: a malformed drop-in breaks sudo for EVERY user.
  SUD_TMP="$(mktemp)"; printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$NEW_USER" > "$SUD_TMP"
  if $SUDO visudo -cf "$SUD_TMP" >/dev/null 2>&1; then
    $SUDO install -m 0440 -o root -g root "$SUD_TMP" "/etc/sudoers.d/90-$NEW_USER"
    echo "    NOPASSWD sudo installed (validated)"
  else warn "sudoers syntax check FAILED — not installed, sudo untouched"; fi
  rm -f "$SUD_TMP"; TARGET_USER="$NEW_USER"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" ]] || die "cannot resolve home for $TARGET_USER"
ZSHRC="$TARGET_HOME/.zshrc"; TMUXCONF="$TARGET_HOME/.tmux.conf"
echo "    target: $TARGET_USER ($TARGET_HOME)"

as_target() {
  if [[ "$TARGET_USER" == "$(id -un)" ]]; then "$@"
  elif [[ $EUID -eq 0 ]]; then runuser -u "$TARGET_USER" -- "$@"
  else sudo -u "$TARGET_USER" -H -- "$@"; fi
}
own() { [[ "$TARGET_USER" == "$(id -un)" ]] || $SUDO chown -R "$TARGET_USER:$TARGET_USER" "$1"; }
install_release_bin() {
  local name="$1" repo="$2" asset="$3"
  local url="https://github.com/${repo}/releases/latest/download/${asset}"
  curl -fsIL -o /dev/null "$url" 2>/dev/null || { warn "$name: no '$asset' for arch '$ARCH' — skipping"; return 0; }
  local t; t="$(mktemp -d)"
  if curl -fsSL -o "$t/$name" "$url" && head -c4 "$t/$name" | grep -q $'\x7fELF'; then
    $SUDO install -m 0755 "$t/$name" "/usr/local/bin/$name"
    echo "    $name <- $asset  sha256=$(sha256sum "$t/$name" | cut -c1-16)…"
  else warn "$name: download failed or not an ELF — skipping"; fi
  rm -rf "$t"
}

# ------------------------------------------------------------------ 1. apt
say "apt packages"
if want apt; then
  PKGS=(curl ca-certificates tmux zsh)
  want gowitness && PKGS+=(chromium)
  want masscan   && PKGS+=(masscan)
  $SUDO apt-get update -qq
  $SUDO apt-get install -y "${PKGS[@]}"
  if want netexec; then
    $SUDO apt-get install -y netexec 2>/dev/null || warn "netexec unavailable (Kali-only) — skipping"
  fi
else skip "apt"; fi

# -------------------------------------------------------------------- 2. go
say "Go toolchain"
if want go; then
  GO_WANT="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)"
  [[ -n "$GO_WANT" ]] || die "could not resolve latest Go version"
  GO_HAVE=""; [[ -x /usr/local/go/bin/go ]] && GO_HAVE="$(/usr/local/go/bin/go version | awk '{print $3}')"
  if [[ "$GO_HAVE" == "$GO_WANT" ]]; then echo "    $GO_WANT already present"
  else
    echo "    installing $GO_WANT (have: ${GO_HAVE:-none})"
    GTMP="$(mktemp -d)"
    curl -fsSL -o "$GTMP/go.tgz" "https://go.dev/dl/${GO_WANT}.linux-${ARCH}.tar.gz"
    $SUDO rm -rf /usr/local/go; $SUDO tar -C /usr/local -xzf "$GTMP/go.tgz"; rm -rf "$GTMP"
  fi
  export PATH="/usr/local/go/bin:$PATH"; go version
else skip "go"; fi

# ------------------------------------------------------------- 3. go tools
say "Go tools -> $GOBIN_DIR"
go_install() {
  local t="$1"
  if [[ -n "$SUDO" ]]; then $SUDO env "PATH=$PATH" "GOBIN=$GOBIN_DIR" go install "$t" || warn "FAILED: $t"
  else GOBIN="$GOBIN_DIR" go install "$t" || warn "FAILED: $t"; fi
}
if want gowitness; then echo "    gowitness"; go_install "github.com/sensepost/gowitness@latest"; else skip "gowitness"; fi
if want kerbrute;  then echo "    kerbrute";  go_install "github.com/ropnop/kerbrute@latest";  else skip "kerbrute";  fi

# ------------------------------------------------------- 4. release binaries
say "Release binaries (arch-gated)"
if want bangbang;  then install_release_bin bangbang  "$BB_REPO" "bangbang-linux-${ARCH}";  else skip "bangbang";  fi
if want kerbrutez; then install_release_bin kerbrutez "$KZ_REPO" "kerbrutez-${ZIG_TRIPLE}"; else skip "kerbrutez"; fi

# ------------------------------------------------------------- 5. tmux conf
say "tmux config"
if want tmuxconf; then
  [[ -f "$TMUXCONF" ]] && as_target cp "$TMUXCONF" "${TMUXCONF}.bak.${STAMP}" && echo "    backed up"
  as_target tee "$TMUXCONF" >/dev/null <<'TC_EOF'
set -g history-limit 1000000
setw -g mode-keys vi
set -g mouse on
set -g set-clipboard on
TC_EOF
  if want tmuxtheme; then
    # Replica of the user's own Mac status bar, adapted for Linux, in two styles
    # (--tmux-theme [minimal|powerline]):
    #   minimal   : flat colour-block segments, NO separators, no glyphs. Font-safe;
    #               on a non-powerline terminal it is just clean blocks.
    #   powerline : rage28-style chained banners - every window (incl. two in a row)
    #               starts with a  wedge and shows a two-tone #I|#W chevron. Needs a
    #               powerline/Nerd Font in the terminal you connect FROM.
    # A shared header sets the palette + transparent bar; the branch writes the
    # style-specific segments. Powerline glyphs go in as __R__/__L__ placeholders so
    # the #{} / $() stay literal in the quoted heredoc, then sed swaps in the bytes.
    as_target tee -a "$TMUXCONF" >/dev/null <<'TT_HDR'

# --- Tokyo Night status bar ---
set -g @tn_ink     '#1a1b26'
set -g @tn_fg      '#c0caf5'
set -g @tn_dim     '#737aa2'
set -g @tn_hl      '#3b4261'
set -g @tn_d3      '#545c7e'
set -g @tn_blue    '#7aa2f7'
set -g @tn_magenta '#bb9af7'
set -g @tn_yellow  '#e0af68'
set -g status on
set -g status-style 'bg=default'
set -g status-interval 2
set -g status-left-length 60
set -g status-right-length 60
run-shell 'tmux set -g @tn_host "$(hostname -s 2>/dev/null || hostname)"'
TT_HDR
  if [ "$THEME_STYLE" = powerline ]; then
    as_target tee -a "$TMUXCONF" >/dev/null <<'TT_PL'
# powerline: rage28-style SEAMLESS chained chevrons. Requires a SOLID bar bg so the
# segment-end wedges blend into it (a transparent bar makes them float as triangles).
set -g status-style 'bg=#1a1b26'
set -g window-status-separator ''
set -g status-left '#[fg=#1a1b26,bg=#{?client_prefix,#{@tn_yellow},#{@tn_blue}},bold] #S@#{@tn_host} #[fg=#{?client_prefix,#{@tn_yellow},#{@tn_blue}},bg=#1a1b26,nobold]__R__'
set -g window-status-format '#[fg=#1a1b26,bg=#{@tn_dim}]__R__#[fg=#c0caf5,bg=#{@tn_dim}] #I #[fg=#{@tn_dim},bg=#{@tn_d3}]__R__#[fg=#c0caf5,bg=#{@tn_d3}] #W #[fg=#{@tn_d3},bg=#1a1b26]__R__'
set -g window-status-current-format '#[fg=#1a1b26,bg=#{@tn_magenta}]__R__#[fg=#1a1b26,bg=#{@tn_magenta},bold] #I #[fg=#{@tn_magenta},bg=#{@tn_blue}]__R__#[fg=#1a1b26,bg=#{@tn_blue}] #W #[fg=#{@tn_blue},bg=#1a1b26,nobold]__R__'
set -g status-right '#[fg=#{@tn_dim},bg=#1a1b26] #(~/.tmux/scripts/netspeed.sh) #[fg=#{@tn_hl},bg=#1a1b26]__L__#[fg=#c0caf5,bg=#{@tn_hl}] %Y-%m-%d %H:%M '
TT_PL
    as_target sed -i "s/__R__/$(printf '')/g; s/__L__/$(printf '')/g" "$TMUXCONF"
  else
    as_target tee -a "$TMUXCONF" >/dev/null <<'TT_MIN'
# minimal: flat colour blocks, no separators, no glyphs
set -g status-left '#[fg=#{@tn_ink},bg=#{?client_prefix,#{@tn_yellow},#{@tn_blue}},bold] #S@#{@tn_host} #[default]'
set -g window-status-format '#[fg=#{@tn_dim},bg=default] #I#{?#{automatic-rename},, #W}#{?window_zoomed_flag, (zoom),} '
set -g window-status-current-format '#[fg=#{@tn_ink},bg=#{@tn_magenta},bold] #I#{?#{automatic-rename},, #W}#{?window_zoomed_flag, (zoom),} #[default]'
set -g status-right '#[fg=#{@tn_dim},bg=default]#(~/.tmux/scripts/netspeed.sh) #[fg=#{@tn_ink},bg=#{@tn_hl}] %Y-%m-%d %H:%M #[default]'
TT_MIN
  fi
    echo "    status bar written (style: $THEME_STYLE)"
  fi
else skip "tmuxconf"; fi

# ------------------------------------------------------------ 6. netspeed (theme)
say "tmux netspeed script"
if want tmuxtheme; then
  # Linux port of the user's Mac netspeed.sh (route/netstat -> ip route//proc/net/dev).
  # The status bar references ~/.tmux/scripts/netspeed.sh; no tpm/plugin involved.
  as_target mkdir -p "$TARGET_HOME/.tmux/scripts"
  as_target tee "$TARGET_HOME/.tmux/scripts/netspeed.sh" >/dev/null <<'NS_EOF'
#!/usr/bin/env bash
# Prints "v <rx>/s ^ <tx>/s" for the default-route interface, from /proc/net/dev
# deltas since the previous call (tmux runs this every status-interval).
iface=$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -z "$iface" ] && exit 0
line=$(sed 's/:/ /' /proc/net/dev | awk -v i="$iface" '$1==i {print $2, $10}')
[ -z "$line" ] && exit 0
read -r rx tx <<<"$line"
now=$(date +%s)
state="${TMPDIR:-/tmp}/tmux-netspeed-${iface}"
[ -f "$state" ] && read -r prev_t prev_rx prev_tx < "$state"
echo "$now $rx $tx" > "$state"
dt=$((now - ${prev_t:-0}))
if [ -z "${prev_t:-}" ] || [ "$dt" -le 0 ] || [ "$dt" -gt 60 ]; then exit 0; fi
human() { awk -v b="$1" -v t="$dt" 'BEGIN{r=b/t; if(r<0)r=0;
  if(r>=1048576)printf "%.1fMB",r/1048576; else if(r>=1024)printf "%.0fKB",r/1024; else printf "%.0fB",r}'; }
printf 'v %s/s ^ %s/s' "$(human $((rx-${prev_rx:-rx})))" "$(human $((tx-${prev_tx:-tx})))"
NS_EOF
  as_target chmod +x "$TARGET_HOME/.tmux/scripts/netspeed.sh"
  echo "    netspeed.sh installed"
else skip "tmuxtheme"; fi

# ------------------------------------------------------------------ 7. nxc
say "netexec pwn3d_label"
if want netexec && command -v nxc >/dev/null 2>&1; then
  NXC_DIR="$TARGET_HOME/.nxc"
  [[ -d "$NXC_DIR" ]] || { echo "    generating config (first run)"; as_target nxc >/dev/null 2>&1 || true; }
  NXC_CONF=""
  for c in "$NXC_DIR/nxc.conf" "$NXC_DIR/.nxc.conf"; do [[ -f "$c" ]] && { NXC_CONF="$c"; break; }; done
  if [[ -n "$NXC_CONF" ]]; then
    as_target cp "$NXC_CONF" "${NXC_CONF}.bak.${STAMP}"
    as_target sed -i 's/^pwn3d_label[[:space:]]*=.*/pwn3d_label = Admin!/' "$NXC_CONF"
    echo "    $(grep '^pwn3d_label' "$NXC_CONF")"
  else warn "no nxc.conf under $NXC_DIR — run 'nxc' once as $TARGET_USER, then re-run"; fi
elif want netexec; then warn "nxc not installed — skipping label change"
else skip "netexec"; fi

# ----------------------------------------------------------------- 9. zshrc
say "zsh functions"
if want zshfns; then
  [[ -f "$ZSHRC" ]] && as_target cp "$ZSHRC" "${ZSHRC}.bak.${STAMP}" && echo "    backed up"
  as_target touch "$ZSHRC"
  as_target sed -i '/# >>> vm-setup >>>/,/# <<< vm-setup <<</d' "$ZSHRC"
  as_target tee -a "$ZSHRC" >/dev/null <<'ZB_EOF'
# >>> vm-setup >>>
export PATH="/usr/local/go/bin:/usr/local/bin:$HOME/go/bin:$PATH"

# Pipe stdin to the LOCAL clipboard over SSH via OSC 52.
#   some-command | clipboard      (or: | clip)
clipboard() {
  printf '\033]52;c;%s\a' "$(base64 | tr -d '\n')" > /dev/tty
}
clip() { clipboard; }   # function, not alias: also works in scripts and pipelines

# Dump scrollback from every tmux pane to one file.
#   tmux-save [--file <path>]
tmux-save() {
  local output_file=~/tmux_all_history.txt pane
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file)
        [[ -n "$2" ]] || { printf 'tmux-save: --file requires a path\n' >&2; return 1; }
        output_file="$2"; shift 2 ;;
      --help|-h)
        printf 'Usage: tmux-save [--file <output_file>]\n\n'
        printf '  --file <path>   Output file (default: ~/tmux_all_history.txt)\n'
        printf '  --help, -h      Show this help\n'
        return 0 ;;
      *)
        printf 'tmux-save: unknown option: %s\n' "$1" >&2; return 1 ;;
    esac
  done
  command -v tmux >/dev/null 2>&1 || { printf 'tmux-save: tmux not installed\n' >&2; return 1; }
  tmux list-panes -a >/dev/null 2>&1 || { printf 'tmux-save: no tmux server running\n' >&2; return 1; }
  : > "$output_file" || return 1
  tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}" | while read -r pane; do
    printf '===== %s =====\n' "$pane"
    tmux capture-pane -p -S - -t "$pane"
    printf '\n\n\n'
  done >> "$output_file"
  printf 'Saved tmux scrollback to: %s (%s lines)\n' "$output_file" "$(wc -l < "$output_file" | tr -d ' ')"
}
alias tmuxsave='tmux-save'
# <<< vm-setup <<<
ZB_EOF
else skip "zshfns"; fi

# ---------------------------------------------------------------- summary
say "Done ($MODE, target=$TARGET_USER)"
for b in gowitness kerbrute masscan chromium nxc bangbang kerbrutez; do
  printf '    %-11s %s\n' "$b" "$(command -v "$b" 2>/dev/null || echo '-')"
done
want go && printf '    %-11s %s\n' "go" "$(go version 2>/dev/null | awk '{print $3}')"
if want tmuxtheme; then
  if [ "$THEME_STYLE" = powerline ]; then cat <<'FONT_EOF'

  tmux bar installed (style: powerline). Uses  /  banner glyphs, so the
  terminal you connect FROM needs a powerline/Nerd Font, or you will see boxes.
  Re-run with `--tmux-theme minimal` for a font-safe bar.
FONT_EOF
  else cat <<'FONT_EOF'

  tmux bar installed (style: minimal). Colour blocks, no separator glyphs, no
  Nerd Font needed - renders on any terminal. For powerline banners on a
  Nerd-Font terminal, re-run with `--tmux-theme powerline`.
FONT_EOF
  fi
fi
[[ -n "$NEW_USER" ]] && printf '\n  New user: su - %s   (passwordless sudo; set a password with passwd)\n' "$NEW_USER"
cat <<'NEXT_EOF'

Next:
  exec zsh                      # reload (source alone cannot unset old functions)
  echo hi | clip                # test OSC 52 -> local clipboard
  tmux-save --help
NEXT_EOF
