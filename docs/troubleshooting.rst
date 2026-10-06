Troubleshooting
===============

Each entry below is a symptom, its cause and the fix, with a link to the page that covers it in full. The entries
come from failures seen while building and testing the plugin.

Building and uploading
----------------------

App Store Connect rejects the app in processing with error 90208
   The app was built with Xcode 27 (Solar2D 3733) and a ``MinimumOSVersion`` below 15.0. The Xcode 27 SDK sets the
   executable's minimum to 15.0, so set ``MinimumOSVersion`` to ``"15.0"`` or higher (see :doc:`setup`).

App Store Connect rejects the upload with ITMS-91179
   The downloader extension is in ``PlugIns/``. It must be in the app's ``Extensions/`` folder, which is where
   ``extension/build.sh`` writes it (see :doc:`setup`).

App Store Connect rejects the upload with ITMS-90360
   The extension has no ``CFBundleDisplayName``. ``extension/build.sh`` sets one (``--display-name``).

``extension/build.sh`` exits with code 2
   Nothing was built: an option is missing or wrong, the project folder has no ``build.settings``, or the
   extension's provisioning profile cannot be used. Most often the profile has expired, is not for
   ``<team id>.<app id>.<suffix>`` or lacks the app group. The message names the problem; :doc:`setup` lists every
   case.

Uploading a pack fails with ``-19241 PARAMETER_ERROR``
   The pack id contains an underscore, such as ``my_pack``. App Store Connect rejects it, although ``ba-package``,
   ``ba-serve`` and a self-hosted server accept it. Use letters and digits (see :doc:`packs`).

``ba-package`` fails on a prefetch pack
   A ``prefetch`` policy needs its ``installationEventTypes`` (see :doc:`packs`).

On the device
-------------

``getCapabilities().isSupported`` is ``false``, and every call gives ``unsupported``
   The device runs a version below iOS 26. The plugin loads from iOS 13 but Background Assets needs iOS 26, so check
   ``isSupported`` before using the packs (see :doc:`quickstart`).

One call gives ``unsupported`` while the others work
   The call needs a later iOS version than the device runs; ``getManifest``, for example, needs iOS 27.
   ``getCapabilities()`` reports which calls are available (see :doc:`api/getCapabilities`).

``getCapabilities().hosting`` is ``nil``
   The Info.plist lacks ``BAHasManagedAssetPacks = true`` (see :doc:`setup`).

The app's own downloads never start, but prefetch packs arrive
   The requests stay at "Awaiting status updates…" because the app lacks the
   ``com.apple.developer.team-identifier`` entitlement (see :doc:`setup`).

``display.newImage`` or ``audio.loadSound`` cannot load a pack file
   They fail on a file's absolute path, the one ``urlForPath`` gives. Use ``pathForFile``, which returns a filename
   and a base directory that both accept (see :doc:`files`).

A path call fails with ``assetPackNotAvailable`` or ``fileNotFound``
   The pack is not local, for example after ``removeAssetPack``. Make it local with ``ensureLocalAvailability``
   first. With ``options.assetPackId`` the call reports ``assetPackNotAvailable``; without it, ``fileNotFound``
   (see :doc:`files`).

The plugin is missing in the Xcode iOS Simulator
   The plugin ships no archive for it. Use a device, or the Solar2D Simulator (see :doc:`simulator`).

Self-hosting
------------

iOS kills the app at its first Background Assets call with "BUG IN CLIENT OF BackgroundAssets"
   The Info.plist lacks ``BAInitialDownloadRestrictions`` (see :doc:`self-hosting`).

Every pack download fails with NSURLError -1004, while the manifest requests succeed
   The server is on the device's local network, and the app does not have the Local Network permission. Pack
   downloads do not bring up the prompt, so the app has to make a request to the server itself first (see
   :doc:`self-hosting`).

Testing with ba-serve
---------------------

Every ``ensureLocalAvailability`` fails at once after ``ba-serve`` restarts
   The device keeps the old manifest until you enter the development-override URL again, under Settings › Developer
   › Background Assets (see :doc:`packs`).

The device reports "certificate invalid"
   A stale ``ba-serve`` may still hold the port; kill it and start again. Also check that the device trusts your
   root CA, under Settings › General › About › Certificate Trust Settings (see :doc:`packs`).

In the Solar2D Simulator
------------------------

No pack exists
   ``packsDirectory`` is not set. Point it at the folder of ``ba-package`` manifests you build your packs from (see
   :doc:`simulator`).

``apiVersion`` or ``hosting`` has no effect
   Set them before the first ``require("plugin.backgroundAssets")``. The settings are not stored, so configure the
   emulator on every launch (see :doc:`simulator`).

An error differs from the one on a device
   The emulator assumes some behaviours that have never been observed on a device; :doc:`emulator` lists them under
   "Limits". Test on a device before you rely on an error code.
