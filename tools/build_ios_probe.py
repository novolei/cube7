"""Build/install an isolated iPhone development probe from committed HEAD.

Reuses Minitanks ship-kit/apple/ios-ship.sh for the unsigned archive, then its
Mac-only signing metadata for development signing. No TestFlight upload.
python tools/build_ios_probe.py --ship-kit <ship-kit> --out <fresh-dir> --device <uuid>
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tarfile
from datetime import datetime, timezone


REMOTE_SCRIPT = r'''#!/bin/sh
set -eu
ROOT="${1:?build root}"
DEVICE="${2:?device UUID}"
SHIP_APPLE_ENV="$ROOT/probe.env" sh "$ROOT/ios-ship.sh" --archive-only
# Paths and IDs only. The private key stays on the Mac.
. "$HOME/mt-build/ship-apple-ios.env"
sign() {
  xcodebuild -exportArchive -archivePath "$ROOT/out/cube7.xcarchive" -exportPath "$ROOT/ipa" \
    -exportOptionsPlist "$ROOT/ExportOptions-development.plist" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    -authenticationKeyPath "$SHIP_ASC_KEY_PATH" -authenticationKeyID "$SHIP_ASC_KEY_ID" \
    -authenticationKeyIssuerID "$SHIP_ASC_ISSUER" > "$ROOT/sign.log" 2>&1
}
sign || { sleep 20; sign; } || { echo IOS_SIGN_FAILED; exit 1; }
IPA="$ROOT/ipa/cube7.ipa"
test -f "$IPA"
xcrun devicectl device install app --device "$DEVICE" "$IPA" --json-output "$ROOT/install.json" > "$ROOT/install.log" 2>&1 \
  || { echo IOS_INSTALL_FAILED; exit 1; }
shasum -a 256 "$IPA" > "$ROOT/ipa.sha256"
echo IOS_PROBE_INSTALLED
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ship-kit', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--device', required=True)
    parser.add_argument('--mac', default='mac-studio')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    stage = out / 'project'
    stage.mkdir()
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo).decode().strip()
    archive = subprocess.check_output(['git', 'archive', '--format=tar', commit], cwd=repo)
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        source.extractall(stage, filter='data')
    for relative in ['tools', 'docs', 'demo', 'addons/godot_ai', 'addons/sky_3d']:
        target = stage / relative
        if target.exists():
            shutil.rmtree(target)  # Fresh staging tree, never the workspace.
    project = stage / 'project.godot'
    text = project.read_text(encoding='utf-8')
    text = re.sub(r'^_mcp_game_helper=.*\n', '', text, flags=re.M)
    text = re.sub(r'^enabled=PackedStringArray.*$', 'enabled=PackedStringArray()', text, flags=re.M)
    text += '\n[editor]\n\nexport/convert_text_resources_to_binary=false\n'
    project.write_text(text, encoding='utf-8')
    resources = sorted('res://' + p.relative_to(stage).as_posix() for p in stage.rglob('*') if p.is_file() and p.suffix in {'.gd', '.tscn', '.tres', '.glb', '.png', '.svg', '.ogg', '.ttf', '.gdshader', '.gdshaderinc'})
    build = datetime.now(timezone.utc).strftime('%Y%m%d%H%M')
    preset = '[preset.0]\nname="iOS Probe"\nplatform="iOS"\nrunnable=false\nexport_filter="resources"\nexport_files=PackedStringArray(' + ','.join(json.dumps(p) for p in resources) + ')\nscript_export_mode=2\n\n[preset.0.options]\n'
    preset += 'architectures/arm64=true\napplication/app_store_team_id="94NP7XQA93"\napplication/bundle_identifier="com.novolei.cube7.polishprobe"\napplication/signature=""\napplication/short_version="0.1.1"\n'
    preset += f'application/version="{build}"\n'
    preset += 'application/min_ios_version="15.0"\napplication/targeted_device_family=0\napplication/export_method_release=1\napplication/export_project_only=true\nuser_data/accessible_from_files_app=true\nuser_data/accessible_from_itunes_sharing=true\nprivacy/tracking_enabled=false\n'
    (stage / 'export_presets.cfg').write_text(preset, encoding='utf-8')
    remote_home = subprocess.check_output(['ssh', '-o', 'BatchMode=yes', args.mac, 'pwd']).decode().strip()
    assert remote_home.startswith('/Users/') and re.fullmatch(r'[A-Za-z0-9/_-]+', remote_home)
    remote = remote_home + '/cube7-probe-' + build + '-' + commit[:8]
    env = {
        'SHIP_PROJECT_DIR': remote + '/project', 'SHIP_BUILD_ROOT': remote,
        'SHIP_GODOT': '/Applications/Godot.app/Contents/MacOS/Godot', 'SHIP_EXECUTABLE': 'cube7',
        'SHIP_PRESET': 'iOS Probe', 'SHIP_TEAM_ID': '94NP7XQA93', 'SHIP_OUT_DIR': remote + '/out',
        'SHIP_ENCRYPTED': '0', 'SHIP_GDIGNORE': 'tools', 'SHIP_STASH_DIR': remote + '/addon-stash',
        'SHIP_STASH_ALL': '', 'SHIP_STASH': '', 'SHIP_REQUIRED': '', 'SHIP_MIN_PCK_MB': '20',
    }
    (out / 'probe.env').write_text(''.join(key + '=' + shlex.quote(value) + '\n' for key, value in env.items()), encoding='utf-8', newline='\n')
    (out / 'run.sh').write_text(REMOTE_SCRIPT, encoding='utf-8', newline='\n')
    (out / 'ios-ship.sh').write_text((args.ship_kit / 'apple/ios-ship.sh').read_text(encoding='utf-8'), encoding='utf-8', newline='\n')
    # Reuse the known development export options without printing signing secrets.
    subprocess.run(['scp', '-q', args.mac + ':mt-build/ExportOptions-development.plist', str(out / 'ExportOptions-development.plist')], check=True)
    bundle = out / 'source.tar.gz'
    with tarfile.open(bundle, 'w:gz') as target:
        for item in [stage, out / 'probe.env', out / 'run.sh', out / 'ios-ship.sh', out / 'ExportOptions-development.plist']:
            target.add(item, arcname=item.name)
    subprocess.run(['ssh', args.mac, 'mkdir ' + shlex.quote(remote)], check=True)
    subprocess.run(['scp', '-q', str(bundle), args.mac + ':' + remote + '/source.tar.gz'], check=True)
    command = 'cd ' + shlex.quote(remote) + ' && tar -xzf source.tar.gz && nohup sh run.sh ' + shlex.quote(remote) + ' ' + shlex.quote(args.device) + ' > build.log 2>&1 < /dev/null &'
    subprocess.run(['ssh', args.mac, command], check=True)
    record = {'commit': commit, 'device': args.device, 'mac': args.mac, 'remote': remote, 'source_sha256': hashlib.sha256(bundle.read_bytes()).hexdigest(), 'encrypted': False, 'channel': 'development, not for distribution'}
    (out / 'build_record.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(json.dumps(record, indent=2), flush=True)


if __name__ == '__main__':
    main()
