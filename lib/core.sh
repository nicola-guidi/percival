# shellcheck shell=bash
# lib/core.sh — paths, global config, program loading. Sourced by the dispatcher.

PERCIVAL_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/percival"
PERCIVAL_CONFIG="$PERCIVAL_CONFIG_DIR/config"
PERCIVAL_LAST="$PERCIVAL_CONFIG_DIR/last_program"
# This tool used to be called kestrel: on first run move its config dir across, so nothing is asked
# or lost (the workspace you chose and the last program you used carry over).
_old_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/kestrel"
if [ -d "$_old_cfg" ] && [ ! -e "$PERCIVAL_CONFIG_DIR" ] && mv "$_old_cfg" "$PERCIVAL_CONFIG_DIR" 2>/dev/null; then
  if [ -f "$PERCIVAL_CONFIG" ]; then
    sed 's/^KESTREL_WORKSPACE=/PERCIVAL_WORKSPACE=/' "$PERCIVAL_CONFIG" > "$PERCIVAL_CONFIG.new" \
      && mv "$PERCIVAL_CONFIG.new" "$PERCIVAL_CONFIG"
  fi
fi
unset _old_cfg
DEFAULT_UA='Mozilla/5.0'
DEFAULT_WORKSPACE="$HOME/hunts"

# Workspace = the folder where programs live. Precedence:
#   1. PERCIVAL_BASE in the environment (one-off override)
#   2. PERCIVAL_WORKSPACE saved in ~/.config/percival/config (chosen once, on first use)
#   3. ~/hunts
_env_base="${PERCIVAL_BASE:-${KESTREL_BASE:-}}"   # KESTREL_BASE: the old name, still honoured
# global config (optional): workspace, notification settings
# shellcheck disable=SC1090
[ -f "$PERCIVAL_CONFIG" ] && . "$PERCIVAL_CONFIG"
PERCIVAL_BASE="${_env_base:-${PERCIVAL_WORKSPACE:-$DEFAULT_WORKSPACE}}"
unset _env_base

# global_set KEY VALUE — persist a key in ~/.config/percival/config
global_set() {
  mkdir -p "$PERCIVAL_CONFIG_DIR"
  [ -f "$PERCIVAL_CONFIG" ] || printf '# percival global config\n' > "$PERCIVAL_CONFIG"
  conf_set "$PERCIVAL_CONFIG" "$1" "$2"
}

# ensure_workspace — first use: ask once where programs live, create it, remember it
ensure_workspace() {
  if ! grep -q '^PERCIVAL_WORKSPACE=' "$PERCIVAL_CONFIG" 2>/dev/null; then
    local w
    ui_section workspace
    ui_dim "First run: where should percival keep your programs?"
    w="$(ui_ask 'Workspace folder' "$PERCIVAL_BASE")"
    w="${w/#\~/$HOME}"
    PERCIVAL_BASE="$w"
    global_set PERCIVAL_WORKSPACE "$w"
  fi
  mkdir -p "$PERCIVAL_BASE" 2>/dev/null || ui_die "cannot create workspace $PERCIVAL_BASE"
  [ -w "$PERCIVAL_BASE" ] || ui_die "workspace $PERCIVAL_BASE is not writable"
}

# valid program name: letters, digits, dot, dash, underscore
valid_program_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }

program_dir() { printf '%s/%s' "$PERCIVAL_BASE" "$1"; }

# migrate_program_dir <dir> — a program made when this tool was called kestrel: rename its two files,
# nothing else changes (recon data, content, js, notes and the report stay exactly where they are)
migrate_program_dir() {
  local d="${1%/}"
  if [ ! -f "$d/percival.conf" ] && [ -f "$d/kestrel.conf" ]; then
    mv "$d/kestrel.conf" "$d/percival.conf" || return 0
    [ -f "$d/kestrel.db" ] && [ ! -e "$d/percival.db" ] && mv "$d/kestrel.db" "$d/percival.db"
    ui_info migrated "$(basename "$d"): kestrel.conf → percival.conf (data untouched)" 2>/dev/null || true
  fi
  return 0
}

