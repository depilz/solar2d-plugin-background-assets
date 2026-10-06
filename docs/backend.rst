The backend interface
=====================

``plugin.backgroundAssets`` is one Lua source file, the *front*, over a *backend*. The front is the whole public API.
The backend supplies Apple's raw Background Assets data and the few things Lua cannot do. This page is the contract
between them, for whoever writes a backend: the iOS backend in Objective-C, and the Simulator's folder emulator in
Lua.

The files
---------

``lua/plugin_backgroundAssets.lua``
    The front. Every platform runs this one file unchanged.

``lua/plugin_backgroundAssets_backend.lua``
    The Simulator's backend: the folder emulator. It returns the backend table of the emulator module, so the backend
    and the app's ``configure`` share one set of settings and one emulated device.

``lua/plugin_backgroundAssets_emulator.lua``
    The emulator module, ``plugin.backgroundAssets.emulator``: the emulator's engine, its settings and its emulated
    device, and the app's ``configure`` and ``reset`` (see :doc:`emulator`). It ships only in the Simulator archives.

The front finds its backend in one of two ways:

- **Called as a chunk with a backend table.** The iOS library loads the front from bytes embedded in it and calls the
  chunk with its backend table as the only argument. The chunk returns the library table.
- **Required as a module.** In the Solar2D Simulator, ``require("plugin.backgroundAssets")`` loads the flat
  ``plugin_backgroundAssets.lua`` from the plugin's archive. The chunk then gets the module name, not a table, and
  requires the module ``plugin_backgroundAssets_backend`` itself. That flat name resolves through the Simulator's
  plugin directory on ``package.path``.

What the front owns
-------------------

All of the API's policy lives in the front, and a backend never repeats it:

- argument checks, and the Lua errors that report a wrong argument type;
- the iOS version each call needs, from the backend's ``apiVersion``, and the ``unsupported`` error;
- event tables, pack, status, manifest and progress tables, and error tables with their ``name``;
- 1-based arrays and their sort orders;
- calling the listener, never before the call returns;
- the checks every path call makes: the pack check, through ``assetPackIsAvailableLocally`` from iOS 26.4 and through
  the removed-pack record below it, and the file check, through ``fileExists``;
- the removed-pack record itself: which ids it holds and when they change.

A backend gets only arguments the front has already checked. The front never calls a backend function for a call the
backend's ``apiVersion`` does not reach.

Conventions
-----------

**Raw packs.** A pack is a table ``{ id, downloadSize, version, language, userInfo }``, from ``BAAssetPack``. ``id``
is a string. ``downloadSize`` and ``version`` are numbers. ``language`` is the pack's language or nil (iOS 27).
``userInfo`` is the bytes as a Lua string, or nil. The front copies these five fields, so extra fields are ignored.

**Raw errors.** An error is a table ``{ domain, code, message, assetPackId }``:

- ``domain`` is the ``NSError`` domain string, e.g. ``"BAManagedErrorDomain"`` or ``"NSCocoaErrorDomain"``;
- ``code`` is its code, as a number;
- ``message`` is its localized description;
- ``assetPackId`` is the value for ``BAAssetPackIdentifierErrorKey``, when the error has one.

The front adds ``name`` from the domain and code. A backend may report errors in the plugin's own domain,
``"plugin.backgroundAssets"``, with the codes 1 ``unsupported``, 2 ``invalidArgument``, 3 ``assetPackNotAvailable``
and 4 ``fileNotFound``.

**Asynchronous functions** take ``done`` as their last argument. The backend calls it exactly once:

- ``done(result)`` on success;
- ``done(nil, error)`` on failure, with a raw error.

The call happens on the main thread, in the Corona main Lua state, and may come before the backend function returns:
the front then defers the listener with ``defer``. After that one call, the backend drops its reference to ``done``.

**Synchronous functions** return their result, or ``nil, error`` with a raw error.

**Packs given to the backend** are passed by id. When Apple's method takes a ``BAAssetPack``, the backend resolves the
object by id from the packs it last received. If it has none for that id, it fetches the pack first, through the
manifest on iOS 27.

Every backend
-------------

A backend whose ``apiVersion`` is nil needs only these two functions. Together they are the smallest backend this
interface allows; over it, the front reports every call as unsupported.

