# shellcheck shell=bash
# percival schedule — run `percival retest <program>` automatically on a schedule, so new live
# subdomains are found (and notified, if notifications are configured) without you remembering.
#
#   percival schedule <program> daily|weekly|monthly [--at HH:MM]   install (default 03:00)
#   percival schedule --list                                        what is scheduled
#   percival schedule <program> --remove                            remove it
#
# Prefers a systemd user timer (Persistent=true, so a run missed while the machine was off is
# caught up at the next boot); falls back to crontab. Either way it runs ON YOUR MACHINE, so the
# machine must be powered on at that time — for 24/7 coverage use an always-on host.

_sched_unit_dir() { printf '%s/systemd/user' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
_sched_has_systemd() { have systemctl && systemctl --user show-environment >/dev/null 2>&1; }

# OnCalendar / cron fields for a preset + HH:MM
_sched_oncalendar() { # <preset> <hh> <mm>
  case "$1" in
    daily)   printf '*-*-* %02d:%02d:00' "$2" "$3" ;;
    weekly)  printf 'Mon *-*-* %02d:%02d:00' "$2" "$3" ;;
    monthly) printf '*-*-01 %02d:%02d:00' "$2" "$3" ;;
  esac
}
_sched_cronspec() { # <preset> <hh> <mm>  → "m h dom mon dow"
  case "$1" in
    daily)   printf '%d %d * * *' "$3" "$2" ;;
    weekly)  printf '%d %d * * 1' "$3" "$2" ;;
    monthly) printf '%d %d 1 * *' "$3" "$2" ;;
  esac
}

# Timers installed when this tool was called kestrel point at the old command and the old unit names.
# Remove a program's legacy timer / cron entry (called on install and on --remove, so a program is never
# scheduled twice).
_sched_legacy_cleanup() { # <program>
  local p="$1" udir; udir="$(_sched_unit_dir)"
  if _sched_has_systemd && [ -f "$udir/kestrel-retest-$p.timer" ]; then
    systemctl --user disable --now "kestrel-retest-$p.timer" >/dev/null 2>&1 || true
    rm -f "$udir/kestrel-retest-$p.timer" "$udir/kestrel-retest-$p.service"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    ui_ok replaced "old kestrel timer for $p removed"
  fi
  if have crontab && crontab -l 2>/dev/null | grep -q "# kestrel-retest:$p$"; then
    crontab -l 2>/dev/null | grep -v "# kestrel-retest:$p$" | crontab -
    ui_ok replaced "old kestrel cron entry for $p removed"
  fi
}

