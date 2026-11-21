#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <encrypted-file.enc>" >&2
    exit 1
fi

OUTNAME=$(basename "$1" .enc).json

# Don't clobber an existing decrypted file without warning.
if [ -e "$OUTNAME" ]; then
    echo "Refusing to overwrite existing file: $OUTNAME" >&2
    exit 1
fi

# Must mirror backup.sh's encryption exactly. Do NOT add -nopad: encryption uses
# default PKCS#7 padding, so decryption must strip it — with -nopad the padding
# bytes are left on the end and the resulting JSON is invalid / unimportable.
openssl enc -aes-256-cbc -pbkdf2 -iter 1000000 -d -in "$1" -out "$OUTNAME"
