#!/usr/bin/env python3
"""Generate the bundled plugin's standalone catalogs. No host-app dependency."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = ROOT / 'packages/wiredash_video/l10n'
TARGET = ROOT / 'packages/wiredash_video/lib/src/video_messages.g.dart'
LANGUAGES = {'en', 'cs', 'de', 'es', 'fr', 'he', 'it', 'nb', 'nl', 'pl', 'pt', 'ru', 'sv'}


def quoted(value):
    return json.dumps(value, ensure_ascii=False).replace('$', r'\$')


def generate():
    catalogs = {}
    for path in sorted(CATALOGS.glob('video_*.arb')):
        data = json.loads(path.read_text())
        catalogs[data['@@locale']] = {k: v for k, v in data.items() if not k.startswith('@')}
    if set(catalogs) != LANGUAGES:
        raise ValueError(f'Expected all 13 languages, got {sorted(catalogs)}')
    english = catalogs['en']
    slots = lambda value: set(re.findall(r'\{([a-zA-Z]\w*)\}', value))
    for locale, data in catalogs.items():
        if data.keys() != english.keys():
            raise ValueError(f'{locale}: missing or extra message keys')
        for key, value in data.items():
            if not isinstance(value, str) or not value.strip() or slots(value) != slots(english[key]):
                raise ValueError(f'{locale}.{key}: empty text or mismatched placeholders')
    lines = ['// GENERATED CODE — run python3 tool/generate_video_l10n.py',
             '// ignore_for_file: type=lint', '',
             'const videoMessages = <String, Map<String, String>>{']
    for locale, data in catalogs.items():
        lines.append(f'  {quoted(locale)}: {{')
        lines.extend(f'    {quoted(key)}: {quoted(value)},' for key, value in data.items())
        lines.append('  },')
    lines.extend(['};', '', 'const videoMessageIds = <String, String>{'])
    lines.extend(f'  {quoted(value)}: {quoted(key)},' for key, value in english.items() if not slots(value))
    lines.extend(['};', ''])
    return '\n'.join(lines)


if __name__ == '__main__':
    result = generate()
    if '--check' in sys.argv:
        if not TARGET.exists() or TARGET.read_text() != result:
            sys.exit('Video translations are stale. Run python3 tool/generate_video_l10n.py')
    else:
        TARGET.write_text(result)
    print('Video catalogs: 13 complete languages; placeholders and generated output verified.')
