# shellcheck shell=bash
# percival info [program] — reprint the onboarding summary (no traffic).

cmd_info() {
  local prog="" a
  for a in "$@"; do
    case "$a" in
      -h|--help) printf 'usage: percival info [program]\n\n  Shows the program settings and scope summary.\n' >&2; return 0 ;;
      -*) ui_die "unknown option '$a'" "percival info --help" ;;
      *) prog="$a" ;;
    esac
  done
  prog="$(resolve_program "$prog")"
  load_program "$prog"
  ui_header info "$prog"
  if [ -f "$WORK/scope" ]; then scope_rebuild >/dev/null || true; fi
  program_summary
  ui_blank
  ui_next "percival recon $prog"
  ui_blank
}
