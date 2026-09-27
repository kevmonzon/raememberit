#!/usr/bin/env bash
# Regenerate plugin/hooks/hooks.json from engine/settings.fragment.json.
#
# There are two ways to wire the hooks — a settings fragment the standalone installer merges, and a
# plugin's own hooks.json — and they must say the same thing. Generating one from the other is the only
# way to guarantee that; this project has been bitten three times by two descriptions of one mechanism
# drifting apart.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT/engine/settings.fragment.json" "$ROOT/plugin/hooks/hooks.json" <<'PY'
import json, sys
frag = json.load(open(sys.argv[1]))
json.dump({"description": ("raememberit's hooks. GENERATED from engine/settings.fragment.json by "
                           "tools/gen-plugin-hooks.sh — do not hand-edit; two hook definitions is a "
                           "drift surface and this project has been bitten by that three times."),
           "hooks": frag["hooks"]}, open(sys.argv[2], "w"), indent=2)
open(sys.argv[2], "a").write("\n")
PY
echo "regenerated plugin/hooks/hooks.json from engine/settings.fragment.json"
