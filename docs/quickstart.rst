Quickstart
==========

This page installs the plugin in a Solar2D project and walks through the smallest flow: check that Background Assets
is there, download a pack and show one of its images.

Installing
----------

From a release
~~~~~~~~~~~~~~

Add the plugin to the ``plugins`` table of your ``build.settings``, with the URL of each platform's archive:

.. code-block:: lua

   settings =
   {
       plugins =
       {
           ["plugin.backgroundAssets"] =
           {
               publisherId = "com.studycat",
               supportedPlatforms =
               {
                   iphone = { url = "https://github.com/depilz/solar2d-plugin-background-assets/releases/download/1.0.0/plugin.backgroundAssets-1.0.0-iphone.tgz" },
                   ["mac-sim"] = { url = "https://github.com/depilz/solar2d-plugin-background-assets/releases/download/1.0.0/plugin.backgroundAssets-1.0.0-mac-sim.tgz" },
                   ["win32-sim"] = { url = "https://github.com/depilz/solar2d-plugin-background-assets/releases/download/1.0.0/plugin.backgroundAssets-1.0.0-win32-sim.tgz" },
               },
           },
       },
   }

The Simulator and the device build then download the plugin from those URLs. They name the plugin's 1.0.0 release, the
version the project gets; a later release changes the version in all three.

From a local copy
~~~~~~~~~~~~~~~~~

On macOS, Solar2D also takes the plugin from ``~/Solar2DPlugins``. Copy the
``plugin/com.studycat/plugin.backgroundAssets/`` folder of the plugin's repository,
`depilz/solar2d-plugin-background-assets <https://github.com/depilz/solar2d-plugin-background-assets>`_, to
``~/Solar2DPlugins/com.studycat/plugin.backgroundAssets/``, and declare the plugin with its publisher only:

.. code-block:: lua

   settings =
   {
       plugins =
       {
           ["plugin.backgroundAssets"] = { publisherId = "com.studycat" },
       },
   }

On Windows, install from a release.

A first flow
------------

The flow below sets a listener for download events, gets the pack ``mypack``, makes it local, downloading it when
needed, and shows its ``mypack/image.png``. The calls and their events are in :doc:`api`.

.. code-block:: lua

   local backgroundAssets = require("plugin.backgroundAssets")

   local function showImage()
       local filename, baseDirectory = backgroundAssets.pathForFile("mypack/image.png")
       if filename then
           display.newImage(filename, baseDirectory, display.contentCenterX, display.contentCenterY)
       end
   end

   local function loadPack()
       backgroundAssets.setDelegate(function(event)
           if event.phase == "progress" then
               print(event.assetPack.id, event.progress.fractionCompleted)
           elseif event.phase == "failed" then
               print(event.assetPack.id, event.error.message)
           end
       end)

       backgroundAssets.getAssetPack("mypack", function(event)
           if event.isError then
               print(event.error.name, event.error.message)
               return
           end
           backgroundAssets.ensureLocalAvailability(event.assetPack, function(event)
               if event.isError then
                   print(event.error.name, event.error.message)
               else
                   showImage()
               end
           end)
       end)
   end

   if backgroundAssets.getCapabilities().isSupported then
       loadPack()
   else
       print("Background Assets is not available on this device")
   end

``getCapabilities().isSupported`` is ``false`` below iOS 26. ``pathForFile`` gives a filename and a base directory
that ``display.newImage`` and ``audio.loadSound`` load (see :doc:`files`).

Next steps
----------

- Before any device build, set up the app: the Info.plist keys, the entitlements and the downloader extension (see
  :doc:`setup`).
- Build your packs and test them (see :doc:`packs`), or host them yourself (see :doc:`self-hosting`).
- To run the app in the Solar2D Simulator over local pack sources, see :doc:`simulator`.
