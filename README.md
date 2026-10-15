# Legacy Discord for Intel Mac

Legacy Discord is a native AppKit Discord client focused on 64-bit Intel Macs
running Mac OS X Snow Leopard through OS X Mountain Lion. OS X Mavericks is a
best-effort target. It is based on the GPL-3.0 Discord Lite project by dosdude1
and keeps the original copyright and license notices.

The visual target is the official Discord client's dark theme and layout,
reproduced with lightweight native AppKit code rather than a web view. Discord
Messenger is a reference for feature coverage only. Snow Leopard is the
primary rendering and layout validation target.

## Platform priorities

1. Mac OS X 10.6.8 Snow Leopard on 64-bit Intel (minimum)
2. Mac OS X 10.7.5 Lion on 64-bit Intel
3. OS X 10.8.5 Mountain Lion on 64-bit Intel (maximum formal target)
4. OS X 10.9.5 Mavericks on 64-bit Intel where practical

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
- building a single x86_64 application with a 10.6 deployment target.

The next feature milestones are tracked in [docs/ROADMAP.md](docs/ROADMAP.md).
The [Discord Messenger comparison](docs/DISCORD_MESSENGER_PORT.md) records which
Windows-client features are already present and which have been adapted for
this native Mac client.
レガシーOS向けの初回ビルドは
[Xcode 4.6.3 / 5.0.2向け手順](docs/BUILDING_XCODE_5_JA.md)を参照してください。

## Building

The current project is an Objective-C, non-ARC AppKit application. Open
`Discord Lite.xcodeproj` in Xcode with an OS X SDK that still permits a 10.6
deployment target. The intended release-validation matrix is:

- an Xcode 4.6.3 / OS X 10.8 SDK build with deployment target 10.6;
- direct launch and feature tests on 10.6.8, 10.7.5, and 10.8.5;
- a separate best-effort launch and feature test on 10.9.5;
- modern Xcode only for the isolated DevLocal and login-preview builds.

The bundled curl/OpenSSL libraries are used for current TLS and WebSocket
support. Never add an account token, captured request, Keychain export or test
account credentials to this repository.

Run `scripts/verify-source.sh` after protocol or project-setting changes. It
checks the project files, x86_64 library slices, transport safety settings and
Objective-C syntax when the local Command Line Tools SDK is available.

Snow Leopard compatibility work and its remaining validation boundary are
recorded in [docs/SNOW_LEOPARD_COMPATIBILITY.md](docs/SNOW_LEOPARD_COMPATIBILITY.md).

## Upstream and license

The original project README is preserved as
[UPSTREAM_README.md](UPSTREAM_README.md). The application source is distributed
under GPL-3.0; see [LICENSE](LICENSE).

Unicode emoji use locally bundled [Twemoji 17.0.3](https://github.com/jdecked/twemoji)
PNG graphics, licensed under CC BY 4.0. Their license and attribution are in
`Discord Lite/Twemoji72/LICENSE-GRAPHICS` and `SOURCE.txt`. The searchable 3,781
entry catalog uses Unicode Emoji 16.0 names and sequences, with the Unicode
license in the same resource directory. Images are shared by messages,
reactions, the composer, and navigation labels.

`sh scripts/check-twemoji-renderer.sh` checks every catalog image and Unicode
sequence handling without opening a test UI or connecting to Discord.
