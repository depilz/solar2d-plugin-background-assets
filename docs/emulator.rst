The Simulator emulator
======================

In the Solar2D Simulator (``mac-sim`` and ``win32-sim``), ``plugin.backgroundAssets`` runs over a folder emulator of
Background Assets, written in Lua. Its packs come from local folders described by the ``ba-package`` manifests Apple's
``xcrun ba-package`` takes. Downloads take time and send download events, they can fail offline or for lack of disk
space, and packs can be removed. The app configures the emulator through the module
``plugin.backgroundAssets.emulator``. This page is its reference.

The emulator works under the API of :doc:`api` unchanged: the plugin's library table is the same as on iOS.
``pathForFile`` gives a filename and ``system.CachesDirectory``, as on iOS, so an app's pack-loading code is the same
in the Simulator and on a device.

Requiring the module
--------------------

The module exists only in the Simulator archives: on a device it cannot be required. Require it only in the
Simulator, by ``system.getInfo("environment")``, since ``system.getInfo("platform")`` gives the skin's OS (``"ios"``
by default):

.. code-block:: lua

   if system.getInfo("environment") == "simulator" then
       local emulator = require("plugin.backgroundAssets.emulator")
       emulator.configure({ packsDirectory = "../packs" })
   end
   local backgroundAssets = require("plugin.backgroundAssets")

The module may be required before or after ``plugin.backgroundAssets``, but ``apiVersion`` and ``hosting`` must be set
before the plugin's first ``require``. Its flat name, ``plugin_backgroundAssets_emulator``, reaches the same module.

The module has two functions.

``configure(options)``
    Merges the fields of ``options`` into the emulator's settings. Returns nothing. An unknown field, or a field of the
    wrong type or value, raises a Lua error naming the field. Settings are not stored: the app calls ``configure`` on
    every launch.

``reset()``
    Empties the emulated device (see `The emulated device`_). Returns nothing. Settings are kept.

Options
~~~~~~~

.. list-table::
   :header-rows: 1

   * - Field
     - Value, default
     - Takes effect
   * - ``packsDirectory``
     - The folder of pack sources (see `Pack sources`_): an absolute path, or a path relative to the project folder
       (``system.ResourceDirectory``). Default: none, so no pack exists.
     - At the next call that reads the pack sources.
   * - ``apiVersion``
     - ``"26.0"``, ``"26.4"`` or ``"27.0"``: the iOS version emulated. Default ``"27.0"``.
     - Once, when the plugin loads.
   * - ``hosting``
     - ``"apple"`` or ``"self"``. Default ``"apple"``.
     - Once, when the plugin loads.
   * - ``bytesPerSecond``
     - A number greater than 0: the download speed. Default 5000000.
     - At the next download that starts.
   * - ``downloadDuration``
     - A number of seconds, 0 or more, or ``false`` to clear it. When set, every download takes this long, whatever
       ``bytesPerSecond`` says. Default: not set.
     - At the next download that starts.
   * - ``offline``
     - A boolean. Default ``false``.
     - At once, downloads in flight included (see `Failures`_).
   * - ``freeDiskSpace``
     - The emulated device's free space in bytes, or ``false`` for unlimited. Default unlimited.
     - At once, downloads in flight included (see `Failures`_).
   * - ``offlineError``, ``lowDiskSpaceError``
     - ``{ domain, code, message }``, the error the failure gives in place of its default, or ``false`` to restore the
       default.
     - At the next failure.

``apiVersion`` and ``hosting`` are read once, when ``plugin.backgroundAssets`` loads. After that, calling
``configure`` with a different value for either raises a Lua error saying they must be set before the first
``require("plugin.backgroundAssets")``.

What the plugin reports
-----------------------

Over the emulator, ``getCapabilities()`` gives:

- ``isSupported``: ``true``;
- ``platform``: ``"mac-sim"``, or ``"win32-sim"`` on Windows;
- ``osVersion``: nil;
- ``hosting``: the ``hosting`` setting. It changes nothing else in the emulator;
- ``calls``: the calls the emulated ``apiVersion`` reaches. Emulating ``"26.0"`` or ``"26.4"``, the newer calls give
  ``unsupported``, as on that iOS version.

Pack sources
------------

``packsDirectory`` is a folder of ``ba-package`` manifests and the files they select: the same input ``xcrun
ba-package`` takes. Every ``*.json`` file at its top level is a manifest, one pack each. Other files and the folders
are not manifests. A manifest whose ``platforms`` leaves out ``"iOS"`` is skipped.

A manifest's fields:

- ``assetPackID``: the pack id;
- ``downloadPolicy``: ``essential``, ``prefetch`` or ``onDemand`` (the default), see `Downloads`_;
- ``fileSelectors``: the pack's files, see below;
- ``language``: makes the pack a localized pack of that language;
- ``platforms``;
- ``sourceRoot``: the folder the selectors are relative to, relative to the manifest's folder. Without it, the
  selectors are relative to ``packsDirectory``, as when ``ba-package`` runs from that folder;