``info()``
    Returns ``{ platform, osVersion, apiVersion, hosting }``. The front calls it once, when it loads.

    - ``platform``: ``"ios"``, ``"mac-sim"`` or ``"win32-sim"``.
    - ``osVersion``: the OS version as a string, e.g. ``"26.4"``, or nil when the backend does not know it.
    - ``apiVersion``: the iOS version whose Background Assets calls this backend provides, as a string, or nil when it
      provides none. On iOS it is the highest of 26.0, 26.4 and 27.0 that the OS reaches. Below ``"26.0"`` the front
      treats every call as unsupported, as for nil. An emulator names the iOS version it emulates.
    - ``hosting``: ``"apple"`` when the app's Info.plist sets ``BAUsesAppleHosting``, ``"self"`` when it does not, and
      nil when ``BAHasManagedAssetPacks`` is not set.

``defer(fn)``
    Calls ``fn()`` on a later turn of the main loop, in the Corona main Lua state. The front uses it so that a listener
    never runs before its call returns. The emulator uses ``timer.performWithDelay``.

The Background Assets calls
---------------------------

A backend whose ``apiVersion`` reaches a call provides that call's functions. The minimum versions are those in the
front's ``MINIMUM`` table. Each function wraps the Apple method named beside it.

``setDelegate(handler)``
    Sets the download delegate (``BAManagedAssetPackDownloadDelegate``). The front calls it once, when it loads on a
    backend whose ``apiVersion`` reaches ``setDelegate``, whether or not the app sets a delegate. It never passes
    ``nil``: the front needs ``"finished"`` events for the removed-pack record. The app's ``setDelegate`` only changes
    where the front sends events and never reaches the backend. The backend holds its delegate object strongly, because
    the manager holds its delegate weakly. For each delegate callback, it calls ``handler(download)`` on the main
    thread with ``{ phase, assetPack, progress, error }``:

    - ``phase`` is ``"began"``, ``"paused"``, ``"progress"``, ``"finished"`` or ``"failed"``;
    - ``assetPack`` is a raw pack;
    - ``progress`` (phase ``"progress"``) is ``{ fractionCompleted, completedUnitCount, totalUnitCount }``;
    - ``error`` (phase ``"failed"``) is a raw error.

``getAssetPack(id, done)``
    ``getAssetPackWithIdentifier:completionHandler:``. ``done(pack)``.

``getAllAssetPacks(done)``
    ``getAllAssetPacksWithCompletionHandler:``. ``done(packs)``, an array in any order.

``getManifest(done)``
    ``getManifestWithCompletionHandler:``. ``done(manifest)`` with ``{ assetPacks, primaryLanguage,
    availableLanguages, resolvedLanguage, localizedAssetPacks }``. The two pack fields are arrays of raw packs in any
    order. ``availableLanguages`` is an array in Apple's order. Fields the OS does not give are nil.

``getStatusOfAssetPack(id, done)``, ``getStatusRelativeToAssetPack(id, done)``, ``getLocalStatusOfAssetPack(id, done)``
    ``getStatusOfAssetPackWithIdentifier:``, ``getStatusRelativeToAssetPack:`` (the pack resolved by id) and
    ``getLocalStatusOfAssetPackWithIdentifier:``, each with its completion handler. ``done(bits)``, the
    ``BAAssetPackStatus`` value as a number.

``assetPackIsAvailableLocally(id)``
    ``assetPackIsAvailableLocallyWithIdentifier:``. Returns a boolean.

``ensureLocalAvailability(id, requireLatestVersion, done)``
    ``requireLatestVersion`` is a boolean. When it is ``true``,
    ``ensureLocalAvailabilityOfAssetPack:requireLatestVersion:completionHandler:``; when ``false``,
    ``ensureLocalAvailabilityOfAssetPack:completionHandler:``. ``done(true)``.

``ensureLocalAvailabilityOfAssetPacks(ids, requireLatestVersions, done)``
    ``ensureLocalAvailabilityOfAssetPacks:requireLatestVersions:completionHandler:``. ``done(true)``. On failure, the
    raw error also carries ``successes``, an array of raw packs, and ``failures``, an array of ``{ assetPack, error }``
    with a raw pack and a raw error. Both come from the error's userInfo. Read those keys by their string values, so the
    library has no reference to the iOS 27 key symbols.

``checkForUpdates(done)``
    ``checkForUpdatesWithCompletionHandler:``. ``done({ updatingIdentifiers, removedIdentifiers })``, two arrays of
    ids in any order.

``removeAssetPack(id, done)``
    ``removeAssetPackWithIdentifier:completionHandler:``. ``done(true)``. Path lookups started while a remove is in
    flight wait for it (see below), so the backend signals the remove's completion before it hops to the main thread.

