urlForPath()
============

| **Kind:** synchronous
| **iOS:** 26.0
| **Apple counterpart:** ``URLForPath:error:``; with ``options.language``, ``URLForPath:asLocalizedForLanguage:error:`` (27.0)
| **See also:** :doc:`path-calls`, :doc:`pathForFile`

Returns the file's path on disk, as a plain path string. ``io.open`` reads it; to show an image or play a sound, use
:doc:`pathForFile`.

Syntax
------

.. code-block:: lua

   local path, err = backgroundAssets.urlForPath(path, options)

Parameters
----------

- ``path`` (string): the file's path in the packs' shared file namespace, e.g. ``"mypack/image.png"``.
- ``options`` (table, optional): ``assetPackId`` and ``language`` (see :doc:`path-calls`).

Returns
-------

The path; or ``nil, err`` with an :doc:`error table <errors>`.

Example
-------

.. code-block:: lua

   local path = backgroundAssets.urlForPath("mypack/level.json", { assetPackId = "mypack" })
   if path then
       local file = io.open(path, "r")
       local text = file:read("*a")
       file:close()
   end
