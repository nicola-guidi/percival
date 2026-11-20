# shellcheck shell=bash
# percival db <sub> — a per-program SQLite index for recalling everything percival collected.
#
#   The flat files in each program folder stay the source of truth; the db is a DERIVED,
#   additive store, rebuilt any time from those files. Each program has its OWN db file:
#   <program_dir>/percival.db (inspectable with the `sqlite3` CLI or any viewer — nothing hidden).
#
#   percival db sync [program]   read the program's files on disk into its db (idempotent)
#   percival db stats [program]  row counts per table
#   percival db host <name> [program]   dossier for one host: IPs, services, Shodan+CVE, endpoints, leads
#   percival db ip <addr> [program]     dossier for one IP: owning host(s), services, Shodan+CVE
#   percival db path <substr> [program] every host exposing a URL whose path matches <substr>
#   percival db view <kind> [program]   table view: hosts|services|ports|endpoints|vulns|leads
#   percival db query "<sql>" [program] run raw SQL on the program's db, tab-separated output
#
#   The program defaults to the last one you worked on. Each db holds only its own program — nothing
#   crosses between programs.

cmd_db() {
  local sub="${1:-}"; shift 2>/dev/null || true
  have python3 || ui_die "python3 is required" "percival doctor --install"

  case "$sub" in
    ""|-h|--help)
      sed -n '2,17p' "$PERCIVAL_ROOT/cmd/db.sh" | sed 's/^# \{0,1\}//' >&2; return 0 ;;

    sync)
      local prog; prog="$(resolve_program "${1:-}")"; load_program "$prog"
      local db="$WORK/percival.db"
      ui_header db "$prog"
      local t0; t0=$(date +%s)
      ui_running db "ingesting $prog into its db (offline, reads files on disk)…"
      local out; out="$(python3 "$PERCIVAL_ROOT/lib/db.py" "$db" sync "$WORK" "$prog")" || ui_die "db sync failed"
      local D_HOSTS D_IPS D_HOST_IPS D_PORTS D_ENDPOINTS D_LEADS
      eval "$(printf '%s\n' "$out" | sed 's/^\([A-Z0-9_]*\)=\(.*\)$/D_\1=\x27\2\x27/')"
      ui_ok synced "${D_HOSTS:-0} hosts · ${D_IPS:-0} IPs · ${D_HOST_IPS:-0} host↔IP · ${D_PORTS:-0} ports · ${D_ENDPOINTS:-0} endpoints · ${D_LEADS:-0} leads"
      ui_blank
      ui_ok done "$(ui_elapsed $(( $(date +%s) - t0 ))) · $db"
      ui_next "percival db host <name>   ·   percival db ip <addr>   ·   percival db stats"
      ui_blank ;;

    stats)
      local prog; prog="$(resolve_program "${1:-}")"; load_program "$prog"
      local db="$WORK/percival.db"
      ui_header db "$prog"
      [ -f "$db" ] || ui_die "no db yet for $prog" "percival db sync $prog"
      python3 "$PERCIVAL_ROOT/lib/db.py" "$db" stats | while IFS='=' read -r k v; do
        ui_info "$(printf '%s' "$k" | tr '[:upper:]' '[:lower:]')" "$v"
      done
      ui_blank ;;

    host|ip|path)
      [ -n "${1:-}" ] || ui_die "give a value" "percival db $sub <value> [program]"
      local val="$1"; shift 2>/dev/null || true
      local prog; prog="$(resolve_program "${1:-}")"; load_program "$prog"
      local db="$WORK/percival.db"
      [ -f "$db" ] || ui_die "no db yet for $prog" "percival db sync $prog"
      python3 "$PERCIVAL_ROOT/lib/db.py" "$db" "$sub" "$val" "$prog" ;;

    view)
      [ -n "${1:-}" ] || ui_die "give a kind" "percival db view hosts [program]"
      local kind="$1"; shift
      # the program is optional; a first argument starting with '-' is a filter, not a program name
      local prog=""
      if [ -n "${1:-}" ] && [[ "$1" != -* ]]; then prog="$1"; shift; fi
      prog="$(resolve_program "$prog")"
      load_program "$prog"
      local db="$WORK/percival.db"
      [ -f "$db" ] || ui_die "no db yet for $prog" "percival db sync $prog"
      python3 "$PERCIVAL_ROOT/lib/db.py" "$db" view "$kind" "$prog" "$@" ;;

    query)
      [ -n "${1:-}" ] || ui_die "give a SQL statement" 'percival db query "SELECT * FROM hosts" [program]'
      local sql="$1"; shift 2>/dev/null || true
      local prog; prog="$(resolve_program "${1:-}")"; load_program "$prog"
      local db="$WORK/percival.db"
      [ -f "$db" ] || ui_die "no db yet for $prog" "percival db sync $prog"
      python3 "$PERCIVAL_ROOT/lib/db.py" "$db" query "$sql" ;;

    *) ui_die "unknown 'db $sub'" "percival db --help" ;;
  esac
}
