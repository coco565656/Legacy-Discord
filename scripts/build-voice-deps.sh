#!/bin/bash
#
# Builds the voice stack for OS X 10.8+ (x86_64) on the Mountain Lion test Mac:
#   OpenSSL 3 (static), mlspp + libdave (Discord's DAVE E2EE, C++17) and
#   libopus, combined into one self-contained libLegacyDiscordVoice.dylib that
#   exports only the C APIs (dave.h, opus) and depends only on system libraries.
#
# Run on the 10.8 machine:  scripts/build-voice-deps.sh <source-dir> <out-dir>
# <source-dir> holds openssl-3.0.15.tar.gz, opus-1.5.2.tar.gz, mlspp/
# (cisco/mlspp at 1cc50a1, the commit libdave pins), libdave/ and
# nlohmann/json.hpp. Xcode 5 cannot compile C++17, so MacPorts clang-16 and
# its libc++ (linked statically) are used; the app itself keeps Xcode 5.

set -euo pipefail

SRC=$(cd "$1" && pwd)
OUT=$2
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
WORK="$OUT/work"
PREFIX="$OUT/prefix"
mkdir -p "$WORK" "$PREFIX"

MIN=10.8
CC=/opt/local/bin/clang-mp-16
CXX=/opt/local/bin/clang++-mp-16
LIBCXX=/opt/local/libexec/llvm-16/lib/libc++
JOBS=$(sysctl -n hw.ncpu)
COMMON="-arch x86_64 -mmacosx-version-min=$MIN -O2 -fvisibility=hidden -fPIC"
CXXFLAGS="$COMMON -std=c++17 -stdlib=libc++ -D_LIBCPP_DISABLE_AVAILABILITY -fvisibility-inlines-hidden"

step() { printf '\n== %s\n' "$1"; }

# OpenSSL: static, no assembly (avoids old-assembler issues; voice payloads
# are small), no engines or legacy providers.
if [ ! -f "$PREFIX/lib/libcrypto.a" ]; then
    step "OpenSSL 3.0.15"
    rm -rf "$WORK/openssl-3.0.15"
    tar -xzf "$SRC/openssl-3.0.15.tar.gz" -C "$WORK"
    (cd "$WORK/openssl-3.0.15" &&
     CC="$CC" ./Configure darwin64-x86_64-cc no-shared no-asm no-tests \
        no-engine no-legacy no-module "--prefix=$PREFIX" "--openssldir=$PREFIX/ssl" \
        -mmacosx-version-min=$MIN -fvisibility=hidden >/dev/null &&
     make -j"$JOBS" build_libs >/dev/null &&
     make install_dev >/dev/null) || { echo "OpenSSL build failed" >&2; exit 1; }
    [ -f "$PREFIX/lib/libcrypto.a" ] || { echo "libcrypto.a missing" >&2; exit 1; }
fi

# libopus: plain C, fixed-point off, no examples.
if [ ! -f "$PREFIX/lib/libopus.a" ]; then
    step "Opus 1.5.2"
    rm -rf "$WORK/opus-1.5.2"
    tar -xzf "$SRC/opus-1.5.2.tar.gz" -C "$WORK"
    (cd "$WORK/opus-1.5.2" &&
     CC="$CC" CFLAGS="-arch x86_64 -mmacosx-version-min=$MIN -O2 -fPIC" ./configure --prefix="$PREFIX" --disable-shared --enable-static \
        --disable-doc --disable-extra-programs --disable-dred --disable-osce >/dev/null &&
     make -j"$JOBS" >/dev/null && make install >/dev/null) || { echo "Opus build failed" >&2; exit 1; }
fi

# mlspp and libdave: compiled file by file (no cmake on the test Mac).
step "mlspp + libdave"
OBJ="$WORK/obj"
rm -rf "$OBJ"
mkdir -p "$OBJ/include"
printf '#pragma once\n#define MLS_NAMESPACE mlspp\n' > "$OBJ/include/namespace.h"
M="$SRC/mlspp"
D="$SRC/libdave/cpp"
INCLUDES="-I$OBJ/include -I$PREFIX/include -I$SRC -I$M/include -I$M/lib/bytes/include \
 -I$M/lib/hpke/include -I$M/lib/tls_syntax/include -I$D/includes -I$D/src"
DEFINES="-DDISABLE_GREASE -DWITH_OPENSSL3"
SOURCES=$(ls "$M"/src/*.cpp "$M"/lib/bytes/src/*.cpp "$M"/lib/hpke/src/*.cpp "$M"/lib/tls_syntax/src/*.cpp)
SOURCES="$SOURCES $(ls "$D"/src/*.cpp "$D"/src/utils/*.cpp "$D"/src/mls/*.cpp | grep -v -E 'bindings_wasm|boringssl_cryptor|persisted_key_pair')"
SOURCES="$SOURCES $D/src/mls/persisted_key_pair_null.cpp"
# xargs -P: parallel, and fails if any compilation fails (bash 3.2 has no wait -n).
for file in $SOURCES; do echo "$file"; done > "$OBJ/sources.txt"
export CXX CXXFLAGS DEFINES INCLUDES OBJ SRC
fail=0
xargs -P "$JOBS" -n 1 sh -c 'name=$(echo "$0" | sed "s|$SRC/||; s|/|_|g; s|\.cpp$|.o|"); "$CXX" $CXXFLAGS $DEFINES $INCLUDES -c "$0" -o "$OBJ/$name"' < "$OBJ/sources.txt" || fail=1
[ "$fail" -eq 0 ] || { echo "C++ compilation failed" >&2; exit 1; }

# Transport encryption shim (Voice/ldv_transport.c, next to this script's repo).
REPO=$(cd "$(dirname "$0")/.." && pwd)
"$CC" $COMMON -I"$PREFIX/include" -c "$REPO/Voice/ldv_transport.c" -o "$OBJ/ldv_transport.o"

# One dylib: the DAVE, Opus and transport C APIs are the only exports.
step "libLegacyDiscordVoice.dylib"
cat > "$OBJ/exports.txt" <<EOF
_dave*
_opus_*
_ldv_*
EOF
"$CXX" $CXXFLAGS -dynamiclib -nostdlib++ \
    -install_name @rpath/libLegacyDiscordVoice.dylib \
    -Wl,-exported_symbols_list,"$OBJ/exports.txt" \
    "$OBJ"/*.o -Wl,-force_load,"$PREFIX/lib/libopus.a" "$PREFIX/lib/libcrypto.a" \
    "$LIBCXX/libc++.a" "$LIBCXX/libc++abi.a" \
    -framework Security -framework CoreFoundation \
    -o "$OUT/libLegacyDiscordVoice.dylib"
mkdir -p "$OUT/include/dave" "$OUT/include/opus"
cp "$D"/includes/dave/dave.h "$OUT/include/dave/"
cp "$PREFIX"/include/opus/*.h "$OUT/include/opus/"
cp "$REPO/Voice/ldv_transport.h" "$OUT/include/"
otool -L "$OUT/libLegacyDiscordVoice.dylib"
# The export trie is what other code can link against (nm also lists hidden globals).
xcrun dyldinfo -export "$OUT/libLegacyDiscordVoice.dylib" | awk 'NR>1 {print $NF}' | cut -c1-5 | sort | uniq -c
echo "Done: $OUT/libLegacyDiscordVoice.dylib"