- ``userInfo``: an object, which the pack gives as its JSON text.

Every selector kind of Apple's manifest template is read:

.. list-table::
   :header-rows: 1

   * - Selector
     - Adds
   * - ``{ "file": path }``
     - the file, at its path
   * - ``{ "directory": path }``
     - every file under the folder, at its path
   * - ``{ "filePattern": glob }``
     - every file whose path matches the UNIX glob, at its path. ``*`` and ``?`` do not cross ``/``, and ``[...]`` is
       a class
   * - ``{ "fileSource": path, "fileDestination": path }``
     - the file, at the destination path
   * - ``{ "directorySource": path, "directoryDestination": path }``
     - every file under the folder, under the destination path
   * - ``{ "fileExclusion": path }``
     - no file: it leaves out the file at that path

Paths in selectors are relative to the source root. A file's path in the pack is its path in the packs' shared file
namespace, the path the path calls take. For a ``file`` selector it is the path Apple packs it at; for the other kinds
it follows the comments of Apple's template, never checked against a packed pack.

A bad manifest is skipped, with one ``print`` line naming the file and the reason. A manifest is bad when it is not
valid JSON, has no ``assetPackID``, repeats another manifest's ``assetPackID``, has a selector with an unknown key, or
has a selector that names nothing.

A pack, as the calls give it:

- ``id``: the ``assetPackID``;
- ``downloadSize``: the sum of its files' sizes, in bytes;
- ``version``: 1;
- ``language``: the manifest's ``language``, or nil;
- ``userInfo``: the manifest's ``userInfo`` as JSON text, or nil.

Every call that would reach the store on iOS reads the pack sources again: ``getAssetPack``, ``getAllAssetPacks``,
``getManifest``, ``getStatusOfAssetPack``, ``getStatusRelativeToAssetPack``, ``ensureLocalAvailability``,
``ensureLocalAvailabilityOfAssetPacks`` and ``checkForUpdates``. So does the plugin's load. A change to the folder while
the app runs shows at the next such call.

The emulated device
-------------------

The emulator keeps its device under ``system.CachesDirectory``, in ``plugin.backgroundAssets/emulator/``. On a Mac that
is in the project's Simulator sandbox, ``~/Library/Application Support/Corona Simulator/<project>-<hash>/Caches/``. It
holds:

- ``files/Unlocalized/<path>``: the files of the local packs that have no language;
- ``files/<language>/<path>``: the files of the local localized packs;
- ``state.json``: the local packs and their files, whether the device was installed (see `Downloads`_), the resolved
  language, and the plugin's record of the packs it removed (see "Path calls" in :doc:`api`).

The device lasts across Simulator relaunches, as a device keeps its packs.

``reset()`` first ends every download in flight: each sends a ``failed`` download event, and each call waiting on it
gets the error ``{ domain = "NSCocoaErrorDomain", code = 3072, message = "The operation was cancelled." }``. Then it
deletes the whole ``emulator/`` folder. The install-time packs arrive at the next launch, as after a fresh install.

Downloads
---------

**Install-time packs.** When the plugin loads on a device not yet installed, the ``essential`` packs are copied in at
once, with no download event, and the device is marked installed. At every load, each ``prefetch`` pack that is not
local, and that the app has not removed, starts downloading, so an interrupted prefetch completes. Of the localized
packs, only those of the stored resolved language are installed; none while it is nil.

**ensureLocalAvailability.** A pack that is not in the pack sources gives ``assetPackNotFound``. A local pack succeeds
at once. A pack already downloading joins that download, and the call ends when it ends. Otherwise a download starts.
``requireLatestVersion`` changes nothing.

**ensureLocalAvailabilityOfAssetPacks** runs the packs' downloads side by side. It succeeds when they all do;
otherwise its error is the first failure's, and the event carries ``successes`` and ``failures``.

**A download** lasts ``downloadDuration`` seconds, or else ``downloadSize / bytesPerSecond``. The ``setDelegate``
listener gets ``began``, then ``progress`` about every 100 ms, whose ``totalUnitCount`` is the pack's ``downloadSize``.
At the end, the files are copied into a staging folder and moved into place; then come ``finished``, and the call's
event. The timing uses ``timer.performWithDelay``, so downloads run only while the Simulator runs the app.

A download that cannot start, offline or for lack of space, sends no ``began``: it sends ``failed`` with the error, and
the call's event carries the same error.

Failures
--------

.. list-table::
   :header-rows: 1

   * - Failure
     - Default error (``domain``, ``code``, ``message``)
   * - Offline
     - ``"NSURLErrorDomain"``, -1009, ``"The Internet connection appears to be offline."``
   * - Low disk space
     - ``"NSCocoaErrorDomain"``, 640, ``"The operation couldn't be completed because there isn't enough space."``

