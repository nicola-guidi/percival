# Changelog

Versioning: MAJOR.MINOR.PATCH. Bump MINOR for new features, PATCH for fixes.
The version lives in `PERCIVAL_VERSION` (file `percival`); `percival version` prints it.

## 0.2.1
- README: removed the rename note.

## 0.2.0
- Renamed from kestrel to percival, with automatic migration of old config, program files and timers.
- New: `backup` (`--lite`, `--out`, `--all`), standalone `snapshot` (live hosts by default, `--leads`, `--surface`).
- New: per-program database (`percival db ...`), readable aligned output.
- New: `replay` rewritten (live hosts only, `--wayback` opt-in, `--dry-run`).
- New: proxy-liveness guard between recon stages; a dead proxy stops the run and it resumes later.
- New: search filter in the HTML report; new ASCII banner.
- Fixes: lead mapping for js_secret/fuzz_juicy, `schedule --help` leaking a code line, `backup` hints shown after a failure, `schedule --list` header.
