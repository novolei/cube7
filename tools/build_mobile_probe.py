"""Isolated Android development probe; does not publish or change editor settings.

python tools/build_mobile_probe.py --toolchain H:/GDP/mini-tanks/.tools/android-setup --out <new-directory>
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--toolchain', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--interactive', action='store_true')
    parser.add_argument('--diagnose', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    out = args.out.resolve()
    # Fresh directories only: never mirror/delete a caller's existing checkout.
    out.mkdir(parents=True, exist_ok=False)
    stage = out / 'project'
    runtime = out / 'runtime'
    runtime.mkdir()
    source_engine = args.toolchain / 'godot/Godot_v4.7.1-stable_win64_console.exe'
    engine = runtime / source_engine.name
    shutil.copy2(source_engine, engine)
    gui_engine = source_engine.with_name(source_engine.name.replace('_console', ''))
    shutil.copy2(gui_engine, runtime / gui_engine.name)
    (runtime / '_sc_').touch()
    editor = runtime / 'editor_data'
    editor.mkdir()
    config = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    for key, rel in [('java_sdk_path', 'jdk'), ('android_sdk_path', 'sdk'), ('debug_keystore', 'debug.keystore')]:
        path = (args.toolchain / rel).resolve()
        if not path.exists():
            raise FileNotFoundError(path)
        config += f'export/android/{key} = "{path.as_posix()}"\n'
    config += 'export/android/debug_keystore_user = "androiddebugkey"\nexport/android/debug_keystore_pass = "android"\n'
    (editor / 'editor_settings-4.7.tres').write_text(config, encoding='utf-8')
    files = subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=repo).decode().split('\0')
    for name in sorted(set(files)):
        if not name or name.startswith(('tools/', 'docs/', 'demo/', 'addons/godot_ai/', 'addons/sky_3d/')):
            continue
        src = repo / name
        if src.is_file():
            dst = stage / name
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
    project = stage / 'project.godot'
    text = project.read_text(encoding='utf-8')
    text = re.sub(r'^_mcp_game_helper=.*\n', '', text, flags=re.M)
    text = re.sub(r'^enabled=PackedStringArray.*$', 'enabled=PackedStringArray()', text, flags=re.M)
    if not args.interactive:
        text = text.replace('res://scenes/title.tscn', 'res://scenes/main.tscn')
        main_script = stage / 'scripts/game/main.gd'
        main_text = main_script.read_text(encoding='utf-8')
        anchor = '\tplayer.respawn_at(level.call("spawn_position"), -1, false)'
        assert main_text.count(anchor) == 1
        main_text = main_text.replace(anchor, anchor + '\n\t_attach("res://scripts/debug/prof_break.gd")\n\treturn')
        main_script.write_text(main_text, encoding='utf-8')
        if args.diagnose:
            probe = stage / 'scripts/debug/prof_break.gd'
            probe.write_text(probe.read_text(encoding='utf-8').replace('\t_run()', '\t_diagnose_only()'), encoding='utf-8')
    project.write_text(text, encoding='utf-8')
    # Dynamic paths (fonts, icons, sounds, kit meshes, chapter scripts) need explicit inclusion.
    resources = sorted('res://' + p.relative_to(stage).as_posix() for p in stage.rglob('*') if p.is_file() and p.suffix in {'.gd', '.tscn', '.tres', '.glb', '.png', '.svg', '.ogg', '.ttf', '.gdshader', '.gdshaderinc'})
    template = (args.toolchain / 'godot/editor_data/export_templates/4.7.1.stable/android_debug.apk').resolve()
    preset = '[preset.0]\nname="Android Probe"\nplatform="Android"\nrunnable=true\nexport_filter="resources"\ninclude_filter=""\nexclude_filter=""\nexport_files=PackedStringArray(' + ','.join(json.dumps(x) for x in resources) + ')\nscript_export_mode=2\n\n[preset.0.options]\n'
    preset += f'custom_template/debug="{template.as_posix()}"\n'
    preset += 'gradle_build/use_gradle_build=false\narchitectures/armeabi-v7a=false\narchitectures/arm64-v8a=true\npackage/unique_name="com.novolei.cube7.polishprobe"\npackage/name="Voxel Ark Polish Probe"\nversion/code=1\nversion/name="polish-probe"\npackage/signed=true\nscreen/immersive_mode=true\nscreen/support_small=true\nscreen/support_normal=true\nscreen/support_large=true\nscreen/support_xlarge=true\n'
    (stage / 'export_presets.cfg').write_text(preset, encoding='utf-8')
    for phase, flags in [('import1', ['--editor', '--import', '--quit']), ('import2', ['--editor', '--import', '--quit']), ('runtime_parse', ['--quit-after', '2']), ('export', ['--export-debug', 'Android Probe', str(out / 'cube7-probe.apk')])]:
        log = out / (phase + '.log')
        with log.open('w', encoding='utf-8') as stream:
            result = subprocess.run([str(engine), '--headless', '--path', str(stage), *flags], stdout=stream, stderr=subprocess.STDOUT)
        body = log.read_text(encoding='utf-8')
        if result.returncode or re.search(r'SCRIPT ERROR|Parse Error|Export failed', body):
            raise RuntimeError(f'{phase} failed: {log}\n{body[-3500:]}')
        print(phase + ': OK', flush=True)
    apk = out / 'cube7-probe.apk'
    record = {'mode': 'development probe, not for distribution', 'encrypted': False, 'package': 'com.novolei.cube7.polishprobe', 'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo).decode().strip() + '-dirty', 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(), 'bytes': apk.stat().st_size}
    (out / 'build_record.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(apk, flush=True)


if __name__ == '__main__':
    main()
