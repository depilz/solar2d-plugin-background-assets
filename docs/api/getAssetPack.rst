getAssetPack()
==============

| **Kind:** asynchronous
| **iOS:** 26.0
| **Apple counterpart:** ``getAssetPackWithIdentifier:completionHandler:`` (deprecated in iOS 27.0)
| **See also:** :doc:`getAllAssetPacks`, :doc:`asset-pack`

Gets the pack with this id.

Syntax
------

.. code-block:: lua

   backgroundAssets.getAssetPack(id, listener)

Parameters
----------

- ``id`` (string): the pack id.
- ``listener`` (listener): gets the call's event (see :doc:`events`).

Event
-----

``event.assetPack``: the :doc:`pack <asset-pack>`.

Example
-------

.. code-block:: lua

   backgroundAssets.getAssetPack("mypack", function(event)
       if event.isError then
           print(event.error.name, event.error.message)
       else
           print(event.assetPack.id, event.assetPack.downloadSize)
       end
   end)
