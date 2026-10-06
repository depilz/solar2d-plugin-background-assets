Errors
======

Synchronous calls return ``nil, err`` on failure; asynchronous calls set ``event.isError`` and ``event.error``. Either
way, the error is a table ``{ domain, code, name, message, assetPackId }``:

- ``domain``: the error domain, a string;
- ``code``: the error code, a number;
- ``name``: the code's name for the codes below, and nil otherwise;
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
     - The call does not exist on this platform or iOS version. Also given by :doc:`fileForPath` when Lua's ``io``
       library is missing, and :doc:`pathForFile` when ``system.CachesDirectory`` has no path.
   * - ``"plugin.backgroundAssets"``
     - 2
     - ``invalidArgument``
     - The arguments cannot be used together, or :doc:`pathForFile` was given a path that is not a plain relative
       path.
   * - ``"plugin.backgroundAssets"``
     - 3
     - ``assetPackNotAvailable``
     - A path call's pack is not available locally.
   * - ``"plugin.backgroundAssets"``
     - 4
     - ``fileNotFound``
     - A path call's file is not on disk.

An error with any other domain or code keeps its ``domain`` and ``code``, with ``name = nil``: e.g.
``NSCocoaErrorDomain`` 513 when its retries run out (see :doc:`path-calls`), or ``NSPOSIXErrorDomain`` with the
``errno`` when :doc:`fileForPath` cannot open or wrap the file.

A wrong argument type is a programming error, not an error table: it raises a Lua error naming the argument's
position, e.g. ``bad argument #1 to 'getAssetPack' (string expected, got nil)``.
