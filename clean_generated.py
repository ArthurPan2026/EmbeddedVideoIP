import json
import shutil
from pathlib import Path

root = Path('/home/pzy/Projects/EmbeddedVideoIP').resolve()
profile_root = (root / 'out/synth/xc7z020clg400-1/profiles').resolve()
for name in ('gba', 'gba_bram'):
    target = (profile_root / name).resolve()
    if target.parent != profile_root or not target.name.startswith('gba'):
        raise SystemExit(f'refusing unexpected generated path: {target}')
    if target.exists():
        shutil.rmtree(target)
manifest_path = root / 'out/manifest.json'
data = json.loads(manifest_path.read_text(encoding='utf-8'))
stages = data.get('stages', {})
for key in ('synth:gba', 'synth:gba_bram', 'synth'):
    stages.pop(key, None)
manifest_path.write_text(json.dumps(data, sort_keys=True, indent=2) + '\n', encoding='utf-8')
