from pathlib import Path
import plistlib
import shutil
import subprocess

def make_icon(app, feature, symbol):
    iconset = Path('.build') / f'{feature}.iconset'
    resources = app / 'Contents/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    subprocess.run(['.build/DrawIcons', str(iconset), symbol, feature], check=True)
    subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources/'AppIcon.icns')], check=True)

shutil.rmtree('Pocket.app/Contents/Helpers/Pocket Screenshots.app', ignore_errors=True)

make_icon(Path('Pocket.app'), 'pocket', 'square.stack.3d.up')
for feature, title, symbol in [('clipboard', 'Clipboard', 'doc.on.clipboard'), ('notes', 'Notes', 'note.text')]:
    app = Path('Pocket.app/Contents/Helpers') / f'Pocket {title}.app'
    executable = app / 'Contents/MacOS/DockLauncher'
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2('.build/DockLauncher', executable)
    info = dict(CFBundleIdentifier=f'local.pocket.launcher.{feature}', CFBundleName=f'Pocket {title}', CFBundleExecutable='DockLauncher', CFBundlePackageType='APPL', CFBundleIconFile='AppIcon', CFBundleVersion='1', CFBundleShortVersionString='1.0', LSMinimumSystemVersion='13.0', PocketFeature=feature, PocketSymbol=symbol)
    with (app/'Contents/Info.plist').open('wb') as stream:
        plistlib.dump(info, stream)
    make_icon(app, feature, symbol)
