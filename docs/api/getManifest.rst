getManifest()
=============

| **Kind:** asynchronous
| **iOS:** 27.0
| **Apple counterpart:** ``getManifestWithCompletionHandler:``
| **See also:** :doc:`manifest`

Gets the app's manifest: its packs and their languages.

Syntax
------

.. code-block:: lua

   backgroundAssets.getManifest(listener)

Parameters
----------

- ``listener`` (listener): gets the call's event (see :doc:`events`).

Event
-----

``event.manifest``: the :doc:`manifest table <manifest>`.

Example
-------

.. code-block:: lua

   backgroundAssets.getManifest(function(event)
       if event.isError then return end
       local pack = event.manifest:assetPack("mypack")
       if pack then
           print(pack.id, pack.downloadSize)
       end
   end)
