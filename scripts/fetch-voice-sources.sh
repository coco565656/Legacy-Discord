#!/bin/bash
#
# Downloads the pinned voice dependency sources on a modern Mac (the 10.8 test
# Mac's TLS stack cannot fetch from GitHub reliably) and verifies them.
# Then copy the folder to the 10.8 Mac and run scripts/build-voice-deps.sh.
#
#   scripts/fetch-voice-sources.sh <dest-dir>

set -euo pipefail
DEST=$1
mkdir -p "$DEST"
cd "$DEST"

fetch() {
    local url=$1 file=$2 sha=$3
    [ -f "$file" ] || curl -fsSL -o "$file" "$url"
    echo "$sha  $file" | shasum -a 256 -c -
}

fetch https://github.com/openssl/openssl/releases/download/openssl-3.0.15/openssl-3.0.15.tar.gz \
      openssl-3.0.15.tar.gz 23c666d0edf20f14249b3d8f0368acaee9ab585b09e1de82107c66e1f3ec9533
fetch https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz \
      opus-1.5.2.tar.gz 65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
mkdir -p nlohmann
fetch https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp \
      nlohmann/json.hpp 9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6

# mlspp at the commit libdave pins (libdave/cpp/vcpkg-alts/openssl_3).
[ -d mlspp ] || git clone -q https://github.com/cisco/mlspp.git
(cd mlspp && git fetch -q origin && git checkout -q 1cc50a124a3bc4e143a787ec934280dc70c1034d)
[ -d libdave ] || git clone -q https://github.com/discord/libdave.git
(cd libdave && git log --oneline -1)
echo "Sources ready in $DEST"
