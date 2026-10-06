Loading a pack's files
======================

This page shows how to load the images, sounds and other files of a local pack. It uses the path calls described in
:doc:`api/path-calls`.

Images and sounds
-----------------

``display.newImage`` and ``audio.loadSound`` fail on a pack file's absolute path (the path ``urlForPath`` gives),
although ``io.open`` reads it. The plugin therefore adds ``pathForFile(path [, options])``, which returns
``filename, baseDirectory`` values that both can load:

.. code-block:: lua

   local filename, baseDirectory = backgroundAssets.pathForFile("mypack/image.png")
   if filename then
       display.newImage(filename, baseDirectory)
   end

   local soundName, soundDirectory = backgroundAssets.pathForFile("mypack/sound.wav")
   if soundName then
       audio.play(audio.loadSound(soundName, soundDirectory))
   end

``baseDirectory`` is ``system.CachesDirectory``. On iOS, the filename resolves through a symbolic link that the
plugin keeps in that directory, so no file is copied. The filename stays valid across launches as long as the pack is
local. The same code works in the Solar2D Simulator (see :doc:`simulator`).

The path you pass is the file's path in the packs' shared file namespace, as the pack's manifest selects it (see
:doc:`packs`).

Other reads
-----------

- ``urlForPath(path [, options])`` returns the file's path on disk, which ``io.open`` reads;
- ``contentsAtPath(path [, options])`` returns the file's contents as a Lua string;
- ``fileForPath(path [, options])`` returns the file open for reading, as a Lua file. The app closes it.

On failure, each returns ``nil, err``, with an error table as the second value (see :doc:`api/errors`):

.. code-block:: lua

   local text, err = backgroundAssets.contentsAtPath("mypack/text.txt", { assetPackId = "mypack" })
   if not text then
       print(err.name, err.message)
   end

Checking the pack
-----------------

With ``options.assetPackId``, a path call also checks that the pack is local, and fails with
``assetPackNotAvailable`` when it is not.

After ``removeAssetPack``, the path calls report the pack as gone: ``assetPackNotAvailable`` when
``options.assetPackId`` holds the pack's id, ``fileNotFound`` when it does not.
