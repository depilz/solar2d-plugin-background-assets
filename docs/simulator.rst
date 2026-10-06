Running in the Simulator
========================

This page shows how to run an app that uses the plugin in the Solar2D Simulator, over the same sources you build your
packs from. :doc:`emulator` documents every option and behaviour of the emulator.

The emulator
------------

In the Solar2D Simulator (``mac-sim`` and ``win32-sim``), the plugin runs over a folder emulator of Background Assets,
with no opt-in. ``require("plugin.backgroundAssets")`` returns the same library table as on iOS, so the app's code
stays the same. Downloads take time and send download events, and the emulator keeps its packs across Simulator
relaunches, just as a device does.

The Xcode iOS Simulator is not supported: the plugin ships no archive for it.

Configuring it
--------------

You configure the emulator through the ``plugin.backgroundAssets.emulator`` module, which exists only in the
Simulator. Require it only when ``system.getInfo("environment")`` is ``"simulator"``. Point ``packsDirectory`` at the
folder of ``ba-package`` manifests you build your packs from (see :doc:`packs`), so that the emulator and your built
packs share one set of sources:

.. code-block:: lua

   if system.getInfo("environment") == "simulator" then
       local emulator = require("plugin.backgroundAssets.emulator")
       emulator.configure({ packsDirectory = "../packs", apiVersion = "26.4", hosting = "self" })
   end
   local backgroundAssets = require("plugin.backgroundAssets")

``packsDirectory`` is an absolute path or a path relative to the project folder. Without it, no pack exists.

Set ``apiVersion``, the emulated iOS version (``"27.0"`` by default), and ``hosting`` (``"apple"`` by default) before
the first ``require("plugin.backgroundAssets")``. The settings are not stored, so configure the emulator on every
launch.

Simulating the network and the disk
-----------------------------------

:doc:`emulator` describes the effect of each of these settings:

.. code-block:: lua

   if system.getInfo("environment") == "simulator" then
       local emulator = require("plugin.backgroundAssets.emulator")
       emulator.configure({ bytesPerSecond = 100000 }) -- slower downloads
       emulator.configure({ downloadDuration = 10 })   -- every download takes 10 seconds
       emulator.configure({ offline = true })          -- downloads and store calls fail
       emulator.configure({ freeDiskSpace = 2000000 }) -- downloads that need more fail
   end

Going offline fails the downloads in flight, and lowering ``freeDiskSpace`` fails those that still need more than the
new value. A finished download subtracts its size from ``freeDiskSpace``, and removing a pack adds its size back. The
``essential`` packs installed at the first launch do not subtract their size: as on iOS, where they arrive with the app,
``freeDiskSpace`` is the free space with them already on the device. Removing one therefore adds its size back too.
:doc:`emulator` lists the default errors of these failures ("Failures").

A fresh install
---------------

``emulator.reset()`` empties the emulated device: downloads in flight fail, and the packs and files are removed. At
the next launch, the ``essential`` packs arrive and the ``prefetch`` packs start downloading, as after a fresh
install. The settings are kept.

What differs from a device
--------------------------

The emulator never sends a ``paused`` download event, keeps every pack at version 1, and assumes some behaviours that
have never been observed on a device. The full list is in the "Limits" section of :doc:`emulator`. Test on a device
before you rely on an error code.