# list program names (folders that hold a percival.conf, an old kestrel.conf or a legacy env.sh)
list_programs() {
  local d
  [ -d "$PERCIVAL_BASE" ] || return 0
  for d in "$PERCIVAL_BASE"/*/; do
    migrate_program_dir "$d"
    [ -f "$d/percival.conf" ] || [ -f "$d/env.sh" ] || continue
    basename "$d"
  done
}

remember_program() { mkdir -p "$PERCIVAL_CONFIG_DIR" && printf '%s\n' "$1" > "$PERCIVAL_LAST"; }

# resolve_program [name] → prints the program name, or dies with a hint.
# No name given: the last program used, or the only one that exists.
resolve_program() {
  local p="${1:-}" all n
  if [ -z "$p" ]; then
    if [ -s "$PERCIVAL_LAST" ]; then p="$(cat "$PERCIVAL_LAST")"
    else
      all="$(list_programs)"; n=$(printf '%s' "$all" | grep -c . || true)
      [ "$n" -eq 1 ] && p="$all"
    fi
  fi
  [ -n "$p" ] || ui_die "no program given" "percival ls   ·   percival new <program>"
  [ -d "$(program_dir "$p")" ] || ui_die "program '$p' not found in $PERCIVAL_BASE" "percival new $p"
  printf '%s' "$p"
}

# write a key=value config with safe shell quoting
# conf_write <file> KEY VALUE [KEY VALUE ...]
conf_write() {
  local f="$1"; shift
  {
    printf '# percival program config — written by percival, edit with care\n'
    while [ $# -ge 2 ]; do printf '%s=%q\n' "$1" "$2"; shift 2; done
  } > "$f"
}

# conf_set <file> KEY VALUE — replace or append a single key
conf_set() {
  local f="$1" k="$2" v tmp
  v="$(printf '%q' "$3")"
  tmp="$(mktemp)"
  grep -v "^$k=" "$f" > "$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$k" "$v" >> "$tmp"
  mv "$tmp" "$f"
}

# load_program <name>: export everything the engine scripts expect (same names as
# the legacy env.sh), then cd into the program folder.
load_program() {
  PROGRAM="$1"
  WORK="$(program_dir "$PROGRAM")"
  migrate_program_dir "$WORK"
  if [ -f "$WORK/percival.conf" ]; then
    # shellcheck disable=SC1091
    . "$WORK/percival.conf"
  elif [ -f "$WORK/env.sh" ]; then
    # legacy program created by bb-init: still usable
    # shellcheck disable=SC1091
    . "$WORK/env.sh"
    LEGACY_PROGRAM=1
  else
    ui_die "'$PROGRAM' has no percival.conf" "percival new $PROGRAM"
  fi
  UA="${UA:-$DEFAULT_UA${UA_SUFFIX:+ $UA_SUFFIX}}"
  RATE="${RATE:-5}"
  CURATED="${CURATED:-$PERCIVAL_ROOT/wordlists/curated.txt}"
  HEADERS_FILE="$WORK/headers.txt"
  # legacy single header: the first custom header (engine scripts also read HEADERS_FILE)
  YWH="${YWH:-}"
  if [ -z "$YWH" ] && [ -s "$HEADERS_FILE" ]; then YWH="$(head -n1 "$HEADERS_FILE")"; fi
  export PROGRAM WORK UA YWH RATE CURATED HEADERS_FILE
  export PLATFORM="${PLATFORM:-}" PROGRAM_URL="${PROGRAM_URL:-}" PORTSCAN_ALLOWED="${PORTSCAN_ALLOWED:-n}"
  # intercepting-proxy settings (Burp/Caido): the URL lives in PROXY_URL and the on/off
  # preference in PROXY_DEFAULT. The engine-facing PROXY var is set ONLY by the command that
  # runs a stage (recon/retest/replay), so a URL sitting in the config never proxies by itself.
  export PROXY_URL="${PROXY_URL:-}" PROXY_DEFAULT="${PROXY_DEFAULT:-n}"
  export SCOPE_FILE="$WORK/recon/scope.txt"
  export APEX_FILE="$WORK/recon/apex.txt"
  export HOSTS_FILE="$WORK/recon/hosts.txt"
  export SUBS="$WORK/recon/subs_all.txt"
  export INSCOPE="$WORK/recon/subs_inscope.txt"
  export OOS_FILE="$WORK/recon/oos.txt"
  export CIDR_INSCOPE="$WORK/recon/cidr_inscope.txt"
  export CIDR_OOS="$WORK/recon/cidr_oos.txt"
  export IP_TARGETS="$WORK/recon/ip_targets.txt"
  cd "$WORK" || ui_die "cannot enter $WORK"
  remember_program "$PROGRAM"
}

# write the legacy env.sh so the original bb-* scripts keep working on this program
write_legacy_env() {
  local w="$1"
  {
    printf '# Session variables for: %s  (generated by percival — percival loads these itself)\n' "$PROGRAM"
    printf 'export %s=%q\n' \
      PROGRAM "$PROGRAM" WORK "$w" UA "$UA" YWH "$YWH" RATE "$RATE" CURATED "$CURATED" \
      SCOPE_FILE "$w/recon/scope.txt" APEX_FILE "$w/recon/apex.txt" HOSTS_FILE "$w/recon/hosts.txt" \
      SUBS "$w/recon/subs_all.txt" INSCOPE "$w/recon/subs_inscope.txt" OOS_FILE "$w/recon/oos.txt" \
      CIDR_INSCOPE "$w/recon/cidr_inscope.txt" CIDR_OOS "$w/recon/cidr_oos.txt" \
      IP_TARGETS "$w/recon/ip_targets.txt" HEADERS_FILE "$w/headers.txt"
    printf 'cd %q\n' "$w"
  } > "$w/env.sh"
}

# have <tool> — is it on PATH
have() { command -v "$1" >/dev/null 2>&1; }

# chrome_bin — path of a usable Chrome/Chromium (for httpx -system-chrome screenshots), else empty
chrome_bin() {
  local b
  for b in chromium chromium-browser google-chrome google-chrome-stable chrome; do
    command -v "$b" 2>/dev/null && return 0
  done
  return 0
}
chrome_ok() { [ -n "$(chrome_bin)" ]; }

# ---- intercepting proxy (Burp / Caido) ------------------------------------
# proxy_default_url — the proxy configured for this program (PROXY_URL in percival.conf),
# else the conventional Burp/Caido default on localhost:8080.
proxy_default_url() { printf '%s' "${PROXY_URL:-http://127.0.0.1:8080}"; }

# resolve_proxy on|off|auto — echo the proxy URL to use (empty = don't proxy).
#   on   : the configured/default URL        (a --proxy flag)
#   off  : nothing                            (a --no-proxy flag)
#   auto : the URL iff PROXY_DEFAULT=y        (the program's onboarding choice)
resolve_proxy() {
  case "${1:-auto}" in
    on)   proxy_default_url ;;
    off)  : ;;
    auto) [ "${PROXY_DEFAULT:-n}" = y ] && proxy_default_url || : ;;
  esac
}

# proxy_for_run on|off|auto — set and export the engine-facing PROXY for this run.
# Resolves the URL, preflights it (hard stop if nothing is listening — never fire a whole run at
# a dead proxy), and prints the one-line notice. Call once in a command before running a stage.
# Not in a subshell: ui_die must stop the command, not just a $(...) child.
proxy_for_run() {
  PROXY="$(resolve_proxy "${1:-auto}")"
  if [ -n "$PROXY" ]; then
    proxy_up "$PROXY" || ui_die "proxy not listening at $PROXY" "start Burp/Caido, or re-run with --no-proxy"
    ui_info proxy "routing target traffic through $PROXY"
  fi
  export PROXY
}

# proxy_up <url|host:port> — true if something is listening there (TCP connect, no deps).
# Used as a preflight so percival never fires a whole run at a proxy that isn't running.
proxy_up() {
  local hp="${1#*://}"; hp="${hp%%/*}"
  local host="${hp%%:*}" port="${hp##*:}"
  [ "$host" = "$port" ] && port=8080
  [ -n "$host" ] || host=127.0.0.1
  if have timeout; then
    timeout 2 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null
  else
    (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null
  fi
}

# count lines of a file (0 if missing)
count_lines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
