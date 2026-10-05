# tools/release

Release tooling for the plugin archives (`plugin/com.studycat/plugin.backgroundAssets/<platform>/data.tgz`). An archive
holds no build-machine path or user name, and the same sources always pack to the same bytes.

## pack.sh

```
tools/release/pack.sh --mtime EPOCH TREE OUT [MEMBER...]
```

Writes OUT as a gzip'd archive of the named MEMBERs (paths relative to TREE; a directory packs with everything under
it) or, with no MEMBER, of everything in TREE. Same TREE and EPOCH, same bytes:

- POSIX ustar, entries sorted by path, no leading `./`;
- uid and gid 0, empty owner and group names, every mtime EPOCH;
- modes: directories 0755, `.so` and `.dylib` files 0755, every other file 0644; when the packed set holds a
  directory, every entry is 0755;
- gzip level 9, with header mtime 0 and no file name;
- `._*` files (macOS resource forks) are skipped.

It exits 2 and writes nothing on a usage error, a symlink or other non-regular entry, a member outside TREE, or an OUT
equal to or inside a packed member. An existing OUT is replaced only when packing succeeds. Needs `python3` on `PATH`.

## build.sh

```
tools/release/build.sh --out DIR [--commit REV] [PLATFORM...]
```

Builds the archives for the PLATFORMs (`iphone`, `mac-sim`, `win32-sim`; all three by default) into
`DIR/plugin.backgroundAssets/<platform>/data.tgz`:

- `iphone`: `xcodebuild` of `ios/Plugin.xcodeproj` (scheme `plugin_library`, Release, `iphoneos`, `ZERO_AR_DATE=1`),
  then `libplugin_backgroundAssets.a` and `ios/metadata.lua` (as `metadata.lua`) packed flat;
- `mac-sim` and `win32-sim`: the Lua front `lua/plugin_backgroundAssets.lua`, the emulator backend
  `lua/plugin_backgroundAssets_backend.lua` and the emulator module `lua/plugin_backgroundAssets_emulator.lua` packed
  flat, so the two archives are identical.

The checkout holding the script, a plain clone or a worktree, must have no modified, untracked or ignored file, and its
`HEAD^{tree}` must equal `REV^{tree}` (REV defaults to `HEAD`). DIR must be absent or empty, outside the checkout, and
its parent must already exist.
Every archive is packed by pack.sh with the fixed EPOCH 1767225600 (2026-01-01T00:00:00Z), so the bytes depend only on
the sources: neither committing the archives nor a squash merge changes the next build's bytes. `DIR/pack.log` records
the commit, tree, EPOCH, `xcodebuild -version`, the Solar2D build and the sha256 of each archive; `DIR/logs/` holds the
`xcodebuild` log and `DIR/work/` the intermediate files.

build.sh never writes into the checkout (`xcodebuild` builds a `git archive` copy of `HEAD` in `DIR/work/src/`).
It fails when the build left a file there, or an empty directory that was not there before the build.
To release, copy the archives over the tracked ones and commit them:

```
cp -R DIR/plugin.backgroundAssets/. plugin/com.studycat/plugin.backgroundAssets/
```

It exits 0 when every archive is written, 1 when a build step fails (logs in `DIR/logs/`) and 2 on a usage or
precondition error.

## Pinned toolchains

- Xcode 27.0: `DEVELOPER_DIR`, default `/Applications/Xcode.app/Contents/Developer`. Solar2D 3733's
  CoronaBuilder ships the iphoneos 27.0, 26.4 and 18.5 templates.
  Xcode 27.0 accepts no deployment target below iOS 15.0. The project sets 15.0, and the Release configuration
  compiles with `-target arm64-apple-ios13.0`, so the archived library's minimum stays iOS 13.0 (`tests/native`
  checks it); a Debug build comes out at 15.0.
- Solar2D 2026.3733: `CORONA`, default `/Applications/Corona-3733`; the iphone build compiles against its
  `Native/` headers.

Both can be overridden from the environment. The Release build maps the checkout and `CORONA` paths out of the
library's debug info (`-ffile-prefix-map`), so the same sources build the same bytes from any checkout path.
