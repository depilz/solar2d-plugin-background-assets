checkForUpdates()
=================

| **Kind:** asynchronous
| **iOS:** 26.0
| **Apple counterpart:** ``checkForUpdatesWithCompletionHandler:``
| **See also:** :doc:`getStatusRelativeToAssetPack`

Checks for pack updates.

Syntax
------

.. code-block:: lua

   backgroundAssets.checkForUpdates()
   backgroundAssets.checkForUpdates(listener)

Parameters
----------

- ``listener`` (listener, optional): gets the call's event (see :doc:`events`).

Event
-----

``event.updatingIdentifiers`` and ``event.removedIdentifiers``: arrays of pack ids, sorted.

Example
-------

.. code-block:: lua

   backgroundAssets.checkForUpdates(function(event)
       if event.isError then return end
       for _, id in ipairs(event.updatingIdentifiers) do
           print("updating", id)
       end
   end)
