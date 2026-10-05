The Lua API
===========

``plugin.backgroundAssets`` brings Apple's managed Background Assets API (``BAAssetPackManager``, iOS 26 and later) to
Solar2D apps, for Apple-hosted and self-hosted asset packs. This page is the reference for every call, the tables it
gives, its events and its errors. The app's setup (Info.plist keys, entitlements, the downloader extension) is in
:doc:`setup`.

.. code-block:: lua

   local backgroundAssets = require("plugin.backgroundAssets")

``require`` works on every platform and every iOS version. The library table has ``name``
(``"plugin.backgroundAssets"``), ``publisherId`` (``"com.studycat"``) and the functions below.

Names
-----

The calls' names and every departure from Apple's API are in :doc:`naming`.

Calls and iOS versions
----------------------

A call that is not available on this platform or iOS version gives the ``unsupported`` error. ``getCapabilities()``
tells which calls are available.

.. list-table::
   :header-rows: 1

   * - Lua call
     - Apple counterpart (Objective-C)
     - Min iOS
     - Kind
   * - ``getCapabilities()``
     - none
     - any
     - sync
   * - ``setDelegate(listener or nil)``
     - ``delegate`` property
     - 26.0
     - sync
   * - ``getAssetPack(id, listener)``
     - ``getAssetPackWithIdentifier:completionHandler:`` (deprecated in 27.0)
     - 26.0
     - async
   * - ``getAllAssetPacks(listener)``
     - ``getAllAssetPacksWithCompletionHandler:`` (deprecated in 27.0)
     - 26.0
     - async
   * - ``getManifest(listener)``
     - ``getManifestWithCompletionHandler:``
     - 27.0
     - async
   * - ``getStatusOfAssetPack(id, listener)``
     - ``getStatusOfAssetPackWithIdentifier:completionHandler:`` (deprecated in 26.4)
     - 26.0
     - async
   * - ``getStatusRelativeToAssetPack(assetPack, listener)``
     - ``getStatusRelativeToAssetPack:completionHandler:``
     - 26.4
     - async
   * - ``getLocalStatusOfAssetPack(id, listener)``
     - ``getLocalStatusOfAssetPackWithIdentifier:completionHandler:``
     - 26.4
     - async
   * - ``assetPackIsAvailableLocally(id)``
     - ``assetPackIsAvailableLocallyWithIdentifier:``
     - 26.4
     - sync
   * - ``ensureLocalAvailability(assetPack [, options], listener)``
     - ``ensureLocalAvailabilityOfAssetPack:completionHandler:``; with ``options.requireLatestVersion``,
       ``ensureLocalAvailabilityOfAssetPack:requireLatestVersion:completionHandler:`` (26.4)
     - 26.0
     - async
   * - ``ensureLocalAvailabilityOfAssetPacks(assetPacks [, options], listener)``
     - ``ensureLocalAvailabilityOfAssetPacks:requireLatestVersions:completionHandler:``
     - 27.0
     - async
   * - ``checkForUpdates([listener])``
     - ``checkForUpdatesWithCompletionHandler:``
     - 26.0
     - async
   * - ``removeAssetPack(id [, listener])``
     - ``removeAssetPackWithIdentifier:completionHandler:``
     - 26.0
     - async
   * - ``urlForPath(path [, options])``
     - ``URLForPath:error:``; with ``options.language``, ``URLForPath:asLocalizedForLanguage:error:`` (27.0)
     - 26.0
     - sync
   * - ``contentsAtPath(path [, options])``
     - ``contentsAtPath:searchingInAssetPackWithIdentifier:options:error:``; with ``options.language``, its
       ``asLocalizedForLanguage:`` variant (27.0)
     - 26.0
     - sync
   * - ``fileForPath(path [, options])``
     - ``fileDescriptorForPath:searchingInAssetPackWithIdentifier:error:``; with ``options.language``, its
       ``asLocalizedForLanguage:`` variant (27.0)
     - 26.0
     - sync
   * - ``pathForFile(path [, options])``
     - none
     - 26.0
     - sync
   * - ``getLocallyAvailableLanguages(listener)``
     - ``getLocallyAvailableLanguagesWithCompletionHandler:``
     - 27.0
     - async
   * - ``reconcilePreferredLanguages([listener])``
     - ``reconcilePreferredLanguagesWithCompletionHandler:``
     - 27.0
     - async
   * - ``getResolvedLanguage()``, ``setResolvedLanguage(language or nil)``
     - ``resolvedLanguage`` property
     - 27.0
     - sync

