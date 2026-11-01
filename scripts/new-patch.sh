#!/usr/bin/env bash
# Helpers for working on Upside's patches without mixing them up.
#
#   scripts/new-patch.sh start           Fresh Actual + all current patches,
#                                         committed locally as the baseline.
#   scripts/new-patch.sh save <name>     Write everything changed since the
#                                         baseline to patches/<name>.patch.
#
# (Patches are applied in filename order by scripts/prepare.sh.)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/actual"

case "${1:-}" in
  start)
    "$ROOT/scripts/prepare.sh" >/dev/null
    git -C "$SRC" add -A
    git -C "$SRC" -c user.name=upside -c user.email=upside@localhost \
      commit -q -m "baseline: Actual + existing patches"
    echo "Baseline ready in $SRC"
    ;;
  save)
    name="${2:?usage: new-patch.sh save <name>}"
    if [ "$(git -C "$SRC" log -1 --format=%s)" != "baseline: Actual + existing patches" ]; then
      echo "No baseline commit; run 'scripts/new-patch.sh start' first" >&2
      exit 1
    fi
    git -C "$SRC" add -N .
    git -C "$SRC" diff > "$ROOT/patches/$name.patch"
    git -C "$SRC" diff --stat | tail -1
    ;;
  *)
    sed -n '2,9p' "$0"
    exit 1
    ;;
esac
