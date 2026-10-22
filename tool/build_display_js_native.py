#!/usr/bin/env python3
"""Build the pinned JSF engine for Linux Flutter tests (Android uses its plugin)."""

import json
import os
from pathlib import Path
import subprocess
from urllib.parse import unquote, urljoin, urlparse


root = Path(__file__).resolve().parent.parent
config = root / '.dart_tool/package_config.json'
packages = json.loads(config.read_text())['packages']
package = next(p for p in packages if p['name'] == 'jsf')
source = Path(unquote(urlparse(urljoin(config.as_uri(), package['rootUri'])).path))
build = root / '.dart_tool/display-js-native'
subprocess.run(['cmake', '-S', str(source / 'src'), '-B', str(build),
                '-DCMAKE_BUILD_TYPE=Release'], check=True)
subprocess.run(['cmake', '--build', str(build), '--parallel', '2'], check=True)
library = build / 'libjsf.so'
assert library.is_file()
print(f'JSF_LIBRARY_PATH={library}')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write(f'JSF_LIBRARY_PATH={library}\n')
