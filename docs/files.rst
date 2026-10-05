Loading a pack's files
======================

This page loads the images, sounds and other files of a local pack. The calls are the path calls of :doc:`api`, whose
"Path calls" section has the details.

Images and sounds
-----------------

``display.newImage`` and ``audio.loadSound`` fail on a pack file's absolute path, the path ``urlForPath`` gives;
``io.open`` reads it. So the plugin adds ``pathForFile(path [, options])``, which returns ``filename, baseDirectory``
for ``display.newImage`` and ``audio.loadSound``:

.. code-block:: lua

   local filename, baseDirectory = backgroundAssets.pathForFile("mypack/image.png")
   if filename then
       display.newImage(filename, baseDirectory)
   end

   local soundName, soundDirectory = backgroundAssets.pathForFile("mypack/sound.wav")
   if soundName then
       audio.play(audio.loadSound(soundName, soundDirectory))
   end

``baseDirectory`` is ``system.CachesDirectory``. On iOS the filename goes through a symbolic link the plugin keeps
under it, so no file is copied. The filename stays valid across launches as long as the pack is local. The same code
works in the Solar2D Simulator (see :doc:`simulator`).

The path is the file's path in the packs' shared file namespace, as the pack's manifest selects it (see :doc:`packs`).

Other reads
-----------

- ``urlForPath(path [, options])`` returns the file's path on disk, which ``io.open`` reads;
- ``contentsAtPath(path [, options])`` returns the file's contents as a Lua string;
- ``fileForPath(path [, options])`` returns the file open for reading, as a Lua file. The app closes it.

Each returns ``nil, err`` when it fails, with an error table (see "Errors" in :doc:`api`):

.. code-block:: lua

   local text, err = backgroundAssets.contentsAtPath("mypack/text.txt", { assetPackId = "mypack" })
   if not text then
       print(err.name, err.message)
   end

Checking the pack
-----------------

With ``options.assetPackId``, a path call also checks that the pack is local, and gives ``assetPackNotAvailable`` when
it is not.

After ``removeAssetPack``, the path calls report the pack gone: ``assetPackNotAvailable`` with the pack's id in
``options.assetPackId``, ``fileNotFound`` without it.
