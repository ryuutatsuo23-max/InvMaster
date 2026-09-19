"""Build a minimal addon ZIP, including its license and third-party notices.

Usage: python tools/build_release.py OUTPUT_DIRECTORY
"""
from pathlib import Path
import hashlib
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    'invmaster.lua', 'inventory_model.lua', 'transfer.lua', 'route_transfer.lua',
    'stack_sort.lua', 'bag_access.lua', 'ownership_view.lua', 'item_categories.lua',
    'category_data.lua', 'customization.lua', 'withdraw.lua', 'prepare_bridge.lua',
    'currency.lua', 'crystal_trace.lua', 'crystal_withdraw.lua', 'shami.lua',
    'nearby_npc.lua', 'bag_monitor.lua', 'LICENSE',
    'third_party/categories.md', 'third_party/LandSandBoat-LICENSE',
)


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    version = re.search(r"addon\.version\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'",
                        (ROOT / 'invmaster.lua').read_text(encoding='utf-8'))
    if not version:
        raise SystemExit('Cannot determine addon version.')
    # Read the complete allowlist before creating an archive; missing licenses fail.
    contents = {f'invmaster/{name}': (ROOT / name).read_bytes() for name in FILES}
    output = Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f'InvMaster-v{version[1]}.zip'
    # Never silently replace a previously built or published release asset.
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as bundle:
        for name, data in contents.items():
            bundle.writestr(name, data)
    with zipfile.ZipFile(archive) as bundle:
        if set(bundle.namelist()) != set(contents) or bundle.testzip() is not None:
            raise SystemExit('Archive verification failed.')
        for name, data in contents.items():
            if bundle.read(name) != data:
                raise SystemExit(f'Archive content mismatch: {name}')
    print(f'{archive} ({len(contents)} files)')
    print(f'SHA-256: {hashlib.sha256(archive.read_bytes()).hexdigest()}')


if __name__ == '__main__':
    main()
