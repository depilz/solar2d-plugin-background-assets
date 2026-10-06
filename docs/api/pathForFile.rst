pathForFile()
=============

| **Kind:** synchronous
| **iOS:** 26.0
| **Apple counterpart:** none; the plugin adds it
| **See also:** :doc:`path-calls`, :doc:`/files`

Returns a filename and a base directory for loading the file through Solar2D: ``display.newImage``,
``audio.loadSound`` and the other APIs that take a base directory. They cannot load a pack file's absolute path, which
is why the plugin adds this call.

Syntax
------

.. code-block:: lua

   local filename, baseDirectory = backgroundAssets.pathForFile(path, options)

Parameters
----------

- ``path`` (string): the file's path in the packs' shared file namespace, e.g. ``"mypack/image.png"``.
- ``options`` (table, optional): ``assetPackId`` and ``language`` (see :doc:`path-calls`).

Returns
-------

``filename, baseDirectory``; or ``nil, err`` with an :doc:`error table <errors>`. ``baseDirectory`` is
``system.CachesDirectory`` on iOS and in the Simulator.

Notes
-----

- On iOS, the filename resolves through a symbolic link that the plugin keeps in ``system.CachesDirectory``, so no
  file is copied. It stays valid across launches as long as the pack is local.
- A path that is not a plain relative path gives ``invalidArgument``. When ``system.CachesDirectory`` has no
  path, the call gives ``unsupported``.

Example
-------

.. code-block:: lua

   local filename, baseDirectory = backgroundAssets.pathForFile("mypack/image.png")
   if filename then
       display.newImage(filename, baseDirectory)
   end