cmd_schedule() {
  local prog="" when="" at="03:00" action=install
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) sed -n '2,11p' "$PERCIVAL_ROOT/cmd/schedule.sh" | sed 's/^# \{0,1\}//' >&2; return 0 ;;
      --list)    action=list ;;
      --remove)  action=remove ;;
      --at)      shift; at="${1:-03:00}" ;;
      --at=*)    at="${1#--at=}" ;;
      daily|weekly|monthly) when="$1" ;;
      -*) ui_die "unknown option '$1'" "percival schedule --help" ;;
      *)  prog="$1" ;;
    esac
    shift
  done

  local kbin="$PERCIVAL_ROOT/percival"
  local udir; udir="$(_sched_unit_dir)"

  # -------------------------------------------------------------- list
  if [ "$action" = list ]; then
    ui_header schedule "all programs"
    local any=0
    if _sched_has_systemd && [ -d "$udir" ]; then
      local f base cal
      for f in "$udir"/percival-retest-*.timer; do
        [ -e "$f" ] || continue
        base="$(basename "$f" .timer)"; base="${base#percival-retest-}"
        cal="$(sed -n 's/^OnCalendar=//p' "$f" | head -n1)"
        local nxt; nxt="$(systemctl --user list-timers "$(basename "$f")" --all 2>/dev/null | awk 'NR==2{print $1" "$2}')"
        ui_ok "$base" "systemd · $cal${nxt:+ · next $nxt}"
        any=1
      done
    fi
    if _sched_has_systemd && [ -d "$udir" ]; then
      local lf
      for lf in "$udir"/kestrel-retest-*.timer; do
        [ -e "$lf" ] || continue
        ui_warn "$(basename "$lf" .timer | sed 's/^kestrel-retest-//')" "old kestrel timer — re-create it: percival schedule <program> daily|weekly|monthly"
        any=1
      done
    fi
    if have crontab; then
      local line p spec
      while IFS= read -r line; do
        case "$line" in
          *"# percival-retest:"*)
            p="${line##*# percival-retest:}"; spec="${line%% *}"
            ui_ok "$p" "cron · $(printf '%s' "$line" | awk '{print $1,$2,$3,$4,$5}')"
            any=1 ;;
        esac
      done < <(crontab -l 2>/dev/null)
    fi
    [ "$any" -eq 0 ] && ui_info none "nothing scheduled"
    ui_blank; return 0
  fi

  # program required for install/remove
  prog="$(resolve_program "$prog")"
  local unit="percival-retest-$prog"

  # -------------------------------------------------------------- remove
  if [ "$action" = remove ]; then
    ui_header schedule "$prog"
    _sched_legacy_cleanup "$prog"
    local gone=0
    if _sched_has_systemd && [ -f "$udir/$unit.timer" ]; then
      systemctl --user disable --now "$unit.timer" >/dev/null 2>&1 || true
      rm -f "$udir/$unit.timer" "$udir/$unit.service"
      systemctl --user daemon-reload >/dev/null 2>&1 || true
      ui_ok removed "systemd timer $unit"; gone=1
    fi
    if have crontab && crontab -l 2>/dev/null | grep -q "# percival-retest:$prog$"; then
      crontab -l 2>/dev/null | grep -v "# percival-retest:$prog$" | crontab -
      ui_ok removed "cron entry for $prog"; gone=1
    fi
    [ "$gone" -eq 0 ] && ui_info none "nothing was scheduled for $prog"
    ui_blank; return 0
  fi

  # -------------------------------------------------------------- install
  [ -n "$when" ] || ui_die "give a cadence" "percival schedule $prog daily|weekly|monthly [--at HH:MM]"
  [[ "$at" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]] || ui_die "invalid --at '$at' (use HH:MM)"
  local hh="${at%%:*}" mm="${at##*:}"; hh="${hh#0}"; mm="${mm#0}"; : "${hh:=0}" "${mm:=0}"

  ui_header schedule "$prog"
  _sched_legacy_cleanup "$prog"
  ui_info target "percival retest $prog"
  ui_info cadence "$when at $at"

  if _sched_has_systemd; then
    mkdir -p "$udir"
    local cal; cal="$(_sched_oncalendar "$when" "$hh" "$mm")"
    cat > "$udir/$unit.service" <<EOF
[Unit]
Description=percival scheduled retest — $prog

[Service]
Type=oneshot
ExecStart=$kbin retest $prog
EOF
    cat > "$udir/$unit.timer" <<EOF
[Unit]
Description=percival scheduled retest timer — $prog

[Timer]
OnCalendar=$cal
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    if systemctl --user enable --now "$unit.timer" >/dev/null 2>&1; then
      ui_ok scheduled "systemd user timer · OnCalendar=$cal"
      ui_info unit "$udir/$unit.timer"
      if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
        ui_warn linger "timers run only while you're logged in — for always-on: loginctl enable-linger $USER"
      fi
    else
      ui_err systemd "could not enable the timer — see: systemctl --user status $unit.timer"
    fi
  elif have crontab; then
    local spec logf line
    spec="$(_sched_cronspec "$when" "$hh" "$mm")"
    logf="$(program_dir "$prog")/notes/schedule.log"
    line="$spec $kbin retest $prog >> $logf 2>&1 # percival-retest:$prog"
    { crontab -l 2>/dev/null | grep -v "# percival-retest:$prog$"; printf '%s\n' "$line"; } | crontab -
    ui_ok scheduled "cron · $spec"
    ui_info log "$logf"
  else
    ui_die "no scheduler found (neither systemd --user nor crontab)" "install cron, or run retest by hand"
  fi

  ui_warn note "runs on THIS machine — it must be powered on at $at (missed runs: systemd catches up at boot; cron skips)"
  ui_blank
  ui_ok done "percival schedule --list   to review"
  ui_blank
}
