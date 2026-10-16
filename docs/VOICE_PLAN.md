# Voice chat plan (Milestone 3)

Target: OS X 10.8 (Mountain Lion) and later, Intel x86_64. Snow Leopard keeps
the text client only. Test machine: `MBP2012` (MacBookPro9,2, Core i5-3210M,
16 GB, OS X 10.8.5, Xcode 5.0.2, MacPorts clang-16).

## Constraints

- Since 2026-03-01 Discord only allows end-to-end encrypted (DAVE) calls in
  DMs, group DMs, voice channels and Go Live. A client must send
  `max_dave_protocol_version` in voice Identify and implement the DAVE MLS
  handshake (voice opcodes 21-31, some binary) and per-frame media
  encryption (AES-128-GCM, 8-byte tag, 0xFAFA marker). Without DAVE a client
  cannot even listen.
- Transport encryption on top of DAVE: `aead_aes256_gcm_rtpsize` (preferred)
  or `aead_xchacha20_poly1305_rtpsize` (always offered). Voice gateway v8.
- Discord's reference implementation, libdave (C++17, mlspp, OpenSSL 1.1/3
  or BoringSSL), has a C API (`includes/dave/dave.h`). Xcode 5 cannot build
  C++17.

## Toolchain decision

Verified on MBP2012: MacPorts clang-16 builds C++17 for
`-mmacosx-version-min=10.8` when the llvm-16 `libc++.a`/`libc++abi.a` are
linked statically and `_LIBCPP_DISABLE_AVAILABILITY` is set; the binary then
depends only on libSystem.

So the voice stack is built outside Xcode as one self-contained
`LegacyDiscordVoice.dylib` (or static archive) that exports a small C API and
hides every C++ and OpenSSL symbol:

- OpenSSL 3 (static, no shared, 10.8 target)
- mlspp + libdave (static, C API)
- libopus (static)

The Objective-C app (still built with Xcode 5 for 10.6+) loads the voice
library at run time only on 10.8+, so the Snow Leopard binary is unchanged.

## Phase 1 result (2026-10-16)

`scripts/fetch-voice-sources.sh` (on a modern Mac) and
`scripts/build-voice-deps.sh` (on MBP2012) produce
`libLegacyDiscordVoice.dylib` (about 6 MB): OpenSSL 3.0.15 (static, no-asm),
mlspp 1cc50a1, libdave 8de72b1, Opus 1.5.2 and `Voice/ldv_transport.c`. It links
only Security, CoreFoundation and libSystem, targets 10.8, and exports just
45 `dave*`, 80 `opus_*` and 2 `ldv_transport_*` functions (checked with
`dyldinfo -export`). `Voice/voice_selftest.c`, built with Xcode 5's clang,
passes on 10.8.5: DAVE session and MLS key package, Opus round trip and
AES-256-GCM transport seal/open with tamper detection.

On 10.8 dyld did not resolve `@rpath` through `@executable_path` for the
test binary, so the app will `dlopen` the library by absolute path from
`Contents/Frameworks` (only on 10.8+), which also keeps the Snow Leopard
binary free of any link-time dependency on it. libdave logs verbosely
(including key packages) by default; the app must install a log sink.

## Phases 2-4 result (2026-10-16, MBP2012, alone in a channel)

Joined VC_0 in the user's own server twice and left again:
VOICE_STATE_UPDATE (own session) and VOICE_SERVER_UPDATE arrive, the voice
WebSocket identifies (Hello, Ready), UDP IP discovery answers, Select
Protocol with `aead_aes256_gcm_rtpsize` is accepted, Session Description
reports `dave_protocol_version` 1, the MLS key package (op 26) is sent and
the external sender package (op 25) is received. With nobody else in the
channel the gateway sends no proposals, so the MLS group handshake
(27/28/29/30, key ratchets, media decrypt) still needs a second
participant. Leaving produced the expected own voice state with no channel.

Joining the channel named "test" never got an answer from the gateway (no
voice events, and the official client did not show the user), while VC_0
worked with the same build. Identify changes (v10 property names, a
client build number, gateway v9, a Chrome identity) made no difference, so
they were reverted except for the corrected v10 property names and
`preferred_regions` from READY, which the official clients send. The reason
"test" ignores joins is not known yet (likely a channel setting).

## Phases

1. Toolchain: build OpenSSL 3, mlspp, libdave, libopus on MBP2012 with a
   script in `scripts/`; a tiny C test links the result and runs on 10.8.
2. Signalling: Gateway op 4 (join/leave), VOICE_STATE_UPDATE /
   VOICE_SERVER_UPDATE, voice WebSocket v8 (Identify with DAVE version,
   Hello, heartbeat with `seq_ack`, Ready, Resume), reusing the libcurl
   WebSocket code.
3. Transport: UDP socket, IP discovery, Select Protocol, Session Description,
   RTP packets with `aead_aes256_gcm_rtpsize` via OpenSSL.
4. DAVE: feed opcodes 21-31 to libdave's session, send key packages,
   commits and transition-ready; decrypt/encrypt frames with libdave.
5. Listen: Opus decode, jitter buffer and mixing per SSRC, CoreAudio output
   (AUHAL) at 48 kHz stereo.
6. Talk: CoreAudio input, Opus encode (20 ms frames), Speaking op 5,
   silence frames, voice activity or push-to-talk.
7. UI (official layout): click a voice channel to join; connected users
   under the channel with speaking rings; "Voice Connected" panel above the
   account panel with disconnect; working mute/deafen buttons; DM call
   button; Settings > Voice & Video (input/output device, input volume,
   sensitivity, push-to-talk key).
8. Later: Go Live viewing/streaming (video codecs, VideoToolbox on 10.8) is a
   separate milestone.

## Testing

Use the user's own server and DMs only, with explicit permission for every
call that other people could hear.
