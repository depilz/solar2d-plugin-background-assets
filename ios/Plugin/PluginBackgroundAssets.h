// plugin.backgroundAssets for iOS devices: the Lua front over the native Background Assets backend.

#ifndef _PluginBackgroundAssets_H__
#define _PluginBackgroundAssets_H__

#include <CoronaLua.h>
#include <CoronaMacros.h>

// [Lua] require "plugin.backgroundAssets" (the '.' in the name becomes '_' in the symbol)
CORONA_EXPORT int luaopen_plugin_backgroundAssets( lua_State *L );

#endif // _PluginBackgroundAssets_H__
