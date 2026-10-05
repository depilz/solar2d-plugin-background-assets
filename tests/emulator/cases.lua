-- usage: lua cases.lua REPO --list | REPO CASE
-- --list prints the case ids; CASE runs that case: the front, REPO/lua/plugin_backgroundAssets.lua, required as the
-- Simulator requires it, over the shipped backend file REPO/lua/plugin_backgroundAssets_backend.lua and the emulator
-- module REPO/lua/plugin_backgroundAssets_emulator.lua, with Solar2D stood in by solar2d.lua and json.lua, in a fresh
-- folder under $SUITE_OUT. It fails with a message when the case does not hold.
local repo, which = ...
local here = arg[0]:match( "^(.*)/" ) or "."
local luaBin = arg[-1]:match( "^(.*)/" ) or "."
package.path = here .. "/?.lua;" .. repo .. "/lua/?.lua;" .. package.path
package.cpath = package.cpath .. ";" .. luaBin .. "/?.so"
local json = require( "json" )
local lfs = require( "lfs" )
local stubSolar2D = require( "solar2d" )
local FRONT = "plugin_backgroundAssets"
local BACKEND = "plugin_backgroundAssets_backend"
local EMULATOR = "plugin_backgroundAssets_emulator"
local DEVICE = "plugin.backgroundAssets/emulator"
local UNLOCALIZED = DEVICE .. "/files/Unlocalized"

