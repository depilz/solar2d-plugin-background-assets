Status
======

A status is a table of booleans, one per ``BAAssetPackStatus`` option:

.. code-block:: lua

   { downloadAvailable, updateAvailable, upToDate, outOfDate, obsolete, downloading, downloaded }

Options that are not set are ``false``. :doc:`getStatusOfAssetPack`, :doc:`getStatusRelativeToAssetPack` and
:doc:`getLocalStatusOfAssetPack` give it.
