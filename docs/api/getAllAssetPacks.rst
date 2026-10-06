getAllAssetPacks()
==================

| **Kind:** asynchronous
| **iOS:** 26.0
| **Apple counterpart:** ``getAllAssetPacksWithCompletionHandler:`` (deprecated in iOS 27.0)
| **See also:** :doc:`getAssetPack`, :doc:`asset-pack`

Gets every pack of the app.

Syntax
------

.. code-block:: lua

   backgroundAssets.getAllAssetPacks(listener)

Parameters
----------

- ``listener`` (listener): gets the call's event (see :doc:`events`).

Event
-----

``event.assetPacks``: an array of :doc:`packs <asset-pack>`, sorted by id, then by language.

Example
-------

.. code-block:: lua

   backgroundAssets.getAllAssetPacks(function(event)
       if event.isError then return end
       for _, pack in ipairs(event.assetPacks) do
           print(pack.id, pack.downloadSize)
       end
   end)
