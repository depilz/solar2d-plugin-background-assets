removeAssetPack()
=================

| **Kind:** asynchronous
| **iOS:** 26.0
| **Apple counterpart:** ``removeAssetPackWithIdentifier:completionHandler:``
| **See also:** :doc:`ensureLocalAvailability`, :doc:`path-calls`

Removes the pack's local files.

Syntax
------

.. code-block:: lua

   backgroundAssets.removeAssetPack(id)
   backgroundAssets.removeAssetPack(id, listener)

Parameters
----------

- ``id`` (string): the pack id.
- ``listener`` (listener, optional): gets the call's event (see :doc:`events`).

Event
-----

No payload.

Notes
-----

After it succeeds, the :doc:`path calls <path-calls>` refuse the pack's files: ``assetPackNotAvailable`` when
``options.assetPackId`` holds the pack's id, ``fileNotFound`` when it does not. A later successful
:doc:`ensureLocalAvailability` gives them back.

Example
-------

.. code-block:: lua

   backgroundAssets.removeAssetPack("mypack", function(event)
       if event.isError then
           print(event.error.name, event.error.message)
       end
   end)
