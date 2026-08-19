# Legacy Discord for Intel Mac

Legacy Discord is a native AppKit Discord client focused on Intel Macs running
OS X Mountain Lion and Mavericks. It is based on the GPL-3.0 Discord Lite
project by dosdude1 and keeps the original copyright and license notices.

## Platform priorities

1. OS X 10.8.5 Mountain Lion on 64-bit Intel
2. OS X 10.9.5 Mavericks on 64-bit Intel
3. Mac OS X 10.7.5 Lion on 64-bit Intel
4. OS X 10.10 and 10.11 where compatibility comes for free

The project intentionally no longer builds PowerPC or 32-bit Intel slices. This
lets new UI work use APIs available to the target Intel systems without growing
the already complex legacy build matrix.

## Current baseline

The imported baseline already provides native server and DM navigation, text
messages, attachments, replies, editing, deletion, typing indicators, 2FA and
CAPTCHA handling. This fork starts by:

- moving the HTTP and Gateway endpoints from API v6 to v10;
- storing the user token in the macOS Keychain instead of user defaults;
- removing token values from diagnostic logging;
- enabling TLS peer and hostname verification with a bundled Mozilla CA set;
- building a single x86_64 application with a 10.7 deployment target.

The next feature milestones are tracked in [docs/ROADMAP.md](docs/ROADMAP.md).
Mountain Lionでの初回ビルドは
[Xcode 5.0.2向け手順](docs/BUILDING_XCODE_5_JA.md)を参照してください。

## Building

The current project is an Objective-C, non-ARC AppKit application. Open
`Discord Lite.xcodeproj` in Xcode with a macOS SDK that still permits a 10.7
deployment target. The recommended release test matrix is:

- Xcode 5.1.1 with the 10.9 SDK for the Mavericks test machine;
- a modern Xcode installation with legacy SDK support for development builds;
- final binaries tested directly on 10.8.5 and 10.9.5.

The bundled curl/OpenSSL libraries are used for current TLS and WebSocket
support. Never add an account token, captured request, Keychain export or test
account credentials to this repository.

Run `scripts/verify-source.sh` after protocol or project-setting changes. It
checks the project files, x86_64 library slices, transport safety settings and
Objective-C syntax when the local Command Line Tools SDK is available.

An SSH-accessible Mountain Lion test Mac can build and return artifacts with
`scripts/remote-build-mountainlion.sh`.

## Upstream and license

The original project README is preserved as
[UPSTREAM_README.md](UPSTREAM_README.md). The complete project is distributed
under GPL-3.0; see [LICENSE](LICENSE).
