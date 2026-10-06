The Lua API
===========

``plugin.backgroundAssets`` brings Apple's managed Background Assets API (``BAAssetPackManager``, iOS 26 and later) to
Solar2D apps. Each call has its own page; this one lists them and explains what they have in common. The app's setup
(Info.plist keys, entitlements, the downloader extension) is in :doc:`setup`, and how the calls are named in
:doc:`naming`.

.. code-block:: lua

   local backgroundAssets = require("plugin.backgroundAssets")

``require`` works on every platform and every iOS version. The library table has ``name``
(``"plugin.backgroundAssets"``), ``publisherId`` (``"com.studycat"``) and the calls below.

Calls
-----

A call that is not available on this platform or iOS version gives the ``unsupported`` error.
:doc:`api/getCapabilities` reports which calls are available.

Setup
~~~~~

.. list-table::
   :header-rows: 1
   :widths: 44 10 14 32
   :width: 100%

   * - Call
     - iOS
     - Kind
     - What it does
   * - :doc:`getCapabilities() <api/getCapabilities>`
     - any
     - sync
     - What this device supports
   * - :doc:`setDelegate() <api/setDelegate>`
     - 26.0
     - sync
     - Follows the downloads

Finding packs
~~~~~~~~~~~~~

.. list-table::
   :header-rows: 1
   :widths: 44 10 14 32
   :width: 100%

   * - Call
     - iOS
     - Kind
     - What it does
   * - :doc:`getAssetPack() <api/getAssetPack>`
     - 26.0
     - async
     - One pack, by id
   * - :doc:`getAllAssetPacks() <api/getAllAssetPacks>`
     - 26.0
     - async
     - Every pack
   * - :doc:`getManifest() <api/getManifest>`
     - 27.0
     - async
     - The app's manifest

Status
~~~~~~

.. list-table::
   :header-rows: 1
   :widths: 44 10 14 32
   :width: 100%

   * - Call
     - iOS
     - Kind
     - What it does
   * - :doc:`getStatusOfAssetPack() <api/getStatusOfAssetPack>`
     - 26.0
     - async
     - A pack's status, by id
   * - :doc:`getStatusRelativeToAssetPack() <api/getStatusRelativeToAssetPack>`
     - 26.4
     - async
     - The status relative to a pack
   * - :doc:`getLocalStatusOfAssetPack() <api/getLocalStatusOfAssetPack>`
     - 26.4
     - async
     - A pack's local status
   * - :doc:`assetPackIsAvailableLocally() <api/assetPackIsAvailableLocally>`
     - 26.4
     - sync
     - Whether a pack is local

Downloading and removing
~~~~~~~~~~~~~~~~~~~~~~~~

.. list-table::
   :header-rows: 1
   :widths: 44 10 14 32
   :width: 100%

   * - Call
     - iOS
     - Kind
     - What it does
   * - :doc:`ensureLocalAvailability() <api/ensureLocalAvailability>`
     - 26.0
     - async
     - Makes a pack local
   * - :doc:`ensureLocalAvailabilityOfAssetPacks() <api/ensureLocalAvailabilityOfAssetPacks>`
     - 27.0
     - async
     - Makes several packs local
   * - :doc:`checkForUpdates() <api/checkForUpdates>`
     - 26.0
     - async
     - Checks for pack updates
   * - :doc:`removeAssetPack() <api/removeAssetPack>`
     - 26.0
     - async
     - Removes a pack's files

Files
~~~~~

These are the path calls; :doc:`api/path-calls` covers their options and checks.

.. list-table::
   :header-rows: 1
   :widths: 44 10 14 32
   :width: 100%

   * - Call
     - iOS
     - Kind
     - What it does
   * - :doc:`pathForFile() <api/pathForFile>`
     - 26.0
     - sync
     - A file for ``display.newImage`` and ``audio.loadSound``
   * - :doc:`urlForPath() <api/urlForPath>`
     - 26.0
     - sync
     - A file's path on disk
   * - :doc:`contentsAtPath() <api/contentsAtPath>`
     - 26.0
     - sync
     - A file's contents
   * - :doc:`fileForPath() <api/fileForPath>`
     - 26.0
     - sync
     - A file open for reading

