#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import json
from pathlib import Path
d=json.loads(Path("data/content.json").read_text())
ids={s["id"] for s in d["stations"]}
expected={"radioprincipal","radiopop","radiorock","radioclassicas","radiocountry"}
assert ids==expected
assert set(d["now_playing"])==expected
assert set(d["schedule"])==expected
for s in d["stations"]:
    assert s["stream_url"].startswith("https://radio.studiosatweb.com.br/")
print("DATA_CONTRACT=OK")
PY

if grep -R -nE 'new[[:space:]]+AudioContext|createMediaElementSource|\.createAnalyser\(|useAudioSampleListener|currentTime[[:space:]]*=' web android ios; then
  echo "ERRO: processamento/chase proibido encontrado" >&2
  exit 1
fi
echo "CLEAN_MEDIA_PATH=OK"
