"""Package current shader modes, navigation prerequisites and validation evidence."""
from pathlib import Path
import hashlib
import json
import zipfile

files = []
for name in ['player','front_menu','native_presentation','ui_touch','display_preview','thumb_slider',
             'build_chapter_catalog','test_chapter_directory','test_color_modes','test_saturation',
             'test_audio_aspect','test_ui_interactions','test_native_player','test_full_startup']:
    path = Path('godot') / (name+'.gd')
    files.append(path)
    uid = path.with_suffix('.gd.uid')
    if uid.exists():files.append(uid)
files += [Path('godot/content/chapter_catalog.json'),Path('LICENSE'),Path('tools/build_color_modes_patch.py'),
          Path('reports/color-modes-2026-10-22.md'),Path('reports/chapter-directory-2026-10-22.md')]
for name in ['color-modes','color-modes-audio-aspect','color-modes-ui','color-modes-native-player','color-modes-full-startup']:
    path = Path('reports') / (name+'-2026-10-22.log')
    raw = path.read_bytes()
    output = raw.decode('utf16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf8')
    assert 'PASS' in output and not any(token in output for token in ['SCRIPT ERROR','ERROR:','FAIL']),name
    files.append(path)
for name in ['color-modes-settings','color-modes-scene-preview','color-mode-light','color-mode-dark']:
    files.append(Path('reports')/(name+'-2026-10-22.png'))
manifest = {p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
out = Path('build/YosugaMobile-color-modes-2026-10-22.zip')
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
    for path in files:archive.write(path,'YosugaMobile/'+path.as_posix())
    archive.writestr('YosugaMobile/manifest-sha256.json',json.dumps({'files':manifest},indent=2))
with zipfile.ZipFile(out) as archive:
    assert archive.testzip() is None
    for name,expected in manifest.items():
        assert hashlib.sha256(archive.read('YosugaMobile/'+name)).hexdigest()==expected,name
digest = hashlib.sha256(out.read_bytes()).hexdigest()
out.with_suffix('.zip.sha256').write_text(digest+'  '+out.name+'\n',encoding='ascii')
result = {'status':'PASS','files_verified':len(files),'bytes':out.stat().st_size,'sha256':digest}
Path('reports/color-modes-package-validation-2026-10-22.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps(result))
