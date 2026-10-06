Events
======

Call events
-----------

An asynchronous call sends exactly one event to its listener, on the main thread, and never before the call returns.
The event is a table:

- ``name``: ``"backgroundAssets"``;
- ``type``: the call's name, e.g. ``"getAssetPack"``;
- ``isError``: ``true`` when the call failed;
- ``error``: an :doc:`error table <errors>`, when ``isError`` is true;
- the call's payload, listed on the call's page: ``assetPack``, ``assetPacks``, ``manifest``, ``status``,
  ``languages``, ``updatingIdentifiers``, ``removedIdentifiers``, ``successes``, ``failures``.

.. code-block:: lua

   backgroundAssets.getStatusOfAssetPack("mypack", function(event)
       if event.isError then
           print(event.error.name, event.error.message)
       elseif event.status.downloaded then
           print("mypack is downloaded")
       end
   end)

Download events
---------------

The listener given to :doc:`setDelegate` gets an event for each step of a pack's download, from Apple's
``BAManagedAssetPackDownloadDelegate``:

- ``name``: ``"backgroundAssets"``;
- ``type``: ``"download"``;
- ``phase``: ``"began"``, ``"paused"``, ``"progress"``, ``"finished"`` or ``"failed"``;
- ``assetPack``: the :doc:`pack <asset-pack>`;
- ``progress``: a :doc:`progress table <progress>`, in phase ``"progress"``;
- ``isError``: ``true`` in phase ``"failed"``, with ``error``.

Downloads that finish while the app is not running send no event.