``getLocallyAvailableLanguages(done)``
    ``getLocallyAvailableLanguagesWithCompletionHandler:``. ``done(languages)``, an array in Apple's order.

``reconcilePreferredLanguages(done)``
    ``reconcilePreferredLanguagesWithCompletionHandler:``. ``done(true)``.

``getResolvedLanguage()`` and ``setResolvedLanguage(language or nil)``
    Read and write the manager's ``resolvedLanguage``.

Path primitives
---------------

The front's path calls (``urlForPath``, ``pathForFile``, ``contentsAtPath`` and ``fileForPath``) make their checks
first, then call these functions. ``path`` is the path relative to the packs' shared file namespace, as the app
gave it. ``language`` is nil, or a language identifier for Apple's iOS 27 ``asLocalizedForLanguage:`` variants.
``assetPackId`` is nil or a pack id. The front never passes both ``language`` and ``assetPackId``.

``urlForPath(path, language)``
    ``URLForPath:error:``, or ``URLForPath:asLocalizedForLanguage:error:``. Returns the file's path on disk as a plain
    path string, not a ``file://`` URL.

``fileExists(file)``
    Returns whether a file exists at that path on disk (``fileExistsAtPath:``).

``contentsAtPath(path, assetPackId, language)``
    ``contentsAtPath:searchingInAssetPackWithIdentifier:options:error:`` with no reading options, or its
    ``asLocalizedForLanguage:`` variant. Returns the contents as a Lua string.

``fileForPath(path, assetPackId, language)``
    ``fileDescriptorForPath:searchingInAssetPackWithIdentifier:error:``, or its ``asLocalizedForLanguage:`` variant.
    Returns an open Lua 5.1 file handle on the descriptor (``fdopen``, with the ``LUA_FILEHANDLE`` metatable). When
    wrapping fails, it closes the descriptor and returns ``nil, error``.

``link(path, file)``
    Makes ``file``, which ``urlForPath`` returned for ``path``, loadable by ``display.newImage`` and
    ``audio.loadSound``. Returns ``filename, baseDirectory``, which ``pathForFile`` hands to the app unchanged.

    - On iOS, the backend keeps a symbolic link under ``system.CachesDirectory`` to a folder that holds the file, and
      returns the filename through that link with ``system.CachesDirectory``. That base directory is
      ``Library/Caches/Caches``, so the link goes where it points. The backend picks the link layout: one link per pack
      folder, or one for the namespace root. It creates a link when needed, replaces it when its target changes, and
      recreates it when the OS has purged the caches. It never copies a pack file. The filename stays valid across
      launches as long as the pack is local.
    - A backend whose files are loadable where they are, such as a Simulator emulator over local folders, may return
      the file's real path relative to a base directory that loads it, and make no link.

``unlinkAssetPack(id)``
    Called after a successful ``removeAssetPack``. Deletes every link that serves only that pack. With a single link
    for the namespace root, it does nothing.

The transient 513
~~~~~~~~~~~~~~~~~

On iOS, ``URLForPath`` sometimes fails with ``NSCocoaErrorDomain`` 513 for a few milliseconds after a pack's state
changes. Every native path lookup (``urlForPath``, ``contentsAtPath``, ``fileForPath``) handles it in the backend:

1. If a ``removeAssetPack`` started by the plugin is still in flight, wait for its completion, up to 250 ms.
2. Call Apple's lookup.
3. On ``NSCocoaErrorDomain`` 513, retry up to 4 more times with 5 ms sleeps, within a 50 ms total budget.
4. When the budget runs out, return the 513 as a raw error.

These numbers are named constants in one place in the backend. The front sees only the result.

The removed-pack record
-----------------------

The record lists the pack ids this plugin removed that have not been made local again. Below iOS 26.4, where
``assetPackIsAvailableLocallyWithIdentifier:`` does not exist, it decides the pack check. The front keeps it up to
date:

- a successful ``removeAssetPack`` adds the id;
- a successful ``ensureLocalAvailability`` or a ``"finished"`` download clears it.

A download that finishes while the app is not running never reaches the front, so ``ensureLocalAvailability`` is the
dependable way to clear the record.

The backend only stores the record, across launches, in plugin-owned storage under the app's own container:

``loadRemovedAssetPacks()``
    Returns the stored ids as an array, or an empty array when nothing is stored. The front calls it once, the first
    time it needs the record.

``saveRemovedAssetPacks(ids)``
    Stores the ids, a sorted array, in place of what was stored. The front calls it only when the record changes.
