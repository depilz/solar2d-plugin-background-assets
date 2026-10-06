getStatusOfAssetPack()
======================

| **Kind:** asynchronous
| **iOS:** 26.0
| **Apple counterpart:** ``getStatusOfAssetPackWithIdentifier:completionHandler:`` (deprecated in iOS 26.4)
| **See also:** :doc:`getStatusRelativeToAssetPack`, :doc:`getLocalStatusOfAssetPack`, :doc:`status`

Gets the status of the pack with this id.

Syntax
------

.. code-block:: lua

   backgroundAssets.getStatusOfAssetPack(id, listener)

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

   backgroundAssets.getStatusOfAssetPack("mypack", function(event)
       if event.isError then
           print(event.error.name, event.error.message)
       elseif event.status.downloaded then
           print("mypack is downloaded")
       end
   end)