local function show( value )
	if type( value ) == "string" then return string.format( "%q", value ) end
	if type( value ) ~= "table" then return tostring( value ) end
	local keys = {}
	for key in pairs( value ) do
		keys[#keys + 1] = key
	end
	table.sort( keys, function( a, b ) return tostring( a ) < tostring( b ) end )
	local parts = {}
	for _, key in ipairs( keys ) do
		parts[#parts + 1] = tostring( key ) .. "=" .. show( value[key] )
	end
	return "{" .. table.concat( parts, ", " ) .. "}"
end

local function same( a, b )
	if type( a ) ~= "table" or type( b ) ~= "table" then return a == b end
	for key, value in pairs( a ) do
		if not same( value, b[key] ) then return false end
	end
	for key in pairs( b ) do
		if a[key] == nil then return false end
	end
	return true
end

local function check( condition, message )
	if not condition then error( message, 2 ) end
end

local function checkSame( actual, expected, what )
	if not same( actual, expected ) then
		error( what .. ": got " .. show( actual ) .. ", expected " .. show( expected ), 2 )
	end
end

local function raises( fn, expected )
	local ok, message = pcall( fn )
	check( not ok, "no error raised, expected " .. expected )
	check( message:find( expected, 1, true ), "error message: " .. message )
	check( message:find( "^[^:]*cases%.lua:%d+: " ), "error not reported at the caller: " .. message )
end

-- Files

local function writeFile( path, contents )
	assert( os.execute( "mkdir -p '" .. path:match( "^(.*)/" ) .. "'" ) == 0 )
	local file = assert( io.open( path, "wb" ) )
	file:write( contents )
	file:close()
end

local function readFile( path )
	local file = io.open( path, "rb" )
	if not file then return nil end
	local contents = file:read( "*a" )
	file:close()
	return contents
end

local function exists( path )
	return lfs.attributes( path, "mode" ) ~= nil
end

-- listFiles: the sorted paths, relative to folder, of every file under it
local function listFiles( folder, prefix, files )
	files = files or {}
	if not exists( folder ) then return files end
	for name in lfs.dir( folder ) do
		local path, relative = folder .. "/" .. name, prefix and ( prefix .. "/" .. name ) or name
		local mode = name:find( "^%.%.?$" ) == nil and lfs.attributes( path, "mode" )
		if mode == "directory" then
			listFiles( path, relative, files )
		elseif mode then
			files[#files + 1] = relative
		end
	end
	table.sort( files )
	return files
end

-- The world a case runs in

-- newWorld: fresh Solar2D stand-ins over an empty case folder, with an empty packs folder in the project
local function newWorld()
	local root = assert( os.getenv( "SUITE_OUT" ), "SUITE_OUT is not set" ) .. "/cases/" .. which:gsub( "[^%w]", "_" )
	assert( os.execute( "rm -rf '" .. root .. "'" ) == 0 )
	local folders, clock = stubSolar2D( root )
	local world = { clock = clock, caches = folders.CachesDirectory, packs = folders.ResourceDirectory .. "/packs" }
	assert( os.execute( "mkdir -p '" .. world.packs .. "'" ) == 0 )
	return world
end

-- launch: the emulator module as a fresh app launch loads it, configured with options; packsDirectory defaults to the
-- project's packs folder. The previous run's timers end with it.
local function launch( options )
	timer.cancelAll()
	package.loaded[FRONT], package.loaded[BACKEND], package.loaded[EMULATOR] = nil, nil, nil
	local emulator = require( EMULATOR )
	emulator.configure( { packsDirectory = "packs" } )
	emulator.configure( options or {} )
	return emulator
end

-- loadFront: the front, required after the emulator as an app may, over the backend file, which is the emulator's backend
local function loadFront( emulator )
	package.loaded[FRONT], package.loaded[BACKEND] = nil, nil
	local lib = require( FRONT )
	check( package.loaded[BACKEND] == emulator._backend, "the backend file is not the emulator module's backend" )
	return lib
end

-- addPack: writes the manifest NAME.json (NAME defaults to its assetPackID) and the files, relative to the packs folder
local function addPack( world, manifest, files, name )
	writeFile( world.packs .. "/" .. ( name or manifest.assetPackID ) .. ".json", json.encode( manifest ) )
	for path, contents in pairs( files or {} ) do
		writeFile( world.packs .. "/" .. path, contents )
	end
end

-- filePack: a pack ID with one file selector per name, ID/name, holding "ID name"
local function filePack( world, id, policy, names, fields )
	local manifest = { assetPackID = id, downloadPolicy = { [policy] = {} }, fileSelectors = {}, platforms = { "iOS" } }
	local files = {}
	for i, name in ipairs( names ) do
		manifest.fileSelectors[i] = { file = id .. "/" .. name }
		files[id .. "/" .. name] = id .. " " .. name
	end
	for key, value in pairs( fields or {} ) do
		manifest[key] = value
	end
	addPack( world, manifest, files )
end

-- call: runs an async front call with a listener added last and returns its one event
local function call( world, fn, ... )
	local events = {}
	local args = { ... }
	args[select( "#", ... ) + 1] = function( event ) events[#events + 1] = event end
	fn( unpack( args ) )
	world.clock.advance( 1 )
	check( #events == 1, #events .. " events" )
	return events[1]
end

-- download: ensureLocalAvailability of the pack through the front, run to its end; returns the call's one event
local function download( world, lib, id )
	local events = {}
	lib.ensureLocalAvailability( { id = id }, function( event ) events[#events + 1] = event end )
	world.clock.advance( 60000 )
	check( #events == 1, #events .. " events" )
	return events[1]
end

local function sorted( list )
	table.sort( list )
	return list
end

local function ids( packs )
	local list = {}
	for i, pack in ipairs( packs ) do
		list[i] = pack.id
	end
	return list
end

local function deviceState( world )
	return json.decode( readFile( world.caches .. "/" .. DEVICE .. "/state.json" ) or "null" )
end

local function managedError( code, name, assetPackId )
	return { domain = "BAManagedErrorDomain", code = code, name = name, assetPackId = assetPackId }
end

-- checkError: the error's domain, code, name and assetPackId, and that it has a message
local function checkError( err, expected, what )
	check( type( err ) == "table" and type( err.message ) == "string", what .. ": no error message in " .. show( err ) )
	checkSame( { domain = err.domain, code = err.code, name = err.name, assetPackId = err.assetPackId }, expected, what )
end

-- recorder: a listener adding each event it gets to events as { phase (a download's phase, or else the event's type),
-- id, at (the clock's ms), progress, error }
local function recorder( world, events )
	return function( event )
		events[#events + 1] = { phase = event.phase or event.type, id = event.assetPack and event.assetPack.id,
			at = world.clock.now, progress = event.progress, error = event.error }
	end
end

-- watchDownloads: the list the app delegate's download events go to, through recorder
local function watchDownloads( world, lib )
	local events = {}
	lib.setDelegate( recorder( world, events ) )
	return events
end

-- timeline: the events as "phase id@ms" lines
local function timeline( events )
	local lines = {}
	for i, event in ipairs( events ) do
		lines[i] = event.phase .. " " .. tostring( event.id ) .. "@" .. event.at
	end
	return lines
end

local function eventsOf( events, id )
	local list = {}
	for _, event in ipairs( events ) do
		if event.id == id then list[#list + 1] = event end
	end
	return list
end

-- downloadLines: the timeline of a download of id from began at start ms, with progress every 100 ms over durationMs,
-- then finished
local function downloadLines( id, start, durationMs )
	local lines = { "began " .. id .. "@" .. start }
	local elapsed = 0
	repeat
		elapsed = math.min( elapsed + 100, durationMs )
		lines[#lines + 1] = "progress " .. id .. "@" .. ( start + elapsed )
	until elapsed == durationMs
	lines[#lines + 1] = "finished " .. id .. "@" .. ( start + durationMs )
	return lines
end

local function append( list, ... )
	for _, more in ipairs( { ... } ) do
		for _, value in ipairs( more ) do
			list[#list + 1] = value
		end
	end
	return list
end

local function cocoaError( code, assetPackId )
	return { domain = "NSCocoaErrorDomain", code = code, assetPackId = assetPackId }
end

local function offlineError( assetPackId )
	return { domain = "NSURLErrorDomain", code = -1009, assetPackId = assetPackId }
end

local function statusNames( status )
	local set = {}
	for name, isSet in pairs( status ) do
		if isSet then set[#set + 1] = name end
	end
	table.sort( set )
	return set
end

local cases = {
	{ "the module: configure merges fields and returns nothing", function()
		newWorld()
		local emulator = launch()
		check( select( "#", emulator.configure( { apiVersion = "26.4" } ) ) == 0, "configure returned a value" )
		emulator.configure( { hosting = "self" } )
		emulator.configure( {} )
		local capabilities = loadFront( emulator ).getCapabilities()
		check( capabilities.isSupported and capabilities.platform == "mac-sim" and capabilities.osVersion == nil and
			capabilities.hosting == "self", show( capabilities ) )
		check( capabilities.calls.getLocalStatusOfAssetPack and not capabilities.calls.getManifest, "calls at 26.4" )
		capabilities = loadFront( launch() ).getCapabilities()
		check( capabilities.hosting == "apple" and capabilities.calls.getManifest, "defaults: " .. show( capabilities ) )
	end },

	{ "the module: configure raises a Lua error naming a wrong field", function()
		newWorld()
		local emulator = launch()
		local wrong = {
			packsDirectory = { 3, "" },
			apiVersion = { "25.0", "28.0", 27 },
			hosting = { "apples", true },
			bytesPerSecond = { 0, -1, "fast", false },
			downloadDuration = { -1, true, "1" },
			offline = { "yes", 1 },
			freeDiskSpace = { -1, true },
			offlineError = { { domain = 1, code = 1, message = "m" }, { domain = "d", message = "m" }, true },
			lowDiskSpaceError = { { domain = "d", code = 640 }, "full" },
		}
		for field, values in pairs( wrong ) do
			for _, value in ipairs( values ) do
				raises( function() emulator.configure( { [field] = value } ) end, "bad option '" .. field .. "'" )
			end
		end
		raises( function() emulator.configure( { packDirectory = "packs" } ) end, 'unknown field "packDirectory"' )
		raises( function() emulator.configure( "packs" ) end, "bad argument #1 to 'configure'" )
		raises( function() emulator.configure( { hosting = "self", bytesPerSecond = 0 } ) end, "bytesPerSecond" )
		emulator.configure( { downloadDuration = 0, freeDiskSpace = 0, offline = true, bytesPerSecond = 0.5,
			offlineError = { domain = "d", code = 1, message = "m" }, lowDiskSpaceError = false } )
		emulator.configure( { downloadDuration = false, freeDiskSpace = false, offlineError = false } )
		check( loadFront( emulator ).getCapabilities().hosting == "apple", "a raising configure changed a setting" )
	end },

	{ "the module: apiVersion and hosting are fixed once the front has loaded", function()
		newWorld()
		local emulator = launch( { apiVersion = "26.0", hosting = "self" } )
		loadFront( emulator )
		raises( function() emulator.configure( { apiVersion = "27.0" } ) end,
			"'apiVersion' must be set before the first require(\"plugin.backgroundAssets\")" )
		raises( function() emulator.configure( { hosting = "apple" } ) end, "'hosting' must be set before" )
		emulator.configure( { apiVersion = "26.0", hosting = "self", offline = true, bytesPerSecond = 1 } )
		emulator = launch( { apiVersion = "27.0" } )
		check( loadFront( emulator ).getCapabilities().calls.getManifest, "a relaunch takes a new apiVersion" )
	end },

	{ "the module: the front's library table gains nothing", function()
		newWorld()
		local emulator = launch()
		local keys = {}
		for key in pairs( loadFront( emulator ) ) do
			keys[#keys + 1] = key
		end
		table.sort( keys )
		checkSame( keys, {
			"assetPackIsAvailableLocally", "checkForUpdates", "contentsAtPath", "ensureLocalAvailability",
			"ensureLocalAvailabilityOfAssetPacks", "fileForPath", "getAllAssetPacks", "getAssetPack", "getCapabilities",
			"getLocalStatusOfAssetPack", "getLocallyAvailableLanguages", "getManifest", "getResolvedLanguage",
			"getStatusOfAssetPack", "getStatusRelativeToAssetPack", "name", "pathForFile", "publisherId",
			"reconcilePreferredLanguages", "removeAssetPack", "setDelegate", "setResolvedLanguage", "urlForPath",
		}, "library keys" )
		keys = {}
		for key in pairs( emulator ) do
			keys[#keys + 1] = key
		end
		table.sort( keys )
		checkSame( keys, { "_backend", "configure", "reset" }, "module keys" )
	end },

	{ "win32-sim: detected from package.config, the emulator runs there", function()
		local world = newWorld()
		package.config = "\\" .. package.config:sub( 2 )
		filePack( world, "essential", "essential", { "a.txt" } )
		local lib = loadFront( launch() )
		check( lib.getCapabilities().platform == "win32-sim", "platform " .. show( lib.getCapabilities().platform ) )
		checkSame( { lib.pathForFile( "essential/a.txt" ) }, { UNLOCALIZED .. "/essential/a.txt", "CachesDirectory" },
			"pathForFile" )
		check( lib.contentsAtPath( "essential/a.txt" ) == "essential a.txt", "contentsAtPath" )
	end },

	{ "pack sources: every selector kind, sourceRoot, and packs without it", function()
		local world = newWorld()
		local files = {
			"one.txt", "dir/a.txt", "dir/sub/b.txt", "dir/sub/skip.txt", "pat/x.txt", "pat/y.txt", "pat/deep/z.txt",
			"pat/x.dat", "q/f1.a", "q/f2.b", "q/f3.c", "q/f10.a", "q/f%.a", "renamed/src.txt", "tree/c.txt",
			"tree/skip.txt", "tree/inner/d.txt",
		}
		local contents = {}
		for _, path in ipairs( files ) do
			contents["src/" .. path] = "<" .. path .. ">"
		end
		contents["plain/p.txt"] = "plain"
		addPack( world, {
			assetPackID = "kinds",
			downloadPolicy = { essential = { installationEventTypes = { "firstInstallation" } } },
			sourceRoot = "src",
			fileSelectors = {
				{ file = "one.txt" },
				{ directory = "dir/" },
				{ filePattern = "pat/*.txt" },
				{ filePattern = "q/f?.[ab]" },
				{ filePattern = "q/f[!0-9].a" },
				{ fileSource = "renamed/src.txt", fileDestination = "dest/file.txt" },
				{ directorySource = "tree", directoryDestination = "moved" },
				{ fileExclusion = "tree/skip.txt" },
				{ fileExclusion = "dir/sub/skip.txt" },
			},
			platforms = { "iOS", "macOS" },
		}, contents )
		addPack( world, { assetPackID = "plain", downloadPolicy = { onDemand = {} }, fileSelectors = { { file = "plain/p.txt" } } } )
		local lib = loadFront( launch() )
		local expected = {
			["dest/file.txt"] = "renamed/src.txt", ["dir/a.txt"] = "dir/a.txt", ["dir/sub/b.txt"] = "dir/sub/b.txt",
			["moved/c.txt"] = "tree/c.txt", ["moved/inner/d.txt"] = "tree/inner/d.txt", ["one.txt"] = "one.txt",
			["pat/x.txt"] = "pat/x.txt", ["pat/y.txt"] = "pat/y.txt", ["q/f%.a"] = "q/f%.a", ["q/f1.a"] = "q/f1.a",
			["q/f2.b"] = "q/f2.b",
		}
		local paths, size = {}, 0
		for path, source in pairs( expected ) do
			paths[#paths + 1] = path
			size = size + #( "<" .. source .. ">" )
			check( readFile( world.caches .. "/" .. UNLOCALIZED .. "/" .. path ) == "<" .. source .. ">", path )
		end
		table.sort( paths )
		checkSame( listFiles( world.caches .. "/" .. UNLOCALIZED ), paths, "installed files" )
		local event = call( world, lib.getAssetPack, "kinds" )
		checkSame( event.assetPack, { id = "kinds", downloadSize = size, version = 1 }, "kinds" )
		event = call( world, lib.getAssetPack, "plain" )
		checkSame( event.assetPack, { id = "plain", downloadSize = 5, version = 1 }, "plain" )
		check( not lib.assetPackIsAvailableLocally( "plain" ), "an onDemand pack is local" )
	end },

	{ "pack sources: only top-level .json manifests for iOS", function()
		local world = newWorld()
		filePack( world, "ios", "onDemand", { "a.txt" } )
		filePack( world, "anyplatform", "onDemand", { "a.txt" }, { platforms = false } )
		filePack( world, "mac", "onDemand", { "a.txt" }, { platforms = { "macOS" } } )
		writeFile( world.packs .. "/notes.txt", json.encode( { assetPackID = "notes", fileSelectors = {} } ) )
		writeFile( world.packs .. "/nested/inner.json", json.encode( { assetPackID = "inner", fileSelectors = {} } ) )
		local lines = {}
		print = function( line ) lines[#lines + 1] = line end
		local lib = loadFront( launch() )
		checkSame( ids( call( world, lib.getAllAssetPacks ).assetPacks ), { "anyplatform", "ios" }, "packs" )
		checkSame( lines, {}, "printed" )
	end },

	{ "pack sources: a bad manifest is skipped with one printed line", function()
		local world = newWorld()
		filePack( world, "good", "onDemand", { "a.txt" } )
		writeFile( world.packs .. "/broken.json", "{ \"assetPackID\": " )
		addPack( world, { fileSelectors = { { file = "good/a.txt" } } }, nil, "noid" )
		addPack( world, { assetPackID = "badkey", fileSelectors = { { fiel = "good/a.txt" } } } )
		addPack( world, { assetPackID = "nothing", fileSelectors = { { file = "missing.txt" } } } )
		addPack( world, { assetPackID = "nomatch", fileSelectors = { { filePattern = "good/*.png" } } } )
		addPack( world, { assetPackID = "halfpair", fileSelectors = { { fileSource = "good/a.txt" } } } )
		local lib = loadFront( launch() )
		local lines = {}
		print = function( line ) lines[#lines + 1] = line end
		checkSame( ids( call( world, lib.getAllAssetPacks ).assetPacks ), { "good" }, "packs" )
		table.sort( lines )
		local expected = {
			{ "badkey.json", "unknown selector key 'fiel'" },
			{ "broken.json", "invalid JSON" },
			{ "halfpair.json", "a selector names nothing" },
			{ "noid.json", "no assetPackID" },
			{ "nomatch.json", "a selector names nothing" },
			{ "nothing.json", "a selector names nothing" },
		}
		check( #lines == #expected, "printed " .. show( lines ) )
		for i, line in ipairs( lines ) do
			check( line:find( expected[i][1], 1, true ) and line:find( expected[i][2], 1, true ), "line " .. line )
		end
	end },

	{ "pack sources: re-read by every store call; packsDirectory relative or absolute", function()
		local world = newWorld()
		filePack( world, "first", "onDemand", { "a.txt" } )
		local emulator = launch()
		local lib = loadFront( emulator )
		checkSame( ids( call( world, lib.getAllAssetPacks ).assetPacks ), { "first" }, "at load" )
		filePack( world, "second", "onDemand", { "b.txt" } )
		checkSame( ids( call( world, lib.getAllAssetPacks ).assetPacks ), { "first", "second" }, "after adding" )
		check( not call( world, lib.getAssetPack, "second" ).isError, "getAssetPack of the added pack" )
		os.remove( world.packs .. "/first.json" )
		checkError( call( world, lib.getAssetPack, "first" ).error, managedError( 0, "assetPackNotFound", "first" ),
			"getAssetPack of the deleted pack" )
		local other = world.packs .. "/../elsewhere"
		writeFile( other .. "/third.json", json.encode( { assetPackID = "third", fileSelectors = {} } ) )
		emulator.configure( { packsDirectory = other } )
		checkSame( ids( call( world, lib.getAllAssetPacks ).assetPacks ), { "third" }, "absolute packsDirectory" )
	end },

	{ "raw packs: id, downloadSize, version 1, language and userInfo as JSON", function()
		local world = newWorld()
		filePack( world, "info", "onDemand", { "a.txt", "b.txt" }, { language = "fr", userInfo = { key = "value" } } )
		local lib = loadFront( launch() )
		local event = call( world, lib.getAssetPack, "info" )
		local pack = event.assetPack
		check( not event.isError and pack.id == "info" and pack.downloadSize == 20 and pack.version == 1 and
			pack.language == "fr", show( pack ) )
		checkSame( json.decode( pack.userInfo ), { key = "value" }, "userInfo" )
		event = call( world, lib.getAssetPack, "none" )
		check( event.isError and event.assetPack == nil, show( event ) )
		checkError( event.error, managedError( 0, "assetPackNotFound", "none" ), "unknown pack" )
	end },

	{ "install-time: essential packs arrive at the first launch without events, once", function()
		local world = newWorld()
		filePack( world, "essential", "essential", { "a.txt" } )
		filePack( world, "ondemand", "onDemand", { "a.txt" } )
		filePack( world, "essentialfr", "essential", { "a.txt" }, { language = "fr" } )
		local emulator = launch()
		local backend = emulator._backend
		local lib = loadFront( emulator )
		local events = {}
		lib.setDelegate( function( event ) events[#events + 1] = event end )
		world.clock.advance( 1000 )
		checkSame( events, {}, "download events" )
		check( lib.assetPackIsAvailableLocally( "essential" ), "essential is not local" )
		check( readFile( world.caches .. "/" .. UNLOCALIZED .. "/essential/a.txt" ) == "essential a.txt", "file" )
		for _, id in ipairs( { "ondemand", "essentialfr" } ) do
			check( not backend.assetPackIsAvailableLocally( id ), id .. " is local" )
		end
		check( deviceState( world ).installed == true, "installed is not stored" )
		check( not call( world, lib.removeAssetPack, "essential" ).isError, "remove" )
		lib = loadFront( launch() )
		check( not lib.assetPackIsAvailableLocally( "essential" ), "essential came back at a later launch" )

		emulator.reset()
		writeFile( world.caches .. "/" .. DEVICE .. "/state.json", json.encode( { resolvedLanguage = "fr" } ) )
		lib = loadFront( launch() )
		check( lib.assetPackIsAvailableLocally( "essentialfr" ), "the resolved language's essential pack" )
		check( readFile( world.caches .. "/" .. DEVICE .. "/files/fr/essentialfr/a.txt" ) == "essentialfr a.txt",
			"localized file" )
		check( not exists( world.caches .. "/" .. DEVICE .. "/staging" ), "the staging folder is left" )
	end },

	{ "status: store and local status bits, unknown ids", function()
		local world = newWorld()
		filePack( world, "essential", "essential", { "a.txt" } )
		filePack( world, "ondemand", "onDemand", { "a.txt" } )
		local lib = loadFront( launch() )
		local function statuses( id )
			return {
				statusNames( call( world, lib.getStatusOfAssetPack, id ).status ),
				statusNames( call( world, lib.getStatusRelativeToAssetPack, { id = id } ).status ),
				statusNames( call( world, lib.getLocalStatusOfAssetPack, id ).status ),
			}
		end
		local localBits = { "downloaded", "upToDate" }
		checkSame( statuses( "essential" ), { localBits, localBits, localBits }, "essential" )
		checkSame( statuses( "ondemand" ), { { "downloadAvailable" }, { "downloadAvailable" }, {} }, "ondemand" )
		for _, fn in ipairs( { lib.getStatusOfAssetPack, lib.getLocalStatusOfAssetPack } ) do
			checkError( call( world, fn, "none" ).error, managedError( 0, "assetPackNotFound", "none" ), "unknown" )
		end
		checkError( call( world, lib.getStatusRelativeToAssetPack, { id = "none" } ).error,
			managedError( 0, "assetPackNotFound", "none" ), "unknown relative" )
		check( lib.assetPackIsAvailableLocally( "essential" ) == true, "essential available" )
		check( lib.assetPackIsAvailableLocally( "ondemand" ) == false, "ondemand available" )
		os.remove( world.packs .. "/essential.json" )
		local obsolete = { "downloaded", "obsolete", "upToDate" }
		checkSame( statuses( "essential" ), { obsolete, obsolete, localBits }, "essential without its manifest" )
	end },

	{ "checkForUpdates: removes local packs whose manifest is gone", function()
		local world = newWorld()
		filePack( world, "kept", "essential", { "a.txt" } )
		filePack( world, "gone", "essential", { "a.txt" } )
		local lib = loadFront( launch() )
		local event = call( world, lib.checkForUpdates )
		checkSame( { event.updatingIdentifiers, event.removedIdentifiers }, { {}, {} }, "nothing removed" )
		os.remove( world.packs .. "/gone.json" )
		event = call( world, lib.checkForUpdates )
		checkSame( { event.updatingIdentifiers, event.removedIdentifiers }, { {}, { "gone" } }, "gone removed" )
		check( not lib.assetPackIsAvailableLocally( "gone" ), "gone is still local" )
		checkSame( listFiles( world.caches .. "/" .. UNLOCALIZED ), { "kept/a.txt" }, "files" )
		checkError( call( world, lib.getStatusOfAssetPack, "gone" ).error, managedError( 0, "assetPackNotFound", "gone" ),
			"status of the removed pack" )
	end },

	{ "removeAssetPack: deletes a local pack's files and folders", function()
		local world = newWorld()
		filePack( world, "removed", "essential", { "a.txt", "deep/b.txt" } )
		filePack( world, "kept", "essential", { "c.txt" } )
		filePack( world, "ondemand", "onDemand", { "a.txt" } )
		local lib = loadFront( launch() )
		check( lib.pathForFile( "removed/a.txt", { assetPackId = "removed" } ), "pathForFile before the remove" )
		local event = call( world, lib.removeAssetPack, "removed" )
		check( event.type == "removeAssetPack" and not event.isError, show( event ) )
		checkSame( listFiles( world.caches .. "/" .. UNLOCALIZED ), { "kept/c.txt" }, "files" )
		check( not exists( world.caches .. "/" .. UNLOCALIZED .. "/removed" ), "the pack's folder is left" )
		check( deviceState( world ).packs.removed == nil, "state.json still holds the pack" )
		check( not lib.assetPackIsAvailableLocally( "removed" ), "still local" )
		local filename, err = lib.pathForFile( "removed/a.txt", { assetPackId = "removed" } )
		check( filename == nil, "pathForFile after the remove" )
		checkSame( { err.domain, err.name, err.assetPackId }, { "plugin.backgroundAssets", "assetPackNotAvailable", "removed" },
			"pathForFile error" )
		check( not call( world, lib.removeAssetPack, "ondemand" ).isError, "remove of a pack that is not local" )
		checkError( call( world, lib.removeAssetPack, "none" ).error, managedError( 0, "assetPackNotFound", "none" ),
			"remove of an unknown pack" )
	end },

	{ "path calls: urlForPath, pathForFile, contentsAtPath and fileForPath through the front", function()
		local world = newWorld()
		filePack( world, "pack", "essential", { "image.png" } )
		filePack( world, "other", "essential", { "text.txt" } )
		local lib = loadFront( launch() )
		local name = UNLOCALIZED .. "/pack/image.png"
		check( lib.urlForPath( "pack/image.png" ) == world.caches .. "/" .. name, "urlForPath " ..
			show( lib.urlForPath( "pack/image.png" ) ) )
		checkSame( { lib.pathForFile( "pack/image.png" ) }, { name, "CachesDirectory" }, "pathForFile" )
		checkSame( { lib.pathForFile( "pack/image.png", { assetPackId = "pack" } ) }, { name, "CachesDirectory" },
			"pathForFile with the pack" )
		check( lib.contentsAtPath( "pack/image.png" ) == "pack image.png", "contentsAtPath" )
		check( lib.contentsAtPath( "pack/image.png", { assetPackId = "pack" } ) == "pack image.png", "with the pack" )
		local handle = lib.fileForPath( "pack/image.png", { assetPackId = "pack" } )
		check( io.type( handle ) == "file" and handle:read( "*a" ) == "pack image.png", "fileForPath" )
		handle:close()
		for _, callName in ipairs( { "urlForPath", "pathForFile", "contentsAtPath", "fileForPath" } ) do
			local value, err = lib[callName]( "pack/none.png" )
			check( value == nil, callName .. " gave a value" )
			checkError( err, managedError( 1, "fileNotFound" ), callName .. " of a missing file" )
		end
		for _, callName in ipairs( { "contentsAtPath", "fileForPath" } ) do
			local value, err = lib[callName]( "other/text.txt", { assetPackId = "pack" } )
			check( value == nil, callName .. " gave another pack's file" )
			checkError( err, managedError( 1, "fileNotFound", "pack" ), callName .. " of another pack's file" )
		end
	end },

	{ "languages: localized packs, getManifest and the language calls", function()
		local world = newWorld()
		filePack( world, "base", "essential", { "a.txt" } )
		addPack( world, { assetPackID = "hello-en", downloadPolicy = { essential = {} }, language = "en",
			sourceRoot = "en", fileSelectors = { { file = "loc/hello.txt" } } }, { ["en/loc/hello.txt"] = "hello" } )
		addPack( world, { assetPackID = "hello-fr", downloadPolicy = { essential = {} }, language = "fr",
			sourceRoot = "fr", fileSelectors = { { file = "loc/hello.txt" } } }, { ["fr/loc/hello.txt"] = "bonjour" } )
		filePack( world, "hello-de", "onDemand", { "a.txt" }, { language = "de" } )
		writeFile( world.caches .. "/" .. DEVICE .. "/state.json", json.encode( { resolvedLanguage = "fr" } ) )
		local lib = loadFront( launch() )
		local manifest = call( world, lib.getManifest ).manifest
		checkSame( { ids( manifest.assetPacks ), ids( manifest.localizedAssetPacks ), manifest.availableLanguages,
			manifest.primaryLanguage, manifest.resolvedLanguage },
			{ { "base" }, { "hello-de", "hello-en", "hello-fr" }, { "de", "en", "fr" }, nil, "fr" }, "manifest" )
		checkSame( call( world, lib.getLocallyAvailableLanguages ).languages, { "fr" }, "local languages" )
		check( lib.contentsAtPath( "loc/hello.txt", { language = "fr" } ) == "bonjour", "fr" )
		check( lib.contentsAtPath( "loc/hello.txt" ) == "bonjour", "no language: the resolved language" )
		check( lib.contentsAtPath( "a.txt" ) == nil, "a path outside the namespace" )
		checkSame( { lib.pathForFile( "loc/hello.txt", { language = "fr" } ) },
			{ DEVICE .. "/files/fr/loc/hello.txt", "CachesDirectory" }, "pathForFile fr" )
		checkError( select( 2, lib.urlForPath( "loc/hello.txt", { language = "en" } ) ), managedError( 1, "fileNotFound" ),
			"en is not local" )
		check( lib.setResolvedLanguage( "en" ) and lib.getResolvedLanguage() == "en", "set en" )
		check( deviceState( world ).resolvedLanguage == "en", "state.json resolvedLanguage" )
		check( lib.urlForPath( "loc/hello.txt" ) == nil, "no language after setting en" )
		check( not call( world, lib.reconcilePreferredLanguages ).isError, "reconcilePreferredLanguages" )
		lib = loadFront( launch() )
		check( lib.getResolvedLanguage() == "en", "resolvedLanguage after a relaunch" )
		check( lib.setResolvedLanguage( nil ) and lib.getResolvedLanguage() == nil, "set nil" )
	end },

	{ "reset: empties the device; install-time packs come back at the next launch", function()
		local world = newWorld()
		filePack( world, "essential", "essential", { "a.txt" } )
		filePack( world, "ondemand", "onDemand", { "a.txt" } )
		local emulator = launch()
		local lib = loadFront( emulator )
		lib.setResolvedLanguage( "fr" )
		check( not call( world, lib.removeAssetPack, "ondemand" ).isError, "remove" )
		checkSame( emulator._backend.loadRemovedAssetPacks(), { "ondemand" }, "the removed-pack record" )
		check( select( "#", emulator.reset() ) == 0, "reset returned a value" )
		check( not exists( world.caches .. "/" .. DEVICE ), "the emulator folder is left" )
		check( not lib.assetPackIsAvailableLocally( "essential" ), "essential is local after reset" )
		check( lib.getResolvedLanguage() == nil, "resolvedLanguage after reset" )
		checkSame( emulator._backend.loadRemovedAssetPacks(), {}, "the stored record after reset" )
		lib = loadFront( launch() )
		check( lib.assetPackIsAvailableLocally( "essential" ), "essential at the next launch" )
	end },

	{ "relaunch: the device and the removed-pack record persist", function()
		local world = newWorld()
		filePack( world, "essential", "essential", { "a.txt" } )
		filePack( world, "removed", "essential", { "a.txt" } )
		local lib = loadFront( launch( { apiVersion = "26.0" } ) )
		check( not call( world, lib.removeAssetPack, "removed" ).isError, "remove" )
		checkSame( deviceState( world ).removedAssetPacks, { "removed" }, "stored record" )
		local emulator = launch( { apiVersion = "26.0" } )
		checkSame( emulator._backend.loadRemovedAssetPacks(), { "removed" }, "record after a relaunch" )
		lib = loadFront( emulator )
		local filename, err = lib.pathForFile( "removed/a.txt", { assetPackId = "removed" } )
		check( filename == nil and err.name == "assetPackNotAvailable", "26.0 pack check: " .. show( err ) )
		checkSame( { lib.pathForFile( "essential/a.txt", { assetPackId = "essential" } ) },
			{ UNLOCALIZED .. "/essential/a.txt", "CachesDirectory" }, "essential after a relaunch" )
		emulator._backend.saveRemovedAssetPacks( { "a", "b" } )
		checkSame( launch()._backend.loadRemovedAssetPacks(), { "a", "b" }, "saved record" )
	end },

	{ "downloads: timing, began, progress about every 100 ms, finished, then the call's listener", function()
		local world = newWorld()
		filePack( world, "dl", "onDemand", { "a.txt" } )
		filePack( world, "quick", "onDemand", { "a.txt" } )
		filePack( world, "instant", "onDemand", { "a.txt" } )
		local emulator = launch( { bytesPerSecond = 8 } )
		local lib = loadFront( emulator )
		local events = watchDownloads( world, lib )
		lib.ensureLocalAvailability( { id = "dl" }, recorder( world, events ) )
		checkSame( events, {}, "events before the call returned" )
		world.clock.advance( 951 )
		check( not lib.assetPackIsAvailableLocally( "dl" ), "local before the download's end" )
		checkSame( listFiles( world.caches .. "/" .. DEVICE .. "/files" ), {}, "files before the download's end" )
		world.clock.advance( 50 )
		checkSame( timeline( events ), append( downloadLines( "dl", 1, 1000 ), { "ensureLocalAvailability dl@1001" } ),
			"timeline" )
		for k = 1, 10 do
			local fraction = 100 * k / 1000
			checkSame( events[k + 1].progress,
				{ fractionCompleted = fraction, completedUnitCount = math.floor( 8 * fraction ), totalUnitCount = 8 },
				"progress " .. k )
		end
		check( events[#events].error == nil, "listener error " .. show( events[#events].error ) )
		check( lib.assetPackIsAvailableLocally( "dl" ), "dl is not local" )
		check( readFile( world.caches .. "/" .. UNLOCALIZED .. "/dl/a.txt" ) == "dl a.txt", "dl's file" )
		check( not exists( world.caches .. "/" .. DEVICE .. "/staging" ), "the staging folder is left" )
		checkSame( deviceState( world ).packs.dl, { files = { { path = "dl/a.txt", size = 8 } } }, "state.json" )

		emulator.configure( { downloadDuration = 0.25 } )
		local start = world.clock.now
		events = watchDownloads( world, lib )
		lib.ensureLocalAvailability( { id = "quick" }, recorder( world, events ) )
		world.clock.advance( 1000 )
		checkSame( timeline( events ), append( downloadLines( "quick", start + 1, 250 ),
			{ "ensureLocalAvailability quick@" .. ( start + 251 ) } ), "downloadDuration wins over bytesPerSecond" )
		emulator.configure( { downloadDuration = 0 } )
		events = watchDownloads( world, lib )
		lib.ensureLocalAvailability( { id = "instant" }, recorder( world, events ) )
		world.clock.advance( 1 )
		checkSame( #events, 4, "downloadDuration 0: " .. show( timeline( events ) ) )
		check( events[2].progress.fractionCompleted == 1, "downloadDuration 0 progress" )

		events = watchDownloads( world, lib )
		lib.ensureLocalAvailability( { id = "dl" }, recorder( world, events ) )
		world.clock.advance( 1000 )
		checkSame( timeline( events ), { "ensureLocalAvailability dl@" .. ( world.clock.now - 999 ) }, "a local pack" )
		checkError( call( world, lib.ensureLocalAvailability, { id = "none" } ).error,
			managedError( 0, "assetPackNotFound", "none" ), "an unknown pack" )
	end },

	{ "downloads: the downloading bit, and a call joining the download in flight", function()
		local world = newWorld()
		filePack( world, "dl", "onDemand", { "a.txt" } )
		local lib = loadFront( launch( { bytesPerSecond = 8 } ) )
		local events = watchDownloads( world, lib )
		lib.ensureLocalAvailability( { id = "dl" }, recorder( world, events ) )
		world.clock.advance( 300 )
		lib.ensureLocalAvailability( { id = "dl" }, { requireLatestVersion = true }, recorder( world, events ) )
		checkSame( statusNames( call( world, lib.getStatusOfAssetPack, "dl" ).status ), { "downloadAvailable", "downloading" },
			"store status while downloading" )
		checkSame( statusNames( call( world, lib.getLocalStatusOfAssetPack, "dl" ).status ), { "downloading" },
			"local status while downloading" )
		world.clock.advance( 1000 )
		checkSame( timeline( events ), append( downloadLines( "dl", 1, 1000 ),
			{ "ensureLocalAvailability dl@1001", "ensureLocalAvailability dl@1001" } ), "one download for both calls" )
		local bits = { "downloaded", "upToDate" }
		checkSame( statusNames( call( world, lib.getStatusOfAssetPack, "dl" ).status ), bits, "store status after" )
		checkSame( statusNames( call( world, lib.getLocalStatusOfAssetPack, "dl" ).status ), bits, "local status after" )
	end },

	{ "multi-pack: side by side; the first failure's error with successes and failures", function()
		local world = newWorld()
		filePack( world, "essential", "essential", { "a.txt" } )
		filePack( world, "one", "onDemand", { "a.txt" } )
		filePack( world, "two", "onDemand", { "a.txt" } )
		filePack( world, "small", "onDemand", { "a.txt" } )
		filePack( world, "big", "onDemand", { "a.txt", "b.txt" } )
		local emulator = launch( { bytesPerSecond = 9 } )
		local lib = loadFront( emulator )
		local events = watchDownloads( world, lib )
		lib.ensureLocalAvailabilityOfAssetPacks( { { id = "one" }, { id = "two" }, { id = "essential" } }, recorder( world, events ) )
		world.clock.advance( 1001 )
		local lines = {}
		for i = 1, 10 do
			local at = "@" .. ( i == 1 and 1 or 1 + 100 * ( i - 1 ) )
			lines[#lines + 1] = ( i == 1 and "began" or "progress" ) .. " one" .. at
			lines[#lines + 1] = ( i == 1 and "began" or "progress" ) .. " two" .. at
		end
		append( lines, { "progress one@1001", "finished one@1001", "progress two@1001", "finished two@1001",
			"ensureLocalAvailabilityOfAssetPacks nil@1001" } )
		checkSame( timeline( events ), lines, "side by side" )
		check( events[#events].error == nil, "error " .. show( events[#events].error ) )

		emulator.configure( { freeDiskSpace = 12 } )
		local event
		events = watchDownloads( world, lib )
		lib.ensureLocalAvailabilityOfAssetPacks( { { id = "essential" }, { id = "small" }, { id = "big" } },
			function( e ) event = e end )
		world.clock.advance( 2000 )
		check( event and event.isError, "no multi-pack error" )
		checkError( event.error, cocoaError( 640, "big" ), "the first failure's error" )
		checkSame( ids( event.successes ), { "essential", "small" }, "successes" )
		check( #event.failures == 1 and event.failures[1].assetPack.id == "big", "failures " .. show( event.failures ) )
		checkError( event.failures[1].error, cocoaError( 640, "big" ), "the failure's error" )
		checkSame( timeline( eventsOf( events, "big" ) ), { "failed big@" .. ( world.clock.now - 1999 ) }, "big sends no began" )

		event = call( world, lib.ensureLocalAvailabilityOfAssetPacks, { { id = "essential" }, { id = "none" } } )
		checkError( event.error, managedError( 0, "assetPackNotFound", "none" ), "an unknown pack" )
		checkSame( { ids( event.successes ), ids( { event.failures[1].assetPack } ) }, { { "essential" }, { "none" } },
			"successes and failures with an unknown pack" )
	end },

	{ "install-time: prefetch packs download at the first launch with events, and resume at a later load", function()
		local world = newWorld()
		filePack( world, "pre", "prefetch", { "a.txt" } )
		filePack( world, "kept", "prefetch", { "a.txt" } )
		filePack( world, "prefr", "prefetch", { "a.txt" }, { language = "fr" } )
		local lib = loadFront( launch( { downloadDuration = 1, offline = true } ) )
		local events = watchDownloads( world, lib )
		world.clock.advance( 1000 )
		checkSame( sorted( timeline( events ) ), { "failed kept@1", "failed pre@1" }, "offline at the first launch" )

		lib = loadFront( launch( { downloadDuration = 1 } ) )
		events = watchDownloads( world, lib )
		world.clock.advance( 500 )
		check( #events == 10 and events[1].phase == "began", "downloads at the next launch: " .. show( timeline( events ) ) )
		check( not lib.assetPackIsAvailableLocally( "pre" ), "pre is local mid-download" )

		local start = world.clock.now
		lib = loadFront( launch( { downloadDuration = 1 } ) )
		events = watchDownloads( world, lib )
		world.clock.advance( 2000 )
		local kept, pre = downloadLines( "kept", start + 1, 1000 ), downloadLines( "pre", start + 1, 1000 )
		checkSame( sorted( timeline( events ) ), sorted( append( {}, kept, pre ) ),
			"an interrupted prefetch completes at a later launch" )
		check( lib.assetPackIsAvailableLocally( "pre" ) and lib.assetPackIsAvailableLocally( "kept" ), "not local" )
		check( not lib.assetPackIsAvailableLocally( "prefr" ), "a localized pack with no resolved language" )
		check( not call( world, lib.removeAssetPack, "pre" ).isError, "remove" )

		lib = loadFront( launch() )
		events = watchDownloads( world, lib )
		world.clock.advance( 2000 )
		checkSame( events, {}, "a local or removed prefetch pack at a later launch" )
		check( not lib.assetPackIsAvailableLocally( "pre" ), "the removed prefetch pack came back" )
		lib.setResolvedLanguage( "fr" )
		lib = loadFront( launch() )
		world.clock.advance( 1000 )
		check( lib.assetPackIsAvailableLocally( "prefr" ), "the resolved language's prefetch pack" )
		check( readFile( world.caches .. "/" .. DEVICE .. "/files/fr/prefr/a.txt" ) == "prefr a.txt", "prefr's file" )
	end },

	{ "offline: store calls and downloads fail, local calls work, and the error override", function()
		local world = newWorld()
		filePack( world, "essential", "essential", { "a.txt" } )
		filePack( world, "ondemand", "onDemand", { "a.txt" } )
		local emulator = launch()
		local lib = loadFront( emulator )
		emulator.configure( { offline = true } )
		local storeCalls = {
			{ lib.getAssetPack, "ondemand" },
			{ lib.getAllAssetPacks },
			{ lib.getManifest },
			{ lib.getStatusOfAssetPack, "ondemand" },
			{ lib.getStatusRelativeToAssetPack, { id = "ondemand" } },
			{ lib.checkForUpdates },
		}
		for _, storeCall in ipairs( storeCalls ) do
			local event = call( world, unpack( storeCall ) )
			checkError( event.error, offlineError( storeCall[2] and "ondemand" ), event.type )
		end

		local events = watchDownloads( world, lib )
		lib.ensureLocalAvailability( { id = "ondemand" }, recorder( world, events ) )
		world.clock.advance( 1000 )
		local start = events[1] and events[1].at
		checkSame( timeline( events ), { "failed ondemand@" .. tostring( start ), "ensureLocalAvailability ondemand@" ..
			tostring( start ) }, "a download that cannot start" )
		checkError( events[1].error, offlineError( "ondemand" ), "failed event" )
		checkError( events[2].error, offlineError( "ondemand" ), "listener" )
		check( not exists( world.caches .. "/" .. UNLOCALIZED .. "/ondemand" ), "files of a failed download" )

		check( lib.assetPackIsAvailableLocally( "essential" ), "assetPackIsAvailableLocally" )
		checkSame( statusNames( call( world, lib.getLocalStatusOfAssetPack, "essential" ).status ), { "downloaded", "upToDate" },
			"getLocalStatusOfAssetPack" )
		check( lib.pathForFile( "essential/a.txt", { assetPackId = "essential" } ), "pathForFile" )
		check( lib.contentsAtPath( "essential/a.txt" ) == "essential a.txt", "contentsAtPath" )
		check( not call( world, lib.ensureLocalAvailability, { id = "essential" } ).isError, "ensure a local pack" )
		check( lib.setResolvedLanguage( "fr" ) and lib.getResolvedLanguage() == "fr", "language calls" )
		check( not call( world, lib.getLocallyAvailableLanguages ).isError, "getLocallyAvailableLanguages" )
		check( not call( world, lib.removeAssetPack, "essential" ).isError, "removeAssetPack" )

		emulator.configure( { offlineError = { domain = "TestDomain", code = 7, message = "no network" } } )
		local event = call( world, lib.ensureLocalAvailability, { id = "ondemand" } )
		checkError( event.error, { domain = "TestDomain", code = 7, assetPackId = "ondemand" }, "the override" )
		check( event.error.message == "no network", "override message " .. show( event.error.message ) )
		checkError( call( world, lib.getAllAssetPacks ).error, { domain = "TestDomain", code = 7 }, "store call override" )
		emulator.configure( { offlineError = false } )
		checkError( call( world, lib.ensureLocalAvailability, { id = "ondemand" } ).error, offlineError( "ondemand" ),
			"the default restored" )
		emulator.configure( { offline = false } )
		world.clock.advance( 5000 )
		check( lib.assetPackIsAvailableLocally( "ondemand" ) == false, "a failed download completed later" )
		check( not download( world, lib, "ondemand" ).isError, "online again" )
	end },

	{ "offline mid-flight: the download fails on the next tick and leaves no files", function()
		local world = newWorld()
		filePack( world, "dl", "onDemand", { "a.txt" } )
		local emulator = launch( { bytesPerSecond = 8 } )
		local lib = loadFront( emulator )
		local events = watchDownloads( world, lib )
		lib.ensureLocalAvailability( { id = "dl" }, recorder( world, events ) )
		world.clock.advance( 351 )
		emulator.configure( { offline = true } )
		world.clock.advance( 2000 )
		checkSame( timeline( events ), { "began dl@1", "progress dl@101", "progress dl@201", "progress dl@301",
			"failed dl@401", "ensureLocalAvailability dl@401" }, "timeline" )
		checkError( events[5].error, offlineError( "dl" ), "failed event" )
		checkError( events[6].error, offlineError( "dl" ), "listener" )
		check( not lib.assetPackIsAvailableLocally( "dl" ), "dl is local" )
		checkSame( listFiles( world.caches .. "/" .. DEVICE ), { "state.json" }, "files left" )
	end },

	{ "low disk space: at start, mid-flight, free-space accounting and the error override", function()
		local world = newWorld()
		for _, id in ipairs( { "a", "b", "c" } ) do
			filePack( world, id, "onDemand", { "a.txt" } )
		end
		local emulator = launch( { freeDiskSpace = 15, downloadDuration = 0 } )
		local lib = loadFront( emulator )
		check( not download( world, lib, "a" ).isError and not download( world, lib, "b" ).isError, "a and b fit in 15 bytes" )
		local events = watchDownloads( world, lib )
		checkError( download( world, lib, "c" ).error, cocoaError( 640, "c" ), "c needs more than the space left" )
		checkSame( { #events, events[1].phase }, { 1, "failed" }, "events of c" )
		checkError( events[1].error, cocoaError( 640, "c" ), "c's failed event" )
		check( not call( world, lib.removeAssetPack, "a" ).isError, "remove a" )
		check( not download( world, lib, "c" ).isError, "c fits once a is removed" )

		check( not call( world, lib.removeAssetPack, "b" ).isError, "remove b" )
		emulator.configure( { downloadDuration = 1, freeDiskSpace = 100 } )
		events = watchDownloads( world, lib )
		local start = world.clock.now
		lib.ensureLocalAvailability( { id = "b" }, recorder( world, events ) )
		world.clock.advance( 551 )
		emulator.configure( { freeDiskSpace = 3 } )
		world.clock.advance( 1000 )
		local lines = timeline( events )
		local failedAt = "b@" .. ( start + 601 )
		checkSame( { lines[#lines - 1], lines[#lines] }, { "failed " .. failedAt, "ensureLocalAvailability " .. failedAt },
			"below the remaining 4 bytes mid-flight" )
		checkError( events[#events].error, cocoaError( 640, "b" ), "mid-flight listener" )
		checkSame( listFiles( world.caches .. "/" .. UNLOCALIZED ), { "c/a.txt" }, "files left" )

		emulator.configure( { downloadDuration = 0, freeDiskSpace = 0,
			lowDiskSpaceError = { domain = "TestDomain", code = 9, message = "full" } } )
		checkError( download( world, lib, "b" ).error, { domain = "TestDomain", code = 9, assetPackId = "b" }, "the override" )
		emulator.configure( { lowDiskSpaceError = false } )
		checkError( download( world, lib, "b" ).error, cocoaError( 640, "b" ), "the default restored" )
		emulator.configure( { freeDiskSpace = false } )
		check( not download( world, lib, "b" ).isError, "unlimited space" )
	end },

	{ "removeAssetPack: a download in flight ends cancelled (3072), then the pack is removed", function()
		local world = newWorld()
		filePack( world, "dl", "onDemand", { "a.txt" } )
		local lib = loadFront( launch( { bytesPerSecond = 8 } ) )
		local events = watchDownloads( world, lib )
		lib.ensureLocalAvailability( { id = "dl" }, recorder( world, events ) )
		world.clock.advance( 301 )
		lib.removeAssetPack( "dl", recorder( world, events ) )
		world.clock.advance( 2000 )
		checkSame( timeline( events ), { "began dl@1", "progress dl@101", "progress dl@201", "progress dl@301",
			"failed dl@301", "ensureLocalAvailability dl@301", "removeAssetPack nil@302" }, "timeline" )
		checkError( events[5].error, cocoaError( 3072, "dl" ), "failed event" )
		checkError( events[6].error, cocoaError( 3072, "dl" ), "listener" )
		check( events[6].error.message == "The operation was cancelled.", "message " .. show( events[6].error.message ) )
		check( events[7].error == nil, "remove error " .. show( events[7].error ) )
		check( not lib.assetPackIsAvailableLocally( "dl" ), "dl is local" )
		checkSame( listFiles( world.caches .. "/" .. DEVICE .. "/files" ), {}, "files" )

		check( not download( world, lib, "dl" ).isError, "download" )
		check( lib.pathForFile( "dl/a.txt", { assetPackId = "dl" } ), "pathForFile after the download" )
		check( not call( world, lib.removeAssetPack, "dl" ).isError, "remove the downloaded pack" )
		local filename, err = lib.pathForFile( "dl/a.txt", { assetPackId = "dl" } )
		check( filename == nil and err.name == "assetPackNotAvailable" and err.assetPackId == "dl", "27.0: " .. show( err ) )
		checkError( select( 2, lib.pathForFile( "dl/a.txt" ) ), managedError( 1, "fileNotFound" ), "without the pack" )
	end },

	{ "removeAssetPack from the delegate's began: the download ends cancelled (3072) with one listener event", function()
		local world = newWorld()
		filePack( world, "dl", "onDemand", { "a.txt" } )
		local lib = loadFront( launch( { bytesPerSecond = 8 } ) )
		local phases, listened = {}, {}
		lib.setDelegate( function( event )
			phases[#phases + 1] = event.phase
			if event.phase == "began" then lib.removeAssetPack( "dl", function() end ) end
		end )
		lib.ensureLocalAvailability( { id = "dl" }, function( event ) listened[#listened + 1] = event end )
		world.clock.advance( 60000 )
		check( #listened == 1, #listened .. " listener events" )
		checkError( listened[1].error, cocoaError( 3072, "dl" ), "listener" )
		checkSame( phases, { "began", "failed" }, "delegate phases" )
		check( lib.assetPackIsAvailableLocally( "dl" ) == false, "dl is local" )
	end },

	{ "removed-pack record at 26.0: a removed pack is unavailable until a download brings it back", function()
		local world = newWorld()
		filePack( world, "dl", "onDemand", { "a.txt" } )
		local lib = loadFront( launch( { apiVersion = "26.0" } ) )
		local events = watchDownloads( world, lib )
		check( not download( world, lib, "dl" ).isError, "download" )
		checkSame( { events[1].phase, events[#events].phase }, { "began", "finished" }, "download events at 26.0" )
		check( lib.pathForFile( "dl/a.txt", { assetPackId = "dl" } ), "pathForFile after the download" )
		check( not call( world, lib.removeAssetPack, "dl" ).isError, "remove" )
		local filename, err = lib.pathForFile( "dl/a.txt", { assetPackId = "dl" } )
		check( filename == nil and err.name == "assetPackNotAvailable" and err.assetPackId == "dl", "26.0: " .. show( err ) )
		lib = loadFront( launch( { apiVersion = "26.0" } ) )
		check( lib.pathForFile( "dl/a.txt", { assetPackId = "dl" } ) == nil, "available after a relaunch" )
		check( not download( world, lib, "dl" ).isError, "download again" )
		checkSame( deviceState( world ).removedAssetPacks, {}, "the record after the download" )
		check( lib.pathForFile( "dl/a.txt", { assetPackId = "dl" } ), "pathForFile after downloading again" )
	end },

	{ "reset: downloads in flight end cancelled before the device is emptied", function()
		local world = newWorld()
		filePack( world, "one", "onDemand", { "a.txt" } )
		filePack( world, "two", "onDemand", { "a.txt" } )
		local emulator = launch( { bytesPerSecond = 9 } )
		local lib = loadFront( emulator )
		local events = watchDownloads( world, lib )
		lib.ensureLocalAvailability( { id = "one" }, recorder( world, events ) )
		lib.ensureLocalAvailability( { id = "two" }, recorder( world, events ) )
		world.clock.advance( 201 )
		local before = #events
		emulator.reset()
		world.clock.advance( 5000 )
		checkSame( { unpack( timeline( events ), before + 1 ) }, { "failed one@201", "ensureLocalAvailability one@201",
			"failed two@201", "ensureLocalAvailability two@201" }, "events from the reset on" )
		for i = before + 1, #events do
			checkError( events[i].error, cocoaError( 3072, events[i].id ), timeline( events )[i] )
		end
		check( not exists( world.caches .. "/" .. DEVICE ), "the emulator folder is left" )
		checkSame( statusNames( call( world, lib.getLocalStatusOfAssetPack, "one" ).status ), {}, "status after reset" )
	end },

	{ "reset from the delegate's progress: the download ends cancelled (3072) with one listener event, the device empty", function()
		local world = newWorld()
		filePack( world, "dl", "onDemand", { "a.txt" } )
		local emulator = launch( { bytesPerSecond = 8 } )
		local lib = loadFront( emulator )
		local phases, listened = {}, {}
		lib.setDelegate( function( event )
			phases[#phases + 1] = event.phase
			if event.phase == "progress" then emulator.reset() end
		end )
		lib.ensureLocalAvailability( { id = "dl" }, function( event ) listened[#listened + 1] = event end )
		world.clock.advance( 60000 )
		check( #listened == 1, #listened .. " listener events" )
		checkError( listened[1].error, cocoaError( 3072, "dl" ), "listener" )
		checkSame( phases, { "began", "progress", "failed" }, "delegate phases" )
		check( not exists( world.caches .. "/" .. DEVICE ), "the emulator folder is left" )
		check( lib.assetPackIsAvailableLocally( "dl" ) == false, "dl is local" )
	end },

	{ "gating: the emulator through the front at 26.0, 26.4 and 27.0", function()
		local world = newWorld()
		filePack( world, "essential", "essential", { "a.txt" } )
		local calls = {
			{ "26.0", "getAssetPack", "essential" },
			{ "26.0", "getAllAssetPacks" },
			{ "26.0", "getStatusOfAssetPack", "essential" },
			{ "26.0", "ensureLocalAvailability", { id = "essential" } },
			{ "26.0", "checkForUpdates" },
			{ "26.4", "getStatusRelativeToAssetPack", { id = "essential" } },
			{ "26.4", "getLocalStatusOfAssetPack", "essential" },
			{ "26.4", "ensureLocalAvailability", { id = "essential" }, { requireLatestVersion = true } },
			{ "27.0", "getManifest" },
			{ "27.0", "ensureLocalAvailabilityOfAssetPacks", { { id = "essential" } } },
			{ "27.0", "getLocallyAvailableLanguages" },
			{ "27.0", "reconcilePreferredLanguages" },
		}
		for _, version in ipairs( { "26.0", "26.4", "27.0" } ) do
			local lib = loadFront( launch( { apiVersion = version } ) )
			for _, gated in ipairs( calls ) do
				local event = call( world, lib[gated[2]], unpack( gated, 3 ) )
				local what = version .. " " .. gated[2] .. ( gated[4] and " with options" or "" )
				if gated[1] <= version then
					check( not event.isError, what .. ": " .. show( event.error ) )
				else
					check( event.isError and event.error.name == "unsupported", what .. " is not unsupported" )
				end
			end
			local isLocal, localError = lib.assetPackIsAvailableLocally( "essential" )
			check( version >= "26.4" and isLocal == true or localError.name == "unsupported",
				version .. " assetPackIsAvailableLocally" )
			local _, languageError = lib.getResolvedLanguage()
			check( ( languageError == nil ) == ( version >= "27.0" ), version .. " getResolvedLanguage" )
		end
	end },
}

if which == "--list" then
	for _, case in ipairs( cases ) do
		print( case[1] )
	end
	return
end
for _, case in ipairs( cases ) do
	if case[1] == which then return case[2]() end
end
error( "no case " .. tostring( which ), 0 )
