ensureLocalAvailabilityOfAssetPacks()
=====================================

| **Kind:** asynchronous
| **iOS:** 27.0
| **Apple counterpart:** ``ensureLocalAvailabilityOfAssetPacks:requireLatestVersions:completionHandler:``
| **See also:** :doc:`ensureLocalAvailability`

Makes every pack in the array local, downloading them when needed.

Syntax
------

.. code-block:: lua

   backgroundAssets.ensureLocalAvailabilityOfAssetPacks(assetPacks, listener)
   backgroundAssets.ensureLocalAvailabilityOfAssetPacks(assetPacks, options, listener)

Parameters
----------

- ``assetPacks`` (table): an array of :doc:`asset packs <asset-pack>`; only their ``id`` is read.
- ``options`` (table, optional): ``requireLatestVersions = true`` also requires their latest versions.
- ``listener`` (listener): gets the call's event (see :doc:`events`).

Event
-----

``event.assetPacks``: the array given to the call.

On failure, the event also carries, from the error's user info:

- ``successes``: an array of the packs that were made local;
- ``failures``: an array of ``{ assetPack, error }``, a pack and an :doc:`error table <errors>`, sorted by pack.

Example
-------

.. code-block:: lua

   local packs = { { id = "level1" }, { id = "level2" } }
   backgroundAssets.ensureLocalAvailabilityOfAssetPacks(packs, function(event)
       if not event.isError then
           print("every pack is local")
           return
       end
       for _, failure in ipairs(event.failures or {}) do
           print(failure.assetPack.id, failure.error.name)
       end
   end)
