-- usage: lua cases.lua REPO --list | REPO CASE
-- --list prints the case ids; CASE runs that case against REPO/lua/plugin_backgroundAssets.lua and fails with a message
-- when it does not hold.
local repo, which = ...
local here = arg[0]:match( "^(.*)/" ) or "."
package.path = here .. "/?.lua;" .. repo .. "/lua/?.lua;" .. package.path
local newFake = require( "fake_backend" )
local FRONT = repo .. "/lua/plugin_backgroundAssets.lua"

-- The calls and the iOS version each needs, from the API's OS table.
local MINIMUMS = {
	setDelegate = "26.0",
	getAssetPack = "26.0",
	getAllAssetPacks = "26.0",
	getManifest = "27.0",
	getStatusOfAssetPack = "26.0",
	getStatusRelativeToAssetPack = "26.4",
	getLocalStatusOfAssetPack = "26.4",
	assetPackIsAvailableLocally = "26.4",
	ensureLocalAvailability = "26.0",
	ensureLocalAvailabilityOfAssetPacks = "27.0",
	checkForUpdates = "26.0",
	removeAssetPack = "26.0",
	urlForPath = "26.0",
	contentsAtPath = "26.0",
	fileForPath = "26.0",
	pathForFile = "26.0",
	getLocallyAvailableLanguages = "27.0",
	reconcilePreferredLanguages = "27.0",
	getResolvedLanguage = "27.0",
	setResolvedLanguage = "27.0",
}
local SYNC = {
	assetPackIsAvailableLocally = true,
	urlForPath = true,
	contentsAtPath = true,
	fileForPath = true,
	pathForFile = true,
	getResolvedLanguage = true,
	setResolvedLanguage = true,
}
local PATH_CALLS = { "urlForPath", "pathForFile", "contentsAtPath", "fileForPath" }
local PACK = { id = "packa" }

local INVOKE = {
	getAssetPack = function( lib, listener ) return lib.getAssetPack( "packa", listener ) end,
	getAllAssetPacks = function( lib, listener ) return lib.getAllAssetPacks( listener ) end,
	getManifest = function( lib, listener ) return lib.getManifest( listener ) end,
	getStatusOfAssetPack = function( lib, listener ) return lib.getStatusOfAssetPack( "packa", listener ) end,
	getStatusRelativeToAssetPack = function( lib, listener ) return lib.getStatusRelativeToAssetPack( PACK, listener ) end,
	getLocalStatusOfAssetPack = function( lib, listener ) return lib.getLocalStatusOfAssetPack( "packa", listener ) end,
	assetPackIsAvailableLocally = function( lib ) return lib.assetPackIsAvailableLocally( "packa" ) end,
	ensureLocalAvailability = function( lib, listener ) return lib.ensureLocalAvailability( PACK, listener ) end,
	ensureLocalAvailabilityOfAssetPacks = function( lib, listener )
		return lib.ensureLocalAvailabilityOfAssetPacks( { PACK }, listener )
	end,
	checkForUpdates = function( lib, listener ) return lib.checkForUpdates( listener ) end,
	removeAssetPack = function( lib, listener ) return lib.removeAssetPack( "packa", listener ) end,
	urlForPath = function( lib ) return lib.urlForPath( "packa/a.txt" ) end,
	contentsAtPath = function( lib ) return lib.contentsAtPath( "packa/a.txt" ) end,
	fileForPath = function( lib ) return lib.fileForPath( "packa/a.txt" ) end,
	pathForFile = function( lib ) return lib.pathForFile( "packa/a.txt" ) end,
	getLocallyAvailableLanguages = function( lib, listener ) return lib.getLocallyAvailableLanguages( listener ) end,
	reconcilePreferredLanguages = function( lib, listener ) return lib.reconcilePreferredLanguages( listener ) end,
	getResolvedLanguage = function( lib ) return lib.getResolvedLanguage() end,
	setResolvedLanguage = function( lib ) return lib.setResolvedLanguage( "fr" ) end,
}
-- the backend function a call reaches first, when it is not the call's own name
local REACHES = { urlForPath = "urlForPath", contentsAtPath = "urlForPath", fileForPath = "urlForPath", pathForFile = "urlForPath" }

local function load( version )
	local fake = newFake( version )
	return assert( loadfile( FRONT ) )( fake ), fake
end

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

