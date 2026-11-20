#!/usr/bin/env bash
# install.sh — put `percival` on your PATH (symlink into ~/.local/bin). Re-run safely.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${PERCIVAL_BIN_DIR:-${KESTREL_BIN_DIR:-$HOME/.local/bin}}"
mkdir -p "$BIN"
chmod +x "$ROOT/percival" "$ROOT/lib/scope.py"
ln -sf "$ROOT/percival" "$BIN/percival"
echo "  ✓ percival → $BIN/percival"
# the old command name (this tool used to be called kestrel): drop its symlink if it is one of ours
if [ -L "$BIN/kestrel" ]; then
  rm -f "$BIN/kestrel" && echo "  ✓ old 'kestrel' command removed (it is called percival now)"
fi
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "  ⚠ $BIN is not in \$PATH — add to your shell rc:  export PATH=\"$BIN:\$PATH\"" ;;
esac
echo "  › next: percival doctor"
