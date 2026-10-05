Running in the Simulator
========================

This page runs an app that uses the plugin in the Solar2D Simulator, over the same pack sources you build your packs
from. The emulator's every option and behaviour are in :doc:`emulator`.

The emulator
------------

In the Solar2D Simulator (``mac-sim`` and ``win32-sim``), the plugin runs over a folder emulator of Background Assets,
with no opt-in: ``require("plugin.backgroundAssets")`` gives the same library table as on iOS, and the app's code is
the same. Downloads take time and send download events, and the emulator keeps its packs across Simulator relaunches,
as a device does.

The Xcode iOS Simulator is not supported: the plugin ships no archive for it.

Configuring it
--------------

The emulator is configured through the module ``plugin.backgroundAssets.emulator``, which exists only in the Simulator.
Require it only when ``system.getInfo("environment")`` is ``"simulator"``, and point ``packsDirectory`` at the folder of
``ba-package`` manifests you build your packs from (see :doc:`packs`), so one set of sources feeds both:

.. code-block:: lua

   if system.getInfo("environment") == "simulator" then
       local emulator = require("plugin.backgroundAssets.emulator")
       emulator.configure({ packsDirectory = "../packs", apiVersion = "26.4", hosting = "self" })
   end
   local backgroundAssets = require("plugin.backgroundAssets")

``packsDirectory`` is an absolute path or a path relative to the project folder. Without it, no pack exists.

``apiVersion``, the iOS version emulated (``"27.0"`` by default), and ``hosting`` (``"apple"`` by default) must be set
before the first ``require("plugin.backgroundAssets")``. Settings are not stored: configure the emulator on every
launch.

Simulating the network and the disk
-----------------------------------

Each of these takes effect as :doc:`emulator` says:

.. code-block:: lua

   if system.getInfo("environment") == "simulator" then
       local emulator = require("plugin.backgroundAssets.emulator")
       emulator.configure({ bytesPerSecond = 100000 }) -- slower downloads
       emulator.configure({ downloadDuration = 10 })   -- every download takes 10 seconds
       emulator.configure({ offline = true })          -- downloads and store calls fail
       emulator.configure({ freeDiskSpace = 2000000 }) -- downloads that need more fail
   end

Going offline fails the downloads in flight, and lowering ``freeDiskSpace`` fails those that still need more than the
new value. A finished download takes its size from ``freeDiskSpace``, and a removed pack gives its size back. The
``essential`` packs installed at the first launch do not take their size from it: as on iOS, where they arrive with the
app, ``freeDiskSpace`` is the free space with them already on the device, so removing one gives its size back too. The
default errors of these failures are in :doc:`emulator` ("Failures").

A fresh install
---------------

``emulator.reset()`` empties the emulated device: downloads in flight fail, and the packs and files go. At the next
launch the ``essential`` packs arrive and the ``prefetch`` packs start downloading, as after a fresh install. The
settings are kept.

What differs from a device
--------------------------

The emulator never sends a ``paused`` download event, keeps every pack at version 1, and assumes some behaviours it
has never seen on a device. The full list is :doc:`emulator`, "Limits". Test on a device before you rely on an error
code.
