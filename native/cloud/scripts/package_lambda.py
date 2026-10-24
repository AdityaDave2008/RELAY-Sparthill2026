"""Build Linux arm64 Lambda artifact outside Git; this script does not deploy."""
import argparse
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
cloud = Path(__file__).resolve().parents[1]
output = a.output.resolve()
if cloud.parent == output or cloud.parent in output.parents:
    raise SystemExit('Keep build artifacts outside the checkout')
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='relay-package-') as folder:
    staging = Path(folder)
    subprocess.run([sys.executable, '-m', 'pip', 'install', '--quiet', '--platform', 'manylinux2014_aarch64',
                    '--implementation', 'cp', '--python-version', '3.13', '--only-binary=:all:',
                    '--target', str(staging), '-r', str(cloud / 'requirements.lock')], check=True)
    shutil.copytree(cloud / 'relay_backend', staging / 'relay_backend', ignore=shutil.ignore_patterns('__pycache__'))
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(staging.rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                archive.write(path, path.relative_to(staging))
print('Created Lambda deployment artifact:', output)