Apple's ``BAAssetPackManifest`` methods ``assetPackWithIdentifier:`` and ``localizedAssetPacksForLanguage:`` (27.0)
are the manifest table's methods ``assetPack`` and ``localizedAssetPacksForLanguage`` (see `Manifest`_).

Not provided: ``BAAssetPack``'s ``download`` and ``downloadForContentRequest:``, the manifest's ``allDownloads`` and
``allDownloadsForContentRequest:`` (all unmanaged API), and the manifest initialisers from a file or data.

Outside iOS 26
~~~~~~~~~~~~~~

Below iOS 26:

- ``require`` works and prints nothing;
- ``getCapabilities().isSupported`` is ``false``;
- every other call gives the ``unsupported`` error: synchronous calls return ``nil, err``, asynchronous calls send it as
  an event;
- ``setDelegate`` is accepted and its listener is never called.

In the Solar2D Simulator (``mac-sim`` and ``win32-sim``), the plugin runs over a folder emulator of Background Assets,
which emulates iOS 27.0 unless the app sets another version. The app configures it through the Simulator-only module
``plugin.backgroundAssets.emulator``: see :doc:`emulator`.

The Xcode iOS Simulator is not supported: the plugin ships no archive for it.

How calls report
----------------

**Listeners.** A listener is a function, or a table with a ``backgroundAssets`` method; the event is its only
argument (after the table, for a table listener).

**Asynchronous calls** send exactly one event to their listener, on the main thread, and never before the call
returns. Their errors, ``unsupported`` included, arrive as that event too. Where the listener is optional, a call made
without one still runs.

**Synchronous calls** return their result, or ``nil, err`` with an `error table <Errors_>`_.

**A wrong argument type** is a programming error: it raises a Lua error naming the argument's position, e.g.
``bad argument #1 to 'getAssetPack' (string expected, got nil)``.

The calls
---------

``getCapabilities()``
    Returns ``{ isSupported, platform, osVersion, hosting, calls }``:

    - ``isSupported``: whether this OS has Background Assets (iOS 26.0 or later); ``true`` in the Simulator, whose
      emulator emulates one (see :doc:`emulator`);
    - ``platform``: ``"ios"``, ``"mac-sim"`` or ``"win32-sim"``;
    - ``osVersion``: the iOS version as a string, e.g. ``"26.4"``; nil in the Simulator;
    - ``hosting``: ``"apple"`` when the app's Info.plist sets ``BAUsesAppleHosting``, ``"self"`` when it does not, nil
      when ``BAHasManagedAssetPacks`` is not set. The app picks its hosting through its setup, not through a Lua call;
      in the Simulator it is the emulator's ``hosting`` setting (see :doc:`emulator`);
    - ``calls``: every call name of this page mapped to ``true`` or ``false`` for this OS, or in the Simulator for the
      iOS version its emulator emulates.

``setDelegate(listener or nil)``
    Sets the one listener for `download events`_; ``nil`` removes it. Returns nothing.

``getAssetPack(id, listener)``
    Gets the pack with this id. Event payload: ``assetPack``.

``getAllAssetPacks(listener)``
    Gets every pack. Event payload: ``assetPacks``.

``getManifest(listener)``
    Gets the app's manifest. Event payload: ``manifest``.

``getStatusOfAssetPack(id, listener)``
    Gets the status of the pack with this id. Event payload: ``status``.

``getStatusRelativeToAssetPack(assetPack, listener)``
    Gets the status relative to this pack table. Event payload: ``status``.

``getLocalStatusOfAssetPack(id, listener)``
    Gets the local status of the pack with this id. Event payload: ``status``.

``assetPackIsAvailableLocally(id)``
    Returns whether the pack with this id is available locally, as a boolean.

``ensureLocalAvailability(assetPack [, options], listener)``
    Makes the pack local, downloading it when needed. ``options.requireLatestVersion = true`` also requires its latest
    version; that needs iOS 26.4, and below it the call gives ``unsupported``. Event payload: ``assetPack``, the table
    given to the call, also on failure.

``ensureLocalAvailabilityOfAssetPacks(assetPacks [, options], listener)``
    Makes every pack of the array local. ``options.requireLatestVersions = true`` also requires their latest versions.
    Event payload: ``assetPacks``, the array given to the call. On failure, the event also carries ``successes`` and
    ``failures`` (see `Multi-pack failure`_).

