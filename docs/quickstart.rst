Quickstart
==========

This page installs the plugin in a Solar2D project, then walks through the smallest flow: check that Background
Assets is available, download a pack and show one of its images.

Installing
----------

.. tab-set::

   .. tab-item:: Solar2D Directory

      The plugin is listed in the `Solar2D Free Plugin Directory <https://plugins.solar2d.com>`_. Declare it, with its
      publisher, in the ``plugins`` table of your ``build.settings``:

      .. code-block:: lua

         settings =
         {
             plugins =
             {
                 ["plugin.backgroundAssets"] = { publisherId = "com.studycat" },
             },
         }

      The Simulator and device builds download it from the Directory, which serves it to Solar2D 2026.3731 and later.

   .. tab-item:: Release URLs

      To pin an exact release, give the URL of each platform's archive instead:

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
                         iphone = { url = "https://github.com/depilz/solar2d-plugin-background-assets/releases/download/1.0.1/plugin.backgroundAssets-1.0.1-iphone.tgz" },
                         ["mac-sim"] = { url = "https://github.com/depilz/solar2d-plugin-background-assets/releases/download/1.0.1/plugin.backgroundAssets-1.0.1-mac-sim.tgz" },
                         ["win32-sim"] = { url = "https://github.com/depilz/solar2d-plugin-background-assets/releases/download/1.0.1/plugin.backgroundAssets-1.0.1-win32-sim.tgz" },
                     },
                 },
             },
         }

      These URLs pin version 1.0.1. To move to a later release, change the version in all three.

   .. tab-item:: Local copy

      On macOS, Solar2D can also load the plugin from ``~/Solar2DPlugins``. Copy the
      ``plugin/com.studycat/plugin.backgroundAssets/`` folder from the plugin's repository,
      `depilz/solar2d-plugin-background-assets <https://github.com/depilz/solar2d-plugin-background-assets>`_, to
      ``~/Solar2DPlugins/com.studycat/plugin.backgroundAssets/``, then declare the plugin with its publisher only:

      .. code-block:: lua

         settings =
         {
             plugins =
             {
                 ["plugin.backgroundAssets"] = { publisherId = "com.studycat" },
             },
         }

      On Windows, use the Directory or the release URLs.

A first flow
------------

The flow below sets a listener for download events, gets the pack ``mypack``, makes it local (downloading it when
needed) and shows its ``mypack/image.png``. :doc:`api` describes each call and its events.

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

``pathForFile`` returns a filename and a base directory that ``display.newImage`` and ``audio.loadSound`` accept (see
:doc:`files`).

.. note::

   Background Assets needs iOS 26 or later. Below it, ``getCapabilities().isSupported`` is ``false``, which is why the
   flow checks it first.

Next steps
----------

.. important::

   Before any device build, set up the app: the Info.plist keys, the entitlements and the downloader extension (see
   :doc:`setup`).

- Build your packs and test them (see :doc:`packs`), or host them yourself (see :doc:`self-hosting`).
- To run the app in the Solar2D Simulator over local pack sources, see :doc:`simulator`.
