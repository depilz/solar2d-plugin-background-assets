getStatusRelativeToAssetPack()
==============================

| **Kind:** asynchronous
| **iOS:** 26.4
| **Apple counterpart:** ``getStatusRelativeToAssetPack:completionHandler:``
| **See also:** :doc:`getStatusOfAssetPack`, :doc:`status`

Gets the status relative to this pack.

Syntax
------

.. code-block:: lua

   backgroundAssets.getStatusRelativeToAssetPack(assetPack, listener)

Parameters
----------

- ``assetPack`` (table): an :doc:`asset pack <asset-pack>`; only its ``id`` is read, so ``{ id = "mypack" }`` will do.
- ``listener`` (listener): gets the call's event (see :doc:`events`).

Event
-----

``event.status``: a :doc:`status table <status>`.

Example
-------

.. code-block:: lua

   backgroundAssets.getStatusRelativeToAssetPack({ id = "mypack" }, function(event)
       if not event.isError and event.status.updateAvailable then
           print("mypack has an update")
       end
   end)
