fileForPath()
=============

| **Kind:** synchronous
| **iOS:** 26.0
| **Apple counterpart:** ``fileDescriptorForPath:searchingInAssetPackWithIdentifier:error:``; with ``options.language``, its ``asLocalizedForLanguage:`` variant (27.0)
| **See also:** :doc:`path-calls`, :doc:`contentsAtPath`

Returns the file open for reading, as a Lua file, the way ``io.open`` does. The app closes it.

Syntax
------

.. code-block:: lua

   local file, err = backgroundAssets.fileForPath(path, options)

Parameters
----------

- ``path`` (string): the file's path in the packs' shared file namespace, e.g. ``"mypack/image.png"``.
- ``options`` (table, optional): ``assetPackId`` and ``language`` (see :doc:`path-calls`).

Returns
-------

The file; or ``nil, err`` with an :doc:`error table <errors>`.

Notes
-----

- Without Lua's ``io`` library, the call gives ``unsupported``.
- When the file cannot be opened or wrapped, the error is in ``NSPOSIXErrorDomain``, with the ``errno`` as its code.

Example
-------

.. code-block:: lua

   local file = backgroundAssets.fileForPath("mypack/text.txt")
   if file then
       local text = file:read("*a")
       file:close()
   end
