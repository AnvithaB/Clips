#!/usr/bin/env python3
"""Sign local builds with a persistent, private, certificate-bound identity.
No system trust settings are changed. Keys stay outside the repository.
"""
import hashlib, os, secrets, subprocess, tempfile
from pathlib import Path

root = Path.home() / 'Library/Application Support/Pocket Development Signing'
root.mkdir(parents=True, exist_ok=True, mode=0o700)
os.chmod(root, 0o700)
keychain = root / 'signing.keychain-db'
password_file = root / 'keychain-password'
certificate = root / 'certificate.der'
def run(*args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        detail = result.stderr.decode(errors='replace') if args[0] == 'codesign' else ''
        raise SystemExit(f'{args[0]} failed while preparing local signing (exit {result.returncode}). {detail}')
    return result
if not keychain.exists():
    password_file.write_text(secrets.token_urlsafe(40))
    os.chmod(password_file, 0o600)
    password = password_file.read_text()
    run('security', 'create-keychain', '-p', password, str(keychain))
    run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
    with tempfile.TemporaryDirectory(dir=root) as tmp:
        folder = Path(tmp)
        conf = folder / 'openssl.conf'
        conf.write_text('''[req]
distinguished_name=dn
x509_extensions=extensions
prompt=no
[dn]
CN=Pocket Local Development
[extensions]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
''')
        key, cert, p12 = folder / 'key.pem', folder / 'cert.pem', folder / 'identity.p12'
        run('openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '3650', '-config', str(conf), '-keyout', str(key), '-out', str(cert))
        run('openssl', 'x509', '-in', str(cert), '-outform', 'DER', '-out', str(certificate))
        run('openssl', 'pkcs12', '-export', '-inkey', str(key), '-in', str(cert), '-out', str(p12), '-passout', 'pass:' + password)
        run('security', 'import', str(p12), '-k', str(keychain), '-P', password, '-T', '/usr/bin/codesign')
password = password_file.read_text()
run('security', 'unlock-keychain', '-p', password, str(keychain))
run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, str(keychain))
fingerprint = hashlib.sha1(certificate.read_bytes()).hexdigest().upper()
app = Path(__file__).resolve().parent.parent / 'Pocket.app'
import plistlib
for target in [*sorted((app / 'Contents/Helpers').glob('*.app')), app]:
    identifier = plistlib.loads((target / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier']
    requirement = f'=designated => identifier "{identifier}" and certificate leaf = H"{fingerprint}"'
    run('codesign', '--force', '--sign', fingerprint, '--keychain', str(keychain), '--requirements', requirement, str(target))
    run('codesign', '--verify', '--strict', str(target))
print('Signed Pocket and helpers with persistent local certificate.')
