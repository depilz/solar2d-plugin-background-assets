getLocalStatusOfAssetPack()
===========================

| **Kind:** asynchronous
| **iOS:** 26.4
| **Apple counterpart:** ``getLocalStatusOfAssetPackWithIdentifier:completionHandler:``
| **See also:** :doc:`getStatusOfAssetPack`, :doc:`assetPackIsAvailableLocally`, :doc:`status`

Gets the local status of the pack with this id.

Syntax
------

.. code-block:: lua

   backgroundAssets.getLocalStatusOfAssetPack(id, listener)

Parameters
----------

- ``id`` (string): the pack id.
- ``listener`` (listener): gets the call's event (see :doc:`events`).

Event
-----

``event.status``: a :doc:`status table <status>`.

Example
-------

.. code-block:: lua

   backgroundAssets.getLocalStatusOfAssetPack("mypack", function(event)
       if not event.isError and event.status.downloaded then
           print("mypack is on the device")
       end
   end)