**Offline.** While ``offline`` is ``true``, ``getAssetPack``, ``getAllAssetPacks``, ``getManifest``,
``getStatusOfAssetPack``, ``getStatusRelativeToAssetPack``, ``checkForUpdates`` and every download that would start
fail with the offline error. Setting ``offline = true`` fails every download in flight at its next progress step. The
local calls keep working: ``assetPackIsAvailableLocally``, ``getLocalStatusOfAssetPack``, the path calls,
``removeAssetPack``, the language calls, and ``ensureLocalAvailability`` of a local pack.

**Low disk space.** With ``freeDiskSpace`` set, it is the device's free space. A download that needs more fails when
it would start. Lowering it below what a download in flight still needs fails that download at its next progress step.
A finished download takes its size from it, and a removed pack gives its size back. The ``essential`` packs installed
at the first launch do not take their size from it: as on iOS, where they arrive with the app, ``freeDiskSpace`` is the
free space with them already on the device, so removing one gives its size back too. ``reset()`` leaves it as it is.

Every failed download carries the pack's id in ``assetPackId``, sends ``failed`` to the ``setDelegate`` listener,
and leaves no partial files.

The two default codes are Foundation's standard ones. That iOS reports these failures with them has never been seen on
a device: code that maps the plugin's errors to "offline" or "low disk space" must not rely on them without checking on
a device.

Status, removal and updates
---------------------------

``assetPackIsAvailableLocally`` is ``true`` exactly when the pack is local.

``getStatusOfAssetPack`` and ``getStatusRelativeToAssetPack`` give:

- ``downloadAvailable`` for a pack that is not local;
- ``downloaded`` and ``upToDate`` for a local pack, and ``obsolete`` too when its manifest is gone;
- ``downloading`` too while the pack downloads.

``getLocalStatusOfAssetPack`` gives ``downloaded`` and ``upToDate`` for a local pack, ``downloading`` while it
downloads, and nothing else. For all three, an id that is neither in the pack sources nor local gives
``assetPackNotFound``.

``removeAssetPack`` first ends the pack's download in flight, as ``reset()`` does. Then it deletes the pack's files,
with the folders it leaves empty, and succeeds; for a known pack that is not local it succeeds too. An id that is
neither in the pack sources nor local gives ``assetPackNotFound``.

``checkForUpdates`` gives no ``updatingIdentifiers``. Its ``removedIdentifiers`` are the local packs whose manifest is
gone from the pack sources; their files are deleted.

``getAssetPack`` gives the pack, and ``getAllAssetPacks`` every pack of the sources, localized ones included.

Path calls
----------

The path calls look a path up on the device:

- with ``options.language``, under ``files/<language>/``;
- without it, under ``files/Unlocalized/``, then under the resolved language's folder when one is set;
- with ``options.assetPackId`` (``contentsAtPath`` and ``fileForPath``), only among that pack's files.

A path not found gives ``fileNotFound`` (``BAManagedErrorDomain``). ``urlForPath`` gives the file's absolute path,
``contentsAtPath`` reads it in binary, and ``fileForPath`` opens it with ``io.open(file, "rb")``.

``pathForFile`` gives the file's name relative to ``system.CachesDirectory``, for example
``plugin.backgroundAssets/emulator/files/Unlocalized/mypack/image.png``, and ``system.CachesDirectory``.
``display.newImage`` and ``audio.loadSound`` load it, as on iOS. The emulator makes no link.

The plugin's own checks run as on iOS: after ``removeAssetPack``, a path call with the removed pack's
``assetPackId`` gives ``assetPackNotAvailable``.

Languages
---------

A manifest's ``language`` makes a localized pack, whose files go under ``files/<language>/``.

``getManifest`` gives the packs with no language as ``assetPacks`` and the localized ones as
``localizedAssetPacks``; ``availableLanguages``, their distinct languages, sorted; ``primaryLanguage`` nil; and the
stored ``resolvedLanguage``.

``getResolvedLanguage`` and ``setResolvedLanguage`` read and write the resolved language on the device.
``getLocallyAvailableLanguages`` gives the languages of the local localized packs, sorted.
``reconcilePreferredLanguages`` succeeds and changes nothing.

Limits
------

- No ``paused`` download event is ever sent.
- Every pack is at version 1: ``requireLatestVersion`` and ``requireLatestVersions`` change nothing,
  ``updateAvailable`` and ``outOfDate`` are never set, and ``checkForUpdates`` never gives an updating pack.
- The plugin loads its record of removed packs once per launch, so after ``reset()`` it keeps it until the next
  launch: emulating iOS 26.0, where that record decides the pack check, a path call with the ``assetPackId`` of a
  pack it removed still gives ``assetPackNotAvailable`` until then.
- ``primaryLanguage`` is always nil.
- The default offline and low-disk-space codes are assumed, never seen on a device (see `Failures`_).
- Also assumed, never seen on a device: that iOS gives a self-hosted pack's ``userInfo`` as JSON text, how a path
  without a language resolves when localized packs are local, and that the error of a failed
  ``ensureLocalAvailabilityOfAssetPacks`` is its first failure's.
- A download in flight when the Simulator relaunches is lost; only ``prefetch`` packs start again.
