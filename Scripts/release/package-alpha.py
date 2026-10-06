#!/usr/bin/env python3
"""Package an existing arm64 Release build as a fork alpha (macOS only)."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True, help='For example: 1.9.0-alpha.1')
    parser.add_argument('--source-app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+-alpha\.\d+', args.version):
        parser.error('Expected a SemVer alpha version, e.g. 1.9.0-alpha.1')
    source = args.source_app.resolve()
    if not (source / 'Contents/MacOS/LyricsX').is_file():
        parser.error('source-app must be a built LyricsX.app')
    root = Path(__file__).resolve().parents[2]
    commit = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    if subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain', '--untracked-files=no'], text=True).strip():
        parser.error('Commit tracked changes before packaging so provenance is reproducible')
    architectures = subprocess.check_output(['lipo', '-archs', str(source / 'Contents/MacOS/LyricsX')], text=True).strip()
    if architectures != 'arm64':
        parser.error('This packaging recipe expects an arm64-only build')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f'LyricsX-{args.version}-macOS-arm64.zip'
    if archive.exists() or (output / 'SHA256SUMS').exists() or (output / 'release-manifest.json').exists():
        parser.error('Use an empty output folder; existing release files are never overwritten')
    with tempfile.TemporaryDirectory(prefix='.alpha-staging-', suffix='.noindex', dir=output) as temporary:
        staging = Path(temporary)
        app = staging / 'LyricsX(alpha).app'
        run('ditto', str(source), str(app))
        info_path = app / 'Contents/Info.plist'
        with info_path.open('rb') as stream:
            info = plistlib.load(stream)
        assert info['CFBundleIdentifier'] == 'com.JH.LyricsX'
        info.update(CFBundleShortVersionString=args.version,
                    CFBundleName='LyricsX(alpha)', CFBundleDisplayName='LyricsX(alpha)',
                    LX_SOURCE_COMMIT=commit, SUEnableAutomaticChecks=False,
                    SUAllowsAutomaticUpdates=False,
                    SUFeedURL='file:///nonexistent-lyricsx-alpha-feed.xml')
        with info_path.open('wb') as stream:
            plistlib.dump(info, stream, sort_keys=False)
        # This is an ad-hoc fork distribution; do not ship upstream provisioning profiles.
        for profile in app.rglob('embedded.provisionprofile'):
            profile.unlink()
        entitlements = staging / 'entitlements.plist'
        with entitlements.open('wb') as stream:
            plistlib.dump({'com.apple.security.automation.apple-events': True}, stream)
        run('codesign', '--force', '--deep', '--sign', '-', '--entitlements', str(entitlements), str(app))
        run('codesign', '--verify', '--deep', '--strict', str(app))
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive))
        verification = staging / 'verification'
        run('ditto', '-x', '-k', str(archive), str(verification))
        extracted = verification / app.name
        run('codesign', '--verify', '--deep', '--strict', str(extracted))
        with (extracted / 'Contents/Info.plist').open('rb') as stream:
            packaged = plistlib.load(stream)
        assert packaged['CFBundleShortVersionString'] == args.version
        assert packaged['LX_SOURCE_COMMIT'] == commit
        assert packaged['SUAllowsAutomaticUpdates'] is False
        minimum_system = packaged['LSMinimumSystemVersion']
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / 'SHA256SUMS').write_text(f'{digest}  {archive.name}\n')
    manifest = {'version': args.version, 'source_commit': commit, 'architecture': architectures,
                'minimum_macos': minimum_system, 'archive': archive.name, 'sha256': digest,
                'bytes': archive.stat().st_size, 'signature': 'ad-hoc', 'notarized': False,
                'automatic_updates': False}
    (output / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
