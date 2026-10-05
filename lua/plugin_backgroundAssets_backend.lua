-- plugin.backgroundAssets' backend in the Solar2D Simulator (docs/backend.rst): the folder emulator. Its engine, settings
-- and emulated device live in the emulator module, plugin.backgroundAssets.emulator, required here by its flat name, so
-- the backend and the app's emulator.configure() share them whichever the app requires first.
return require( "plugin_backgroundAssets_emulator" )._backend
