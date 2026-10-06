# Changelog

## 1.0.1 — 2026-10-06

- **`urlForPath` in the Windows Simulator.** On win32-sim `urlForPath` now returns a path with `/` separators only;
  it used to join the Simulator's caches folder and the file's name with `\`. `pathForFile`, `contentsAtPath` and
  `fileForPath` work as before, and the paths on macOS do not change.
- **Troubleshooting for the Simulator's plist warnings.** The Troubleshooting page says the Simulator's
  `unrecognized key: settings.iphone.plist.BA…` warnings for the Background Assets keys in `build.settings` are
  expected and harmless.
- **Docs refresh.** The docs move to the Furo theme, with a logo, copy buttons on code blocks, cards on the home page,
  a "How it works" diagram and link previews. The Lua API reference has a page per call, each with its syntax,
  parameters, result and an example, and separate pages for the tables, events, errors and the path calls' shared
  rules. A new Troubleshooting page lists common failures with their fix, and the key gotchas are callouts. The
  quickstart installs from the Solar2D Free Plugin Directory first. The docs suite now checks that every public
  function has its own page.
- **No internal tooling names in the public tree.** The demo's build script, its comments and the test comments no
  longer refer to Studycat's internal tools; `tools/demo/ios-build.sh` says which folder to copy when the installed
  plugin is missing or out of date.

## 1.0.0 — 2026-10-05

- **User docs for Read the Docs.** `docs/` now holds a user guide around the reference pages: a quickstart, the app
  setup (toolchains, Info.plist keys, entitlements, the downloader extension, and what each missing item causes),
  creating, uploading and locally testing asset packs, self-hosting, loading a pack's files, and running in the
  Simulator, plus a naming page that lists every departure from Apple's API. `tests/run.sh docs` gains a coverage row
  that checks every public function, emulator option, error name and download phase has a reference entry, and Read
  the Docs fails the build on any warning.
- **Simulator emulator.** In the Solar2D Simulator the plugin now runs over a folder emulator of Background Assets in
  place of a backend that reported every call as `unsupported`. Its packs come from local folders of `ba-package`
  manifests; downloads take time and send download events, they fail offline or for lack of disk space, and packs can
  be removed. The Simulator-only module `plugin.backgroundAssets.emulator` configures it (`configure`, `reset`), and
  `pathForFile` gives a filename and `system.CachesDirectory` as on iOS. The demo and the `sim` tests run over it.
  Reference: `docs/emulator.rst`.
- **The Background Assets API in Lua.** `plugin.backgroundAssets` is no longer a stub. On iOS 26 and later it exposes
  Apple's managed `BAAssetPackManager` to Lua for Apple-hosted and self-hosted packs: pack lookup, manifest, status,
  local availability, updates, removal, the path calls, iOS 27's language calls and the download delegate, each gated
  on the iOS version its Apple counterpart needs. `getCapabilities` reports what this OS has, and `pathForFile` gives a
  filename that `display.newImage` and `audio.loadSound` load. After `removeAssetPack`, the path calls refuse the
  removed pack's files, and they retry Apple's transient NSCocoaErrorDomain 513. Below iOS 26 `require` works and
  every call reports `unsupported`. One Lua front, embedded in the iOS library and shipped in the
  Simulator archives, holds the API over a backend. BackgroundAssets is weak-linked, so the library still loads from
  iOS 13. Reference: `docs/api.rst`, `docs/backend.rst`.
- **Demo flows and demo packs.** The demo runs every call and event against two demo packs, whose sources and
  `ba-package` script (`tools/demo/packs.sh`) are in `tools/demo/`.
- **Toolchain: Solar2D 3733 and Xcode 27.0.** Every default and every archive moves to them.
- **Release tooling fixes.** `tools/release/build.sh` names its log when the iphone build fails, and
  `tools/demo/ios-build.sh` leaves no `--out` behind when it refuses a run. `tools/release/build.sh` builds the iphone
  archive from a `git archive` copy of the checkout, and fails when the build leaves a new empty directory in the
  checkout.
- **Downloader extension and its build tool.** `extension/` holds the Background Assets downloader extension in two
  flavours, Apple hosting and self-hosting, and `extension/build.sh`, which builds and signs it for any app with the
  extension's own profile and writes it into a Solar2D project's `Extensions/` before the iOS build. It accepts every
  pack the system offers.
- **Repository foundation with a stub plugin.** `plugin.backgroundAssets` ships archives for `iphone`, `mac-sim` and
  `win32-sim`. On every platform `require("plugin.backgroundAssets")` returns a table with only `name` and
  `publisherId`, and prints one line saying the library is not available on this platform; there is no Background
  Assets API yet. The repository also holds the demo project, the release tooling, the test harness and a docs
  skeleton.
