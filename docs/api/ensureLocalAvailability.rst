ensureLocalAvailability()
=========================

| **Kind:** asynchronous
| **iOS:** 26.0
| **Apple counterpart:** ``ensureLocalAvailabilityOfAssetPack:completionHandler:``; with ``options.requireLatestVersion``, ``ensureLocalAvailabilityOfAssetPack:requireLatestVersion:completionHandler:`` (26.4)
| **See also:** :doc:`ensureLocalAvailabilityOfAssetPacks`, :doc:`setDelegate`, :doc:`pathForFile`

Makes the pack local, downloading it when needed. The listener gets its event once the pack is local or the call has
failed; :doc:`setDelegate`'s listener follows the download meanwhile.

Syntax
------

.. code-block:: lua

   backgroundAssets.ensureLocalAvailability(assetPack, listener)
   backgroundAssets.ensureLocalAvailability(assetPack, options, listener)

Parameters
----------

- ``assetPack`` (table): an :doc:`asset pack <asset-pack>`; only its ``id`` is read, so ``{ id = "mypack" }`` will do.
- ``options`` (table, optional): ``requireLatestVersion = true`` also requires the pack's latest version. It needs iOS 26.4; below that the call gives ``unsupported``.
- ``listener`` (listener): gets the call's event (see :doc:`events`).

Event
-----

``event.assetPack``: the table given to the call, even on failure.

Notes
-----

A successful call lets the :doc:`path calls <path-calls>` give the pack's files again after a :doc:`removeAssetPack`.

Example
-------

.. code-block:: lua

   backgroundAssets.ensureLocalAvailability({ id = "mypack" }, function(event)
       if event.isError then
           print(event.error.name, event.error.message)
       else
           local filename, baseDirectory = backgroundAssets.pathForFile("mypack/image.png")
           display.newImage(filename, baseDirectory)
       end
   end)
