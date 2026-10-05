# Background Assets plugin for Solar2D

`plugin.backgroundAssets` (publisher `com.studycat`) brings Apple's managed Background Assets API (`BAAssetPackManager`,
iOS 26 and later) to Solar2D apps, for Apple-hosted and self-hosted asset packs:

```lua
local backgroundAssets = require("plugin.backgroundAssets")
```

The user documentation is at <https://backgroundassets-solar2d.readthedocs.io>.

Every archive loads. On iOS 26 and later the calls reach Background Assets; below iOS 26 every call reports that it is
unsupported. In the Solar2D Simulator (`mac-sim`, `win32-sim`) the plugin runs over a folder emulator of Background
Assets, configured from Lua through `plugin.backgroundAssets.emulator` ([`docs/emulator.rst`](docs/emulator.rst)). The
API reference is [`docs/api.rst`](docs/api.rst); the interface between the Lua front and its backends is
[`docs/backend.rst`](docs/backend.rst).

## Layout

| Path | What it holds |
| --- | --- |
| `plugin/com.studycat/plugin.backgroundAssets/<platform>/data.tgz` | The archives Solar2D reads: `iphone`, `mac-sim`, `win32-sim` |
| `ios/` | The Xcode plugin project for the `iphone` static library |
| `lua/` | The Lua front, embedded in the `iphone` library, and the Simulator's emulator backend and emulator module; all three packed into the `mac-sim` and `win32-sim` archives |
| `extension/` | The downloader extension (Swift source, Xcode project) and `build.sh`, which builds and signs it |
| `Corona/` | The demo project |
| `tools/release/` | Building and packing the archives |
| `tools/demo/` | Building the demo for an iOS device |
| `tests/` | The test harness |
| `docs/` | The documentation (Sphinx) |

## Installing

Install the plugin from the 1.0.0 release with the `build.settings` snippet on the quickstart page of the
[docs](https://backgroundassets-solar2d.readthedocs.io); the archives are on the
[releases page](https://github.com/depilz/solar2d-plugin-background-assets/releases).

## Downloader extension

Managed Background Assets need a downloader extension inside the app's `Extensions/`. `extension/build.sh` builds it
for an app, signs it with the extension's own provisioning profile and writes it into a Solar2D project before the iOS
build, so the build carries it as it is:

```
extension/build.sh --hosting apple|self --app-id <bundle id> --app-group <group id>
  --profile <extension .mobileprovision> --version <CFBundleShortVersionString> --build <CFBundleVersion>
  --project <Solar2D project dir> [--suffix <component>] [--identity <SHA-1>] [--display-name <name>] [--work <dir>]
```

`apple` builds the Apple-hosting flavour (`StoreDownloaderExtension`), `self` the self-hosting one
(`ManagedDownloaderExtension`). The extension's bundle id is `<app id>.<suffix>` (default suffix `BADownloader`), and
its profile, Development or App Store, must carry the app group. The tool replaces `<project>/Extensions/<suffix>.appex`
and checks it with `codesign --verify --deep --strict`; the project and the work dir lie outside the checkout. Exit
codes: 0 built, 1 the build or signing failed, 2 a usage or precondition error. `tests/run.sh extension-sign` builds
and signs both flavours with the profiles in `BA_EXT_DEV_PROFILE` and `BA_EXT_STORE_PROFILE`.

## Building the archives

`tools/release/build.sh` builds the archives from a clean checkout into a directory outside it; copy its
`plugin.backgroundAssets/<platform>/data.tgz` files over `plugin/com.studycat/plugin.backgroundAssets/` and commit them.
`tools/release/pack.sh` is the deterministic packer it uses. Arguments, determinism rules and pinned toolchains are in
[`tools/release/README.md`](tools/release/README.md).

## Tests

`tests/run.sh` runs the default suites; `tests/run.sh --list` lists them, and `tests/run.sh <suite>` runs a named one
(`sim` runs the demo in an isolated Solar2D Simulator, `docs` builds the docs). Run `tests/setup.sh` once per clone to
enable the pre-push hook in `.githooks/`, which runs the tests before every push.

## Demo

`Corona/` is a Solar2D project that runs every call and event of the plugin, one after the other, against the demo
packs `demoondemand` (on demand) and `demoprefetch` (prefetch), and shows each result on screen and as a `[demo]`
console line. In the Simulator it runs over the emulator, which takes the demo packs from `tools/demo/packs/`. Its
`build.settings` carries the
Apple-hosting Background Assets setup: the `BAAppGroupID`, `BAHasManagedAssetPacks` and `BAUsesAppleHosting` Info.plist
keys and the app group and team identifier entitlements; use your own values. Open it in the Solar2D Simulator, or
build it for an iOS device with:

```
tools/demo/ios-build.sh --profile <app profile> --ext-profile <extension profile> --out <dir>
  [--hosting apple|self] [--manifest-url <https URL>] [--build-number <n>]
```

The script builds a copy of `Corona/` in `<dir>/project`: it sets `CFBundleVersion` to `--build-number` (TestFlight
needs a new one on every upload), switches to self-hosting for `--hosting self` (which needs `--manifest-url`), and
writes the downloader extension into the copy's `Extensions/` with `extension/build.sh` before CoronaBuilder runs. The
app id is the app profile's; both profiles carry the app group. A Development app profile gives an `.app` and the
`xcrun devicectl` commands that install and launch it; an App Store one gives an `.ipa` and the `xcrun altool` command
that uploads it. Either way the app must hold `Extensions/BADownloader.appex` and pass `codesign --verify --deep
--strict`. The plugin is taken from `~/Solar2DPlugins` when copied there: copy
`plugin/com.studycat/plugin.backgroundAssets/` to `~/Solar2DPlugins/com.studycat/plugin.backgroundAssets/` first.

The demo packs' sources are in `tools/demo/packs/`: a `ba-package` manifest per pack id and the pack's PNG, WAV and text
file under `<id>/`, the path the demo asks for. `tools/demo/packs.sh` builds them into a directory outside the checkout:

```
tools/demo/packs.sh --out <dir> [--download-base-url <https URL>]
```

It writes `<dir>/<id>.aar`, to upload to App Store Connect or serve with `ba-serve`; with `--download-base-url` it also
writes a self-hosting server root, `<dir>/www/`, holding each pack under its id and `download-manifest.json`.

## License

MIT, see [LICENSE](LICENSE).
