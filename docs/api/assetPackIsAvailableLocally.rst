assetPackIsAvailableLocally()
=============================

| **Kind:** synchronous
| **iOS:** 26.4
| **Apple counterpart:** ``assetPackIsAvailableLocallyWithIdentifier:``
| **See also:** :doc:`getLocalStatusOfAssetPack`, :doc:`ensureLocalAvailability`

Tells whether the pack with this id is available locally, without waiting for an event.

Syntax
------

.. code-block:: lua

   local isLocal, err = backgroundAssets.assetPackIsAvailableLocally(id)

Parameters
----------

- ``id`` (string): the pack id.

Returns
-------

``true`` or ``false``; or ``nil, err`` with an :doc:`error table <errors>`, e.g. ``unsupported`` below iOS 26.4.

Example
-------

.. code-block:: lua

   if backgroundAssets.assetPackIsAvailableLocally("mypack") then
       showLevel()
   end
