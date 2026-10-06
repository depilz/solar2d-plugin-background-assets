getCapabilities()
=================

| **Kind:** synchronous
| **iOS:** any
| **Apple counterpart:** none; the plugin adds it
| **See also:** :doc:`/naming`

Reports what Background Assets offers here: whether it is supported, which calls are available and how the app hosts
its packs. It works on every platform and every iOS version.

Syntax
------

.. code-block:: lua

   local capabilities = backgroundAssets.getCapabilities()

Returns
-------

A table ``{ isSupported, platform, osVersion, hosting, calls }``:

- ``isSupported``: whether this OS has Background Assets (iOS 26.0 or later); ``true`` in the Simulator, where the
  emulator stands in for it (see :doc:`/emulator`);
- ``platform``: ``"ios"``, ``"mac-sim"`` or ``"win32-sim"``;
- ``osVersion``: the iOS version as a string, e.g. ``"26.4"``; nil in the Simulator;
- ``hosting``: ``"apple"`` when the app's Info.plist sets ``BAUsesAppleHosting``, ``"self"`` when it does not, and nil
  when ``BAHasManagedAssetPacks`` is not set. The app picks its hosting through its setup, not through a Lua call; in
  the Simulator it is the emulator's ``hosting`` setting (see :doc:`/emulator`);
- ``calls``: every call name of the API, mapped to ``true`` or ``false`` for this OS (in the Simulator, for the
  emulator's iOS version).

Example
-------

.. code-block:: lua

   local capabilities = backgroundAssets.getCapabilities()
   if not capabilities.isSupported then
       print("Background Assets is not available on this device")
   elseif capabilities.calls.getManifest then
       -- iOS 27 or later: the manifest is available
   end
