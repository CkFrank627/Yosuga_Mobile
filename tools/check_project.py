"""Check the selected source tree and optionally locally supplied game data."""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ['godot/project.godot', 'godot/export_presets.cfg', 'godot/main.tscn',
            'godot/player.gd', 'godot/front_menu.gd', 'godot/native_presentation.gd',
            'godot/story_flow.gd', 'godot/save_store.gd', 'godot/ui_touch.gd',
            'godot/display_preview.gd', 'godot/thumb_slider.gd',
            'godot/fonts/NotoSansCJKsc-Regular.otf', 'godot/fonts/OFL.txt',
            'godot/ui/title-sky-v1.png', 'LICENSE', 'README.md',
            'docs/IOS-EXPORT.zh-CN.md', 'docs/RESOURCES.zh-CN.md']


def safe_path(value):
    return (isinstance(value, str) and value and '\\' not in value and ':' not in value
            and not value.startswith('/') and all(p not in ('', '.', '..') for p in value.split('/')))


def check(require_content=False):
    errors = []
    for name in REQUIRED:
        if not (ROOT / name).is_file():
            errors.append('Missing source: ' + name)
    for script in sorted((ROOT / 'godot').glob('*.gd')):
        for resource in re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)', script.read_text(encoding='utf-8')):
            if not resource.startswith('content/') and not (ROOT / 'godot' / resource).is_file():
                errors.append('Missing script dependency: ' + resource)
    content = ROOT / 'godot/content'
    story = content / 'story.json'
    if require_content:
        if not story.is_file():
            errors.append('Missing game data: godot/content/story.json; see docs/RESOURCES.zh-CN.md')
        else:
            try:
                data = json.loads(story.read_text(encoding='utf-8'))
                if not isinstance(data, dict) or data.get('schema') != 2 or not isinstance(data.get('assets'), dict):
                    raise ValueError('Expected schema 2 with an assets dictionary')
                for asset in data['assets'].values():
                    if not safe_path(asset) or not (content / asset).is_file():
                        errors.append('Missing or unsafe game asset: ' + str(asset))
                if not (content / 'chapter_catalog.json').is_file():
                    errors.append('Missing chapter_catalog.json; see docs/RESOURCES.zh-CN.md')
                print('Assets checked:', len(data['assets']))
            except (ValueError, OSError, TypeError) as exc:
                errors.append('Invalid story.json: ' + str(exc))
    for message in errors[:30]:
        print('ERROR:', message, file=sys.stderr)
    if errors:
        print('PROJECT_CHECK: FAIL; errors=' + str(len(errors)))
        return 1
    print('PROJECT_CHECK: PASS (' + ('source and local game assets' if require_content else 'source; game data not required') + ')')
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-content', action='store_true', help='Also require locally supplied story and all asset paths')
    sys.exit(check(parser.parse_args().require_content))