local function collector()
	local events = {}
	return events, function( event ) events[#events + 1] = event end
end

local function raises( fn, expected )
	local ok, message = pcall( fn )
	check( not ok, "no error raised, expected " .. expected )
	check( message:find( expected, 1, true ), "error message: " .. message )
	check( message:find( "^[^:]*cases%.lua:%d+: " ), "error not reported at the caller: " .. message )
end

local function event( eventType, fields )
	local shaped = { name = "backgroundAssets", type = eventType, isError = false }
	for key, value in pairs( fields or {} ) do
		shaped[key] = value
	end
	return shaped
end

local function unsupportedError( callName )
	return {
		domain = "plugin.backgroundAssets",
		code = 1,
		name = "unsupported",
		message = callName .. " is not available on this platform or iOS version",
	}
end

local function gating( version )
	return function()
		local lib, fake = load( version )
		local expected = { getCapabilities = true }
		for name, minimum in pairs( MINIMUMS ) do
			expected[name] = tonumber( version ) >= tonumber( minimum )
		end
		local capabilities = lib.getCapabilities()
		checkSame( capabilities.calls, expected, "calls" )
		check( capabilities.isSupported == ( tonumber( version ) >= 26 ), "isSupported" )
		check( ( fake.delegate ~= nil ) == expected.setDelegate, "download handler registered at load" )
		for name, invoke in pairs( INVOKE ) do
			fake.log = {}
			local events, listener = collector()
			local _, err = invoke( lib, listener )
			local reached = fake.log[REACHES[name] or name] ~= nil
			fake.runDeferred()
			check( reached == expected[name], name .. ": backend reached is " .. tostring( reached ) )
			if not expected[name] then
				local refusal = SYNC[name] and err or ( events[1] and events[1].error )
				checkSame( refusal, unsupportedError( name ), name .. " error" )
			end
		end
	end
end

local cases = {
	{ "loads by require over the backend module; the smallest backend makes every call unsupported", function()
		local timers = {}
		-- the smallest backend the interface allows: info() with only the platform, and defer
		package.loaded.plugin_backgroundAssets_backend = {
			info = function() return { platform = "mac-sim" } end,
			defer = function( fn ) timers[#timers + 1] = fn end,
		}
		local lib = require( "plugin_backgroundAssets" )
		check( lib.name == "plugin.backgroundAssets" and lib.publisherId == "com.studycat", "name and publisherId" )
		local capabilities = lib.getCapabilities()
		check( capabilities.isSupported == false and capabilities.platform == "mac-sim", show( capabilities ) )
		check( capabilities.osVersion == nil and capabilities.hosting == nil, show( capabilities ) )
		local count = 0
		for name, isAvailable in pairs( capabilities.calls ) do
			check( isAvailable == ( name == "getCapabilities" ), name )
			count = count + 1
		end
		check( count == 21, "calls has " .. count .. " names" )
		local events, listener = collector()
		lib.getManifest( listener )
		check( #events == 0 and #timers == 1, "listener called before getManifest returned" )
		timers[1]()
		checkSame( events, { event( "getManifest", { isError = true, error = unsupportedError( "getManifest" ) } ) },
			"events" )
		local filename, err = lib.pathForFile( "packa/a.png" )
		check( filename == nil, "pathForFile gave a filename" )
		checkSame( err, unsupportedError( "pathForFile" ), "pathForFile error" )
		check( lib.setDelegate( listener ) == nil, "setDelegate" )
	end },

	{ "loads as a chunk called with a backend table", function()
		local lib = load( "27.0" )
		check( lib.name == "plugin.backgroundAssets" and lib.publisherId == "com.studycat", "name and publisherId" )
		check( package.loaded.plugin_backgroundAssets_backend == nil, "loaded the Simulator backend" )
		local capabilities = lib.getCapabilities()
		check( capabilities.isSupported and capabilities.platform == "ios" and capabilities.osVersion == "27.0" and
			capabilities.hosting == "apple", show( capabilities ) )
	end },

	{ "gating at 25.0", gating( "25.0" ) },
	{ "gating at 26.0", gating( "26.0" ) },
	{ "gating at 26.3", gating( "26.3" ) },
	{ "gating at 26.4", gating( "26.4" ) },
	{ "gating at 27.0", gating( "27.0" ) },

	{ "gating compares versions part by part", function()
		check( load( "26.10" ).getCapabilities().calls.getLocalStatusOfAssetPack, "26.10 is after 26.4" )
		check( not load( "26.3.9" ).getCapabilities().calls.getLocalStatusOfAssetPack, "26.3.9 is before 26.4" )
		check( load( "27" ).getCapabilities().calls.getManifest, "27 is 27.0" )
	end },

	{ "unsupported: nil and the error from sync calls, async errors on a later turn", function()
		local lib, fake = load( "25.0" )
		local events, listener = collector()
		lib.getAssetPack( "packa", listener )
		lib.removeAssetPack( "packa" )
		check( #events == 0, "listener called before getAssetPack returned" )
		fake.runDeferred()
		checkSame( events, { event( "getAssetPack", { isError = true, error = unsupportedError( "getAssetPack" ) } ) },
			"events" )
		local available, err = lib.assetPackIsAvailableLocally( "packa" )
		check( available == nil, "assetPackIsAvailableLocally gave a value" )
		checkSame( err, unsupportedError( "assetPackIsAvailableLocally" ), "error" )
		check( lib.setDelegate( listener ) == nil and fake.delegate == nil, "setDelegate passed on" )
	end },

	{ "async: a backend answering at once still dispatches on a later turn", function()
		local lib, fake = load( "27.0" )
		local events, listener = collector()
		lib.getAllAssetPacks( listener )
		check( #events == 0, "listener called before getAllAssetPacks returned" )
		fake.runDeferred()
		check( #events == 1 and not events[1].isError, show( events ) )
	end },

	{ "async: a backend answering later dispatches on its answer", function()
		local lib, fake = load( "27.0" )
		fake.hold = true
		local events, listener = collector()
		lib.getAssetPack( "packa", listener )
		check( #events == 0 and fake.pending.getAssetPack, "no pending getAssetPack" )
		fake.pending.getAssetPack( { id = "packa", downloadSize = 1, version = 2 } )
		checkSame( events, { event( "getAssetPack", { assetPack = { id = "packa", downloadSize = 1, version = 2 } } ) },
			"events" )
		check( #fake.deferred == 0, "deferred an answer that came after the call returned" )
	end },

	{ "async: table listeners and calls without a listener", function()
		local lib, fake = load( "27.0" )
		local got
		local listener = { backgroundAssets = function( self, received ) got = { self = self, event = received } end }
		lib.checkForUpdates( listener )
		fake.runDeferred()
		check( got and got.self == listener and got.event.type == "checkForUpdates", "table listener not called" )
		lib.checkForUpdates()
		lib.removeAssetPack( "packb" )
		lib.reconcilePreferredLanguages()
		fake.runDeferred()
		check( fake.log.checkForUpdates and fake.log.removeAssetPack and fake.log.reconcilePreferredLanguages,
			"a call without a listener did not run" )
	end },

	{ "arguments: a wrong type raises with its position", function()
		local lib = load( "27.0" )
		local listener = function() end
		raises( function() lib.getAssetPack( 1, listener ) end,
			"bad argument #1 to 'getAssetPack' (string expected, got number)" )
		raises( function() lib.getAssetPack( "packa" ) end,
			"bad argument #2 to 'getAssetPack' (listener expected, got nil)" )
		raises( function() lib.getStatusRelativeToAssetPack( "packa", listener ) end,
			"bad argument #1 to 'getStatusRelativeToAssetPack' (asset pack expected, got string)" )
		raises( function() lib.ensureLocalAvailability( PACK, 5, listener ) end,
			"bad argument #2 to 'ensureLocalAvailability' (table or nil expected, got number)" )
		raises( function() lib.ensureLocalAvailability( PACK, { requireLatestVersion = 1 }, listener ) end,
			"bad argument #2 to 'ensureLocalAvailability' (options.requireLatestVersion: boolean expected, got number)" )
		raises( function() lib.ensureLocalAvailability( PACK, {} ) end,
			"bad argument #3 to 'ensureLocalAvailability' (listener expected, got nil)" )
		raises( function() lib.ensureLocalAvailabilityOfAssetPacks( { PACK, {} }, listener ) end,
			"bad argument #1 to 'ensureLocalAvailabilityOfAssetPacks' ([2]: asset pack expected, got table)" )
		raises( function() lib.urlForPath( "packa/a.txt", { assetPackId = 1 } ) end,
			"bad argument #2 to 'urlForPath' (options.assetPackId: string expected, got number)" )
		raises( function() lib.pathForFile( nil ) end, "bad argument #1 to 'pathForFile' (string expected, got nil)" )
		raises( function() lib.setDelegate( 5 ) end, "bad argument #1 to 'setDelegate' (listener expected, got number)" )
		raises( function() lib.checkForUpdates( {} ) end,
			"bad argument #1 to 'checkForUpdates' (listener expected, got table)" )
		raises( function() lib.removeAssetPack( "packa", 5 ) end,
			"bad argument #2 to 'removeAssetPack' (listener expected, got number)" )
		raises( function() lib.setResolvedLanguage( 5 ) end,
			"bad argument #1 to 'setResolvedLanguage' (string or nil expected, got number)" )
		raises( function() load( "25.0" ).getManifest( 5 ) end,
			"bad argument #1 to 'getManifest' (listener expected, got number)" )
	end },

	{ "arguments: assetPackId with language is invalidArgument", function()
		local lib, fake = load( "27.0" )
		for _, name in ipairs( PATH_CALLS ) do
			local value, err = lib[name]( "packa/a.txt", { assetPackId = "packa", language = "fr" } )
			check( value == nil, name .. " gave a value" )
			checkSame( err, { domain = "plugin.backgroundAssets", code = 2, name = "invalidArgument",
				message = "options.assetPackId and options.language cannot be used together" }, name .. " error" )
		end
		check( fake.log.urlForPath == nil, "looked the path up" )
	end },

	{ "shapes: packs keep their fields and sort by id", function()
		local lib, fake = load( "27.0" )
		local events, listener = collector()
		fake.answers.getAssetPack = { { id = "packa", downloadSize = 5, version = 3, language = "fr", userInfo = "\0b",
			extra = true } }
		fake.answers.getAllAssetPacks = { { { id = "packc" }, { id = "packa" }, { id = "packb" } } }
		lib.getAssetPack( "packa", listener )
		lib.getAllAssetPacks( listener )
		fake.runDeferred()
		checkSame( fake.log.getAssetPack, { "packa" }, "backend arguments" )
		checkSame( events, {
			event( "getAssetPack", { assetPack = { id = "packa", downloadSize = 5, version = 3, language = "fr",
				userInfo = "\0b" } } ),
			event( "getAllAssetPacks", { assetPacks = { { id = "packa" }, { id = "packb" }, { id = "packc" } } } ),
		}, "events" )
	end },

	{ "shapes: status is a table of booleans", function()
		local lib, fake = load( "27.0" )
		local events, listener = collector()
		fake.answers.getStatusOfAssetPack = { 1 + 4 + 64 }
		fake.answers.getStatusRelativeToAssetPack = { 2 + 8 + 16 + 32 }
		lib.getStatusOfAssetPack( "packa", listener )
		lib.getStatusRelativeToAssetPack( PACK, listener )
		lib.getLocalStatusOfAssetPack( "packa", listener )
		fake.runDeferred()
		checkSame( fake.log.getStatusRelativeToAssetPack, { "packa" }, "backend arguments" )
		checkSame( events[1].status, { downloadAvailable = true, updateAvailable = false, upToDate = true,
			outOfDate = false, obsolete = false, downloading = false, downloaded = true }, "getStatusOfAssetPack" )
		checkSame( events[2].status, { downloadAvailable = false, updateAvailable = true, upToDate = false,
			outOfDate = true, obsolete = true, downloading = true, downloaded = false }, "getStatusRelativeToAssetPack" )
		checkSame( events[3], event( "getLocalStatusOfAssetPack", { status = { downloadAvailable = false,
			updateAvailable = false, upToDate = false, outOfDate = false, obsolete = false, downloading = false,
			downloaded = false } } ), "getLocalStatusOfAssetPack" )
	end },

	{ "shapes: manifest fields, localized packs by id then language, languages in order", function()
		local lib, fake = load( "27.0" )
		local events, listener = collector()
		fake.answers.getManifest = { {
			assetPacks = { { id = "packb" }, { id = "packa" } },
			primaryLanguage = "en",
			availableLanguages = { "fr", "en", "de" },
			resolvedLanguage = "fr",
			localizedAssetPacks = { { id = "speech", language = "fr" }, { id = "music", language = "en" },
				{ id = "speech", language = "en" } },
		} }
		lib.getManifest( listener )
		fake.answers.getManifest = { { assetPacks = { { id = "packa" } } } }
		lib.getManifest( listener )
		fake.runDeferred()
		checkSame( events[1], event( "getManifest", { manifest = {
			assetPacks = { { id = "packa" }, { id = "packb" } },
			primaryLanguage = "en",
			availableLanguages = { "fr", "en", "de" },
			resolvedLanguage = "fr",
			localizedAssetPacks = { { id = "music", language = "en" }, { id = "speech", language = "en" },
				{ id = "speech", language = "fr" } },
		} } ), "manifest" )
		checkSame( events[2].manifest, { assetPacks = { { id = "packa" } }, availableLanguages = {},
			localizedAssetPacks = {} }, "manifest without language data" )
	end },

	{ "manifest methods", function()
		local lib, fake = load( "27.0" )
		local events, listener = collector()
		fake.answers.getManifest = { {
			assetPacks = { { id = "packb" }, { id = "packa" } },
			localizedAssetPacks = { { id = "speech", language = "fr" }, { id = "music", language = "en" },
				{ id = "speech", language = "en" } },
		} }
		lib.getManifest( listener )
		fake.runDeferred()
		local manifest = events[1].manifest
		checkSame( manifest:assetPack( "packb" ), { id = "packb" }, "assetPack" )
		check( manifest:assetPack( "packz" ) == nil, "assetPack of an unknown id" )
		checkSame( manifest:localizedAssetPacksForLanguage( "en" ),
			{ { id = "music", language = "en" }, { id = "speech", language = "en" } }, "localizedAssetPacksForLanguage" )
		checkSame( manifest:localizedAssetPacksForLanguage( "de" ), {}, "localizedAssetPacksForLanguage of none" )
		raises( function() manifest:assetPack( 1 ) end, "bad argument #1 to 'assetPack' (string expected, got number)" )
		raises( function() manifest:localizedAssetPacksForLanguage() end,
			"bad argument #1 to 'localizedAssetPacksForLanguage' (string expected, got nil)" )
	end },

	{ "shapes: checkForUpdates sorts its ids, languages keep the backend's order", function()
		local lib, fake = load( "27.0" )
		local events, listener = collector()
		fake.answers.checkForUpdates = { { updatingIdentifiers = { "packc", "packa" }, removedIdentifiers = { "z", "y" } } }
		fake.answers.getLocallyAvailableLanguages = { { "fr", "en", "de" } }
		lib.checkForUpdates( listener )
		lib.getLocallyAvailableLanguages( listener )
		fake.runDeferred()
		checkSame( events, {
			event( "checkForUpdates", { updatingIdentifiers = { "packa", "packc" }, removedIdentifiers = { "y", "z" } } ),
			event( "getLocallyAvailableLanguages", { languages = { "fr", "en", "de" } } ),
		}, "events" )
	end },

	{ "shapes: download events by phase", function()
		local lib, fake = load( "26.0" )
		local events, listener = collector()
		lib.setDelegate( listener )
		check( type( fake.delegate ) == "function", "no handler passed to the backend" )
		local raw = { id = "packa", downloadSize = 9, version = 1 }
		local shaped = { id = "packa", downloadSize = 9, version = 1 }
		local offline = { domain = "NSURLErrorDomain", code = -1009, message = "offline" }
		fake.delegate( { phase = "began", assetPack = raw } )
		fake.delegate( { phase = "progress", assetPack = raw,
			progress = { fractionCompleted = 0.5, completedUnitCount = 5, totalUnitCount = 10 } } )
		fake.delegate( { phase = "paused", assetPack = raw } )
		fake.delegate( { phase = "failed", assetPack = raw, error = offline } )
		fake.delegate( { phase = "finished", assetPack = raw } )
		checkSame( events, {
			event( "download", { phase = "began", assetPack = shaped } ),
			event( "download", { phase = "progress", assetPack = shaped,
				progress = { fractionCompleted = 0.5, completedUnitCount = 5, totalUnitCount = 10 } } ),
			event( "download", { phase = "paused", assetPack = shaped } ),
			event( "download", { phase = "failed", assetPack = shaped, isError = true, error = offline } ),
			event( "download", { phase = "finished", assetPack = shaped } ),
		}, "events" )
		lib.setDelegate( nil )
		fake.delegate( { phase = "began", assetPack = raw } )
		check( #events == 5, "event after setDelegate(nil)" )
		check( type( fake.log.setDelegate[1] ) == "function", "setDelegate(nil) passed on" )
	end },

	{ "errors: names by domain and code, other errors keep domain and code", function()
		local lib, fake = load( "27.0" )
		local events, listener = collector()
		for code, name in pairs( { [0] = "assetPackNotFound", [1] = "fileNotFound", [2] = "localAvailabilityFailure" } ) do
			fake.answers.getAssetPack = { nil, { domain = "BAManagedErrorDomain", code = code, message = name,
				assetPackId = "packz" } }
			lib.getAssetPack( "packz", listener )
			fake.runDeferred()
			checkSame( events[#events], event( "getAssetPack", { isError = true, error = { domain = "BAManagedErrorDomain",
				code = code, name = name, message = name, assetPackId = "packz" } } ), name )
		end
		fake.answers.urlForPath = { nil, { domain = "NSCocoaErrorDomain", code = 513, message = "denied" } }
		local file, err = lib.urlForPath( "packa/a.txt" )
		check( file == nil, "urlForPath gave a path" )
		checkSame( err, { domain = "NSCocoaErrorDomain", code = 513, message = "denied" }, "513" )
		fake.answers.urlForPath = { nil, { domain = "plugin.backgroundAssets", code = 4, message = "gone" } }
		file, err = lib.urlForPath( "packa/a.txt" )
		checkSame( err, { domain = "plugin.backgroundAssets", code = 4, name = "fileNotFound", message = "gone" },
			"plugin domain" )
	end },

	{ "errors: a multi-pack failure carries sorted successes and failures", function()
		local lib, fake = load( "27.0" )
		local events, listener = collector()
		local gone = { domain = "BAManagedErrorDomain", code = 0, message = "gone", assetPackId = "packd" }
		local offline = { domain = "NSURLErrorDomain", code = -1009, message = "offline" }
		fake.answers.ensureLocalAvailabilityOfAssetPacks = { nil, {
			domain = "BAManagedErrorDomain", code = 2, message = "some failed",
			successes = { { id = "packc" }, { id = "packa" } },
			failures = { { assetPack = { id = "packd" }, error = gone }, { assetPack = { id = "packb" }, error = offline } },
		} }
		local packs = { { id = "packa" }, { id = "packb" }, { id = "packc" }, { id = "packd" } }
		lib.ensureLocalAvailabilityOfAssetPacks( packs, listener )
		fake.runDeferred()
		checkSame( fake.log.ensureLocalAvailabilityOfAssetPacks, { { "packa", "packb", "packc", "packd" }, false },
			"backend arguments" )
		checkSame( events[1], event( "ensureLocalAvailabilityOfAssetPacks", {
			isError = true,
			error = { domain = "BAManagedErrorDomain", code = 2, name = "localAvailabilityFailure", message = "some failed" },
			assetPacks = packs,
			successes = { { id = "packa" }, { id = "packc" } },
			failures = {
				{ assetPack = { id = "packb" }, error = offline },
				{ assetPack = { id = "packd" }, error = { domain = "BAManagedErrorDomain", code = 0, name = "assetPackNotFound",
					message = "gone", assetPackId = "packd" } },
			},
		} ), "event" )
	end },

	{ "requireLatestVersion: unsupported below 26.4, passed on from 26.4", function()
		for _, version in ipairs( { "26.0", "26.3" } ) do
			local lib, fake = load( version )
			local events, listener = collector()
			lib.ensureLocalAvailability( PACK, { requireLatestVersion = true }, listener )
			fake.runDeferred()
			check( fake.log.ensureLocalAvailability == nil, version .. ": passed on" )
			checkSame( events[1], event( "ensureLocalAvailability", { isError = true,
				error = unsupportedError( "ensureLocalAvailability with options.requireLatestVersion" ) } ),
				version .. " event" )
			lib.ensureLocalAvailability( PACK, { requireLatestVersion = false }, listener )
			checkSame( fake.log.ensureLocalAvailability, { "packa", false }, version .. " false" )
			fake.log.ensureLocalAvailability = nil
			lib.ensureLocalAvailability( PACK, listener )
			checkSame( fake.log.ensureLocalAvailability, { "packa", false }, version .. " absent" )
			fake.runDeferred()
			checkSame( events[3], event( "ensureLocalAvailability", { assetPack = PACK } ), version .. " success" )
		end
		for _, version in ipairs( { "26.4", "27.0" } ) do
			local lib, fake = load( version )
			lib.ensureLocalAvailability( PACK, { requireLatestVersion = true }, function() end )
			checkSame( fake.log.ensureLocalAvailability, { "packa", true }, version )
		end
	end },

	{ "requireLatestVersions: passed on at 27.0", function()
		local lib, fake = load( "27.0" )
		local events, listener = collector()
		lib.ensureLocalAvailabilityOfAssetPacks( { PACK }, { requireLatestVersions = true }, listener )
		checkSame( fake.log.ensureLocalAvailabilityOfAssetPacks, { { "packa" }, true }, "true" )
		lib.ensureLocalAvailabilityOfAssetPacks( { PACK }, listener )
		checkSame( fake.log.ensureLocalAvailabilityOfAssetPacks, { { "packa" }, false }, "absent" )
		fake.runDeferred()
		checkSame( events[1], event( "ensureLocalAvailabilityOfAssetPacks", { assetPacks = { PACK } } ), "event" )
	end },

	{ "D11: the file check gives fileNotFound for every path call", function()
		local lib, fake = load( "27.0" )
		for _, name in ipairs( PATH_CALLS ) do
			local value, err = lib[name]( "packa/a.txt" )
			check( value == nil, name .. " gave a value" )
			checkSame( err, { domain = "plugin.backgroundAssets", code = 4, name = "fileNotFound",
				message = "no file at packa/a.txt" }, name .. " error" )
		end
		checkSame( fake.log.fileExists, { "/container/packa/a.txt" }, "file checked" )
		check( fake.log.link == nil and fake.log.contentsAtPath == nil and fake.log.fileForPath == nil,
			"went past the file check" )
		fake.available.packa = true
		local _, err = lib.urlForPath( "packa/b.txt", { assetPackId = "packa" } )
		check( err.name == "fileNotFound" and err.assetPackId == "packa", show( err ) )
		fake.files["/container/packa/a.txt"] = true
		check( lib.urlForPath( "packa/a.txt" ) == "/container/packa/a.txt", "urlForPath of a file on disk" )
	end },

	{ "D11: the pack check asks the backend from 26.4", function()
		for _, version in ipairs( { "26.4", "27.0" } ) do
			local lib, fake = load( version )
			fake.files["/container/packa/a.png"] = true
			for _, name in ipairs( PATH_CALLS ) do
				local value, err = lib[name]( "packa/a.png", { assetPackId = "packa" } )
				check( value == nil, version .. " " .. name .. " gave a value" )
				checkSame( err, { domain = "plugin.backgroundAssets", code = 3, name = "assetPackNotAvailable",
					message = "asset pack packa is not available locally", assetPackId = "packa" }, version .. " " .. name )
			end
			check( fake.log.urlForPath == nil, version .. ": looked the path up" )
			lib.removeAssetPack( "packb" )
			fake.available.packa = true
			local filename, baseDirectory = lib.pathForFile( "packa/a.png", { assetPackId = "packa" } )
			check( filename == "links/packa/a.png" and baseDirectory == "CachesDirectory", version .. ": pathForFile" )
			checkSame( fake.log.assetPackIsAvailableLocally, { "packa" }, version .. ": asked" )
		end
	end },

	{ "D11: the removed-pack record decides the pack check below 26.4", function()
		for _, version in ipairs( { "26.0", "26.3" } ) do
			local lib, fake = load( version )
			fake.files["/container/packa/a.txt"] = true
			local function availability()
				local file, err = lib.urlForPath( "packa/a.txt", { assetPackId = "packa" } )
				return file ~= nil or err.name
			end
			check( availability() == true, version .. ": before removing" )
			fake.answers.removeAssetPack = { nil, { domain = "BAManagedErrorDomain", code = 0, message = "x" } }
			lib.removeAssetPack( "packa" )
			check( availability() == true, version .. ": after a failed remove" )
			fake.answers.removeAssetPack = { true }
			lib.removeAssetPack( "packa" )
			check( availability() == "assetPackNotAvailable", version .. ": after removing" )
			check( lib.urlForPath( "packa/a.txt" ) == "/container/packa/a.txt", version .. ": without assetPackId" )
			lib.ensureLocalAvailability( PACK, function() end )
			check( availability() == true, version .. ": after ensureLocalAvailability" )
			lib.removeAssetPack( "packa" )
			lib.setDelegate( function() end )
			fake.delegate( { phase = "finished", assetPack = { id = "packa" } } )
			check( availability() == true, version .. ": after a finished download" )
			check( fake.log.assetPackIsAvailableLocally == nil, version .. ": asked the backend" )
		end
	end },

	{ "D11: a finished download clears the record with no app delegate", function()
		for _, version in ipairs( { "26.0", "26.3" } ) do
			local lib, fake = load( version )
			fake.files["/container/packa/a.txt"] = true
			lib.removeAssetPack( "packa" )
			local _, err = lib.urlForPath( "packa/a.txt", { assetPackId = "packa" } )
			check( err and err.name == "assetPackNotAvailable", version .. ": after removing" )
			check( type( fake.delegate ) == "function", version .. ": no handler registered at load" )
			fake.delegate( { phase = "finished", assetPack = { id = "packa" } } )
			check( lib.urlForPath( "packa/a.txt", { assetPackId = "packa" } ) == "/container/packa/a.txt",
				version .. ": after a finished download" )
			checkSame( fake.stored, {}, version .. ": saved" )
		end
	end },

	{ "D11: the removed-pack record persists through the backend", function()
		local lib, fake = load( "26.3" )
		fake.stored = { "packb" }
		fake.files["/container/packb/a.txt"] = true
		local _, err = lib.urlForPath( "packb/a.txt", { assetPackId = "packb" } )
		check( err and err.name == "assetPackNotAvailable", "stored record not loaded" )
		lib.removeAssetPack( "packa" )
		checkSame( fake.stored, { "packa", "packb" }, "saved after a remove" )
		fake.log.saveRemovedAssetPacks = nil
		lib.removeAssetPack( "packa" )
		check( fake.log.saveRemovedAssetPacks == nil, "saved an unchanged record" )
		lib.ensureLocalAvailability( { id = "packb" }, function() end )
		checkSame( fake.stored, { "packa" }, "saved after ensureLocalAvailability" )
	end },

	{ "D11: a successful remove unlinks the pack", function()
		local lib, fake = load( "27.0" )
		local events, listener = collector()
		lib.removeAssetPack( "packa", listener )
		checkSame( fake.log.unlinkAssetPack, { "packa" }, "unlinked" )
		fake.runDeferred()
		checkSame( events, { event( "removeAssetPack" ) }, "events" )
		fake.log.unlinkAssetPack = nil
		fake.answers.removeAssetPack = { nil, { domain = "BAManagedErrorDomain", code = 0, message = "x" } }
		lib.removeAssetPack( "packb" )
		check( fake.log.unlinkAssetPack == nil, "unlinked after a failed remove" )
	end },

	{ "pathForFile returns the backend link's filename and base directory", function()
		local lib, fake = load( "26.0" )
		fake.files["/container/packa/img.png"] = true
		local filename, baseDirectory = lib.pathForFile( "packa/img.png" )
		check( filename == "links/packa/img.png" and baseDirectory == "CachesDirectory", tostring( filename ) )
		checkSame( fake.log.link, { "packa/img.png", "/container/packa/img.png" }, "link arguments" )
		local denied = { domain = "NSPOSIXErrorDomain", code = 13, message = "denied" }
		fake.link = function() return nil, denied end
		local value, err = lib.pathForFile( "packa/img.png" )
		check( value == nil, "pathForFile gave a filename" )
		checkSame( err, denied, "link error" )
	end },

	{ "path calls: options.language needs 27.0 and reaches the backend", function()
		local lib, fake = load( "26.4" )
		local value, err = lib.urlForPath( "a.txt", { language = "fr" } )
		check( value == nil, "26.4 gave a path" )
		checkSame( err, unsupportedError( "urlForPath with options.language" ), "26.4 error" )
		check( fake.log.urlForPath == nil, "26.4 looked the path up" )
		lib, fake = load( "27.0" )
		fake.files["/container/a.txt"] = true
		check( lib.contentsAtPath( "a.txt", { language = "fr" } ) == "contents of a.txt", "contentsAtPath" )
		checkSame( fake.log.urlForPath, { "a.txt", "fr" }, "urlForPath arguments" )
		checkSame( fake.log.contentsAtPath, { "a.txt", nil, "fr" }, "contentsAtPath arguments" )
	end },

	{ "contentsAtPath and fileForPath pass the pack id and return the backend's answer", function()
		local lib, fake = load( "26.4" )
		fake.available.packa = true
		fake.files["/container/packa/a.txt"] = true
		check( lib.contentsAtPath( "packa/a.txt", { assetPackId = "packa" } ) == "contents of packa/a.txt", "contents" )
		checkSame( fake.log.contentsAtPath, { "packa/a.txt", "packa" }, "contentsAtPath arguments" )
		local handle = lib.fileForPath( "packa/a.txt", { assetPackId = "packa" } )
		check( io.type( handle ) == "file", "fileForPath gave no open file" )
		handle:close()
		checkSame( fake.log.fileForPath, { "packa/a.txt", "packa" }, "fileForPath arguments" )
		local missing = { domain = "BAManagedErrorDomain", code = 1, message = "no file" }
		fake.contentsAtPath = function() return nil, missing end
		fake.fileForPath = function() return nil, missing end
		for _, name in ipairs( { "contentsAtPath", "fileForPath" } ) do
			local value, err = lib[name]( "packa/a.txt" )
			check( value == nil, name .. " gave a value" )
			checkSame( err, { domain = "BAManagedErrorDomain", code = 1, name = "fileNotFound", message = "no file" }, name )
		end
	end },

	{ "assetPackIsAvailableLocally and the resolved language reach the backend", function()
		local lib, fake = load( "27.0" )
		fake.available.packa = true
		check( lib.assetPackIsAvailableLocally( "packa" ) == true, "packa" )
		check( lib.assetPackIsAvailableLocally( "packb" ) == false, "packb" )
		check( select( "#", lib.getResolvedLanguage() ) == 1 and lib.getResolvedLanguage() == nil, "no language" )
		check( lib.setResolvedLanguage( "fr" ) == true and lib.getResolvedLanguage() == "fr", "fr" )
		check( lib.setResolvedLanguage( nil ) == true and lib.getResolvedLanguage() == nil, "nil" )
		checkSame( fake.log.setResolvedLanguage, {}, "setResolvedLanguage(nil) arguments" )
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
