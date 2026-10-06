setDelegate()
=============

| **Kind:** synchronous
| **iOS:** 26.0
| **Apple counterpart:** the ``delegate`` property
| **See also:** :doc:`events`

Sets the one listener for download events: an event for each step of a pack's download, from Apple's
``BAManagedAssetPackDownloadDelegate``. A new listener replaces the previous one, and ``nil`` removes it.

Syntax
------

.. code-block:: lua

   backgroundAssets.setDelegate(listener)

Parameters
----------

- ``listener`` (listener or nil): gets the download events (see :doc:`events`), or ``nil`` to remove it.

Returns
-------

Nothing.

Notes
-----

- Downloads that finish while the app is not running send no event.
- Below iOS 26 the call is accepted, but its listener is never called.

Example
-------

.. code-block:: lua

   backgroundAssets.setDelegate(function(event)
       if event.phase == "progress" then
           print(event.assetPack.id, event.progress.fractionCompleted)
       elseif event.phase == "failed" then
           print(event.assetPack.id, event.error.name)
       end
   end)
