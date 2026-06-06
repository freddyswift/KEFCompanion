# KEF Companion

Unofficial macOS menu bar companion for KEF wireless speakers.

## Download

Download the latest `KEFCompanion-*.dmg` from
[GitHub Releases](https://github.com/freddyswift/KEFCompanion/releases).

Prebuilt releases currently require macOS 14 or later on Apple Silicon.

Open the DMG, then drag `KEF Companion.app` into `Applications`.

## Compatibility

KEF Companion works with KEF speakers that expose the local HTTP control API:

- KEF LS50 Wireless II
- KEF LSX II / LSX II LT
- KEF LS60

The original LS50 Wireless and LSX gen 1 are not supported.

## Features

- Finds speakers with Bonjour auto-discovery
- Supports manual local host/IP fallback
- Controls power, source, volume, and playback
- Shows now-playing metadata for WiFi and Bluetooth playback
- Can route keyboard volume keys to the speaker, or auto-switch them back to macOS when playback is paused
- Sends Wake-on-LAN when a speaker MAC address is discovered

## Permissions

On first launch or discovery, macOS may ask for Local Network access. Allow it
so KEF Companion can find and control speakers on your local network.

Keyboard volume-key control is optional. If you choose Auto or KEF mode, macOS
also asks for broad Input Monitoring and Accessibility privileges. KEF Companion
uses those permissions only to handle volume media-key events; it does not log
or store keystrokes.

- Input Monitoring, to receive keyboard volume-key events
- Accessibility, to intercept those events before macOS changes system volume

After changing Input Monitoring or Accessibility, quit and reopen KEF Companion.

## Build From Source

Requires macOS 14 or later and the Xcode/Swift toolchain. Source builds target
the architecture of the Mac doing the build. If you do not have the command line
tools installed, run:

```sh
xcode-select --install
```

Install from source:

```sh
git clone https://github.com/freddyswift/KEFCompanion.git
cd KEFCompanion
make install
```

That builds `KEF Companion.app`, asks before replacing any existing copy in
`/Applications`, installs it, and opens the app.

Update an installed source build:

```sh
git pull --ff-only
make install
```

Source builds do not update themselves from inside the app. The Settings update
button is enabled only for signed release builds with a Sparkle appcast.

Contributor commands:

- `make run` builds and launches the development app.
- `make dev-reset` removes the development app and resets its macOS privacy prompts.
- `make dev-fresh` resets, rebuilds, and launches a fresh development app.
- `make app` stages `dist/KEF Companion.app`.
- `make clean` removes build artifacts.

Maintainer release instructions live in [docs/RELEASING.md](docs/RELEASING.md).

## Privacy

KEF Companion does not include analytics, telemetry, or bundled credentials.

The app uses Bonjour to discover compatible speakers on the local network,
connects to speakers over their local HTTP API, and may read now-playing
metadata from the connected speaker. Manual speaker hosts, the last connected
host, and app settings are stored locally in macOS app preferences. Discovered
MAC addresses are used only for Wake-on-LAN.

Signed release builds use Sparkle to check GitHub Releases for app updates.

## Attribution

This project is based on [nickvanw/KEFControl](https://github.com/nickvanw/KEFControl), licensed under the MIT License.

Third-party dependency notices are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

MIT. See [LICENSE](LICENSE).