``checkForUpdates([listener])``
    Checks for pack updates. Event payload: ``updatingIdentifiers`` and ``removedIdentifiers``, arrays of pack ids,
    sorted.

``removeAssetPack(id [, listener])``
    Removes the pack's local files. Event: no payload. After it succeeds, the path calls refuse that pack's files (see
    `Path calls`_).

``urlForPath(path [, options])``
    Returns the file's path on disk, as a plain path string.

``contentsAtPath(path [, options])``
    Returns the file's contents as a Lua string.

``fileForPath(path [, options])``
    Returns the file open for reading, as a Lua file, as ``io.open`` does. The app closes it.

``pathForFile(path [, options])``
    Returns ``filename, baseDirectory``, which load the file through Solar2D:

    .. code-block:: lua

       local filename, baseDirectory = backgroundAssets.pathForFile("mypack/image.png")
       if filename then
           display.newImage(filename, baseDirectory)
       end

    ``baseDirectory`` is ``system.CachesDirectory`` on iOS, and in the Simulator too.
    ``audio.loadSound(filename, baseDirectory)`` works the same way. The filename stays valid across launches as long
    as the pack is local.

``getLocallyAvailableLanguages(listener)``
    Event payload: ``languages``, an array of language identifiers in Apple's order.

``reconcilePreferredLanguages([listener])``
    Reconciles the packs' languages with the user's preferred languages. Event: no payload.

``getResolvedLanguage()``
    Returns the manager's resolved language, or nil when it has none.

``setResolvedLanguage(language or nil)``
    Sets the manager's resolved language; ``nil`` clears it. Returns ``true``.

Path calls
~~~~~~~~~~

``urlForPath``, ``contentsAtPath``, ``fileForPath`` and ``pathForFile`` take a path relative to the root of the packs'
shared file namespace: where the pack's files sit in it is the app's own pack layout. ``options`` holds:

- ``assetPackId``: the pack the file belongs to. ``contentsAtPath`` and ``fileForPath`` pass it to Apple as
  ``searchingInAssetPackWithIdentifier``. For every path call it also turns on the pack check below.
- ``language``: a language identifier, which selects Apple's iOS 27 localized variant. Below iOS 27 it gives
  ``unsupported``.

``assetPackId`` together with ``language`` gives ``invalidArgument``: Apple's localized variants take no pack id.

A removed pack never reports a file. Before it returns a path, a file or contents, each path call checks:

- **the pack**, when ``options.assetPackId`` is given: a pack that is not available locally gives
  ``assetPackNotAvailable``. From iOS 26.4 the plugin asks ``assetPackIsAvailableLocally``. Below it, it keeps its own
  record of the packs it removed, stored across launches: ``removeAssetPack`` adds the id, and a successful
  ``ensureLocalAvailability`` or a ``finished`` download clears it.
- **the file**: a file that is not on disk gives ``fileNotFound`` in the plugin's domain.

On iOS, a path lookup started while a ``removeAssetPack`` is in flight waits for that remove, up to 250 ms. A lookup
that fails with ``NSCocoaErrorDomain`` 513, which Apple's ``URLForPath`` sometimes gives for a few milliseconds after a
pack's state changes, is retried up to 4 times, within 50 ms; after that the 513 is returned as the error.

Tables
------

Asset pack
~~~~~~~~~~

``{ id, downloadSize, version, language, userInfo }``, from ``BAAssetPack``:

- ``id``: the pack id, a string;
- ``downloadSize``, ``version``: numbers;
- ``language``: the pack's language identifier; nil below iOS 27 and for a pack with no language;
- ``userInfo``: the pack's user info bytes as a Lua string, or nil.

A call that takes an ``assetPack`` takes such a table; only its ``id`` is read, so a table ``{ id = "mypack" }`` will
do.

Status
~~~~~~

A table of booleans, one per ``BAAssetPackStatus`` option: ``{ downloadAvailable, updateAvailable, upToDate,
outOfDate, obsolete, downloading, downloaded }``. An option not set is ``false``.

Manifest
~~~~~~~~

``{ assetPacks, primaryLanguage, availableLanguages, resolvedLanguage, localizedAssetPacks }``, from
``BAAssetPackManifest``:

- ``assetPacks``: an array of packs;
- ``primaryLanguage``, ``resolvedLanguage``: language identifiers, or nil;
- ``availableLanguages``: an array of language identifiers, in Apple's order;
- ``localizedAssetPacks``: an array of packs.

