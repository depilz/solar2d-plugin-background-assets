contentsAtPath()
================

| **Kind:** synchronous
| **iOS:** 26.0
| **Apple counterpart:** ``contentsAtPath:searchingInAssetPackWithIdentifier:options:error:``; with ``options.language``, its ``asLocalizedForLanguage:`` variant (27.0)
| **See also:** :doc:`path-calls`, :doc:`fileForPath`

Returns the file's contents as a Lua string.

Syntax
------

.. code-block:: lua

   local contents, err = backgroundAssets.contentsAtPath(path, options)

Parameters
----------

- ``path`` (string): the file's path in the packs' shared file namespace, e.g. ``"mypack/image.png"``.
- ``options`` (table, optional): ``assetPackId`` and ``language`` (see :doc:`path-calls`).

Returns
-------

The contents; or ``nil, err`` with an :doc:`error table <errors>`.

Example
-------

.. code-block:: lua

   local text, err = backgroundAssets.contentsAtPath("mypack/text.txt", { assetPackId = "mypack" })
   if not text then
       print(err.name, err.message)
   end