Languages
~~~~~~~~~

.. list-table::
   :header-rows: 1
   :widths: 44 10 14 32
   :width: 100%

   * - Call
     - iOS
     - Kind
     - What it does
   * - :doc:`getLocallyAvailableLanguages() <api/getLocallyAvailableLanguages>`
     - 27.0
     - async
     - The languages available locally
   * - :doc:`reconcilePreferredLanguages() <api/reconcilePreferredLanguages>`
     - 27.0
     - async
     - Matches the user's languages
   * - :doc:`getResolvedLanguage() <api/getResolvedLanguage>`
     - 27.0
     - sync
     - Gets the resolved language
   * - :doc:`setResolvedLanguage() <api/setResolvedLanguage>`
     - 27.0
     - sync
     - Sets the resolved language

Not provided: ``BAAssetPack``'s ``download`` and ``downloadForContentRequest:``, the manifest's ``allDownloads`` and
``allDownloadsForContentRequest:`` (all unmanaged API), and the manifest initialisers from a file or data.

Tables, events and errors
-------------------------

- :doc:`api/asset-pack`: the table that describes a pack.
- :doc:`api/status`: a pack's status, as booleans.
- :doc:`api/manifest`: the app's manifest, with its two methods.
- :doc:`api/progress`: a download's progress.
- :doc:`api/events`: the events of the asynchronous calls, and the download events.
- :doc:`api/errors`: the error table, and every error name.

How calls report
----------------

**Listeners.** A listener is a function, or a table with a ``backgroundAssets`` method. It receives the event as its
only argument (after the table, for a table listener).

**Asynchronous calls** send exactly one event to their listener, on the main thread, and never before the call
returns. Their errors, ``unsupported`` included, arrive as that event too. Where the listener is optional, a call made
without one still runs.

**Synchronous calls** return their result, or ``nil, err`` with an :doc:`error table <api/errors>`.

**A wrong argument type** is a programming error: it raises a Lua error naming the argument's position, e.g.
``bad argument #1 to 'getAssetPack' (string expected, got nil)``.

**Arrays** are 1-based. Arrays of packs are sorted by id, then by language, and ``failures`` by its packs the same way;
arrays of pack ids are sorted. Arrays of languages keep Apple's order.

Outside iOS 26
--------------

Below iOS 26:

- ``require`` works and prints nothing;
- ``getCapabilities().isSupported`` is ``false``;
- every other call gives the ``unsupported`` error: synchronous calls return ``nil, err``, asynchronous calls send it as
  an event;
- ``setDelegate`` is accepted, but its listener is never called.

In the Solar2D Simulator (``mac-sim`` and ``win32-sim``), the plugin runs over a folder emulator of Background Assets,
which emulates iOS 27.0 unless the app sets another version. The app configures it through the Simulator-only module
``plugin.backgroundAssets.emulator``: see :doc:`emulator`.

The Xcode iOS Simulator is not supported: the plugin ships no archive for it.

.. toctree::
   :hidden:

   api/getCapabilities
   api/setDelegate
   api/getAssetPack
   api/getAllAssetPacks
   api/getManifest
   api/getStatusOfAssetPack
   api/getStatusRelativeToAssetPack
   api/getLocalStatusOfAssetPack
   api/assetPackIsAvailableLocally
   api/ensureLocalAvailability
   api/ensureLocalAvailabilityOfAssetPacks
   api/checkForUpdates
   api/removeAssetPack
   api/pathForFile
   api/urlForPath
   api/contentsAtPath
   api/fileForPath
   api/getLocallyAvailableLanguages
   api/reconcilePreferredLanguages
   api/getResolvedLanguage
   api/setResolvedLanguage
   api/path-calls
   api/asset-pack
   api/status
   api/manifest
   api/progress
   api/events
   api/errors