Fields the OS does not give are nil, or empty arrays. The table has two methods:

``manifest:assetPack(id)``
    Returns the pack of ``assetPacks`` with this id, or nil.

``manifest:localizedAssetPacksForLanguage(language)``
    Returns an array of the ``localizedAssetPacks`` in this language.

Progress
~~~~~~~~

``{ fractionCompleted, completedUnitCount, totalUnitCount }``, numbers.

Multi-pack failure
~~~~~~~~~~~~~~~~~~

A failed ``ensureLocalAvailabilityOfAssetPacks`` event carries, from the error's user info:

- ``successes``: an array of the packs that were made local;
- ``failures``: an array of ``{ assetPack, error }``, a pack and an `error table <Errors_>`_.

Arrays
~~~~~~

Every array is 1-based. Arrays of packs are sorted by id, then by language; ``failures`` by its packs the same way;
``updatingIdentifiers`` and ``removedIdentifiers`` by id. Arrays of languages keep Apple's order.

Events
------

The event of an asynchronous call is a table:

- ``name``: ``"backgroundAssets"``;
- ``type``: the call's name, e.g. ``"getAssetPack"``;
- ``isError``: ``true`` when the call failed;
- ``error``: an `error table <Errors_>`_, when ``isError`` is true;
- the call's payload, as each call above says: ``assetPack``, ``assetPacks``, ``manifest``, ``status``,
  ``languages``, ``updatingIdentifiers``, ``removedIdentifiers``, ``successes``, ``failures``.

.. code-block:: lua

   backgroundAssets.getStatusOfAssetPack("mypack", function(event)
       if event.isError then
           print(event.error.name, event.error.message)
       elseif event.status.downloaded then
           print("mypack is downloaded")
       end
   end)

Download events
~~~~~~~~~~~~~~~

The listener given to ``setDelegate`` gets an event for each step of a pack's download, from Apple's
``BAManagedAssetPackDownloadDelegate``:

- ``name``: ``"backgroundAssets"``;
- ``type``: ``"download"``;
- ``phase``: ``"began"``, ``"paused"``, ``"progress"``, ``"finished"`` or ``"failed"``;
- ``assetPack``: the pack;
- ``progress``: a `progress table <Progress_>`_, in phase ``"progress"``;
- ``isError``: ``true`` in phase ``"failed"``, with ``error``.

Downloads that finish while the app is not running send no event.

Errors
------

An error is a table ``{ domain, code, name, message, assetPackId }``:

- ``domain``: the error domain, a string;
- ``code``: the error code, a number;
- ``name``: the code's name, for the codes below, else nil;
- ``message``: the error's localized description;
- ``assetPackId``: the pack the error is about, when it has one (``BAAssetPackIdentifierErrorKey``).

.. list-table::
   :header-rows: 1

   * - ``domain``
     - ``code``
     - ``name``
     - Meaning
   * - ``"BAManagedErrorDomain"``
     - 0
     - ``assetPackNotFound``
     - No pack has this id.
   * - ``"BAManagedErrorDomain"``
     - 1
     - ``fileNotFound``
     - No file at this path.
   * - ``"BAManagedErrorDomain"``
     - 2
     - ``localAvailabilityFailure``
     - The pack could not be made local.
   * - ``"plugin.backgroundAssets"``
     - 1
     - ``unsupported``
     - The call does not exist on this platform or iOS version. Also ``fileForPath`` when Lua's ``io`` library is
       missing, and ``pathForFile`` when ``system.CachesDirectory`` has no path.
   * - ``"plugin.backgroundAssets"``
     - 2
     - ``invalidArgument``
     - The arguments cannot be used together, or ``pathForFile`` was given a path that is not a plain relative path.
   * - ``"plugin.backgroundAssets"``
     - 3
     - ``assetPackNotAvailable``
     - A path call's pack is not available locally.
   * - ``"plugin.backgroundAssets"``
     - 4
     - ``fileNotFound``
     - A path call's file is not on disk.

Any other domain or code keeps its ``domain`` and ``code`` with ``name = nil``, e.g. ``NSCocoaErrorDomain`` 513 when
its retries run out, or ``NSPOSIXErrorDomain`` with the ``errno`` when ``fileForPath`` cannot open or wrap the file.

Departures from Apple's API
---------------------------

The ways the API departs from Apple's are listed in :doc:`naming`.
