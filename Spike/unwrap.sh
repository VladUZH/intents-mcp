#!/bin/sh
# M0 spike: signed .shortcut (AEA1, profile 0, signed not encrypted) -> JSON of Shortcut.wflow.
# Built-in tools only: the signing public key comes from the file's own auth data.
# usage: unwrap.sh <file.shortcut>   (prints JSON to stdout)
set -e
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
python3 - "$1" "$T" <<'PY'
import base64, plistlib, struct, sys
b = open(sys.argv[1], 'rb').read(); t = sys.argv[2]
assert b[:4] == b'AEA1', 'not a signed shortcut'
n = struct.unpack('<I', b[8:12])[0]
auth = plistlib.loads(b[12:12 + n])
if 'SigningPublicKey' in auth:  # contact-signed (people-who-know-me)
    der = bytes.fromhex('3059301306072a8648ce3d020106082a8648ce3d030107034200') + auth['SigningPublicKey']
    open(f'{t}/pub.pem', 'w').write('-----BEGIN PUBLIC KEY-----\n' + base64.encodebytes(der).decode() + '-----END PUBLIC KEY-----\n')
else:  # iCloud-notarized (anyone): key is in the leaf certificate
    open(f'{t}/leaf.der', 'wb').write(auth['SigningCertificateChain'][0])
PY
[ -f "$T/leaf.der" ] && openssl x509 -inform der -in "$T/leaf.der" -pubkey -noout > "$T/pub.pem"
aea decrypt -i "$1" -o "$T/payload.aar" -sign-pub "$T/pub.pem"
mkdir "$T/x" && aa extract -i "$T/payload.aar" -d "$T/x"
plutil -convert json -o - "$T/x/Shortcut.wflow"
