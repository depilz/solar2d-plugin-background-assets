-- plugin.backgroundAssets: the public Lua API over a backend that supplies Apple's raw Background Assets data and the
-- native-only primitives (docs/backend.rst). Native code calls this chunk with its backend table; required as a module
-- (the Solar2D Simulator), it loads the backend module plugin_backgroundAssets_backend.
local backend = ...
if type( backend ) ~= "table" then
	backend = require( "plugin_backgroundAssets_backend" )
end

local EVENT_NAME = "backgroundAssets"
local PLUGIN_DOMAIN = "plugin.backgroundAssets"
local MANAGED_DOMAIN = "BAManagedErrorDomain"

-- The iOS version each call needs: the availability of its Objective-C counterpart.
local MINIMUM = {
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
local SUPPORTED_MINIMUM = "26.0"
local LATEST_VERSION_MINIMUM = "26.4"
local LANGUAGE_MINIMUM = "27.0"

local PLUGIN_CODES = { unsupported = 1, invalidArgument = 2, assetPackNotAvailable = 3, fileNotFound = 4 }
local ERROR_NAMES = {
	[MANAGED_DOMAIN] = { [0] = "assetPackNotFound", [1] = "fileNotFound", [2] = "localAvailabilityFailure" },
	[PLUGIN_DOMAIN] = {},
}
for name, code in pairs( PLUGIN_CODES ) do
	ERROR_NAMES[PLUGIN_DOMAIN][code] = name
end

-- BAAssetPackStatus option bits
local STATUS_FLAGS = {
	downloadAvailable = 1,
	updateAvailable = 2,
	upToDate = 4,
	outOfDate = 8,
	obsolete = 16,
	downloading = 32,
	downloaded = 64,
}

local OPTION_TYPES = {
	assetPackId = "string",
	language = "string",
	requireLatestVersion = "boolean",
	requireLatestVersions = "boolean",
}

local info = backend.info()

local function versionParts( version )
	local parts = {}
	for number in string.gmatch( version, "%d+" ) do
		parts[#parts + 1] = tonumber( number )
	end
	return parts
end

local apiVersion = info.apiVersion and versionParts( info.apiVersion )

local function available( minimum )
	if not apiVersion then return false end
	local need = versionParts( minimum )
	for i = 1, math.max( #apiVersion, #need ) do
		local have, want = apiVersion[i] or 0, need[i] or 0
		if have ~= want then return have > want end
	end
	return true
end

-- Argument checks. They raise at level 4, the public function's caller, so the public functions call them directly.

local function argError( callName, position, expected, value, field )
	local subject = field and ( field .. ": " ) or ""
	error( string.format( "bad argument #%d to '%s' (%s%s expected, got %s)", position, callName, subject, expected,
		type( value ) ), 4 )
end

local function isListener( value )
	return type( value ) == "function" or ( type( value ) == "table" and type( value[EVENT_NAME] ) == "function" )
end

local function checkType( callName, position, value, expected )
	if type( value ) ~= expected then argError( callName, position, expected, value ) end
end

local function checkListener( callName, position, value, isOptional )
	if not ( isListener( value ) or ( isOptional and value == nil ) ) then
		argError( callName, position, "listener", value )
	end
end

local function checkLanguage( callName, position, value )
	if value ~= nil and type( value ) ~= "string" then argError( callName, position, "string or nil", value ) end
end

local function isPack( value )
	return type( value ) == "table" and type( value.id ) == "string"
end

local function checkPack( callName, position, value )
	if not isPack( value ) then argError( callName, position, "asset pack", value ) end
end

local function checkPacks( callName, position, value )
	if type( value ) ~= "table" then argError( callName, position, "array of asset packs", value ) end
	for i, pack in ipairs( value ) do
		if not isPack( pack ) then argError( callName, position, "asset pack", pack, "[" .. i .. "]" ) end
	end
end

local function checkOptions( callName, position, options )
	if options == nil then return end
	if type( options ) ~= "table" then argError( callName, position, "table or nil", options ) end
	for field, expected in pairs( OPTION_TYPES ) do
		local value = options[field]
		if value ~= nil and type( value ) ~= expected then
			argError( callName, position, expected, value, "options." .. field )
		end
	end
end

-- Errors

local function pluginError( name, message, assetPackId )
	return { domain = PLUGIN_DOMAIN, code = PLUGIN_CODES[name], name = name, message = message, assetPackId = assetPackId }
end

local function unsupported( callName )
	return pluginError( "unsupported", callName .. " is not available on this platform or iOS version" )
end

local function toError( raw )
	local names = ERROR_NAMES[raw.domain]
	return {
		domain = raw.domain,
		code = raw.code,
		name = names and names[raw.code],
		message = raw.message,
		assetPackId = raw.assetPackId,
	}
end

-- Shapes

local function toPack( raw )
	return {
		id = raw.id,
		downloadSize = raw.downloadSize,
		version = raw.version,
		language = raw.language,
		userInfo = raw.userInfo,
	}
end

local function byIdThenLanguage( a, b )
	if a.id ~= b.id then return a.id < b.id end
	return ( a.language or "" ) < ( b.language or "" )
end

local function toPacks( raws )
	local packs = {}
	for i, raw in ipairs( raws or {} ) do
		packs[i] = toPack( raw )
	end
	table.sort( packs, byIdThenLanguage )
	return packs
end

local function copyArray( values )
	local copy = {}
	for i, value in ipairs( values or {} ) do
		copy[i] = value
	end
	return copy
end

local function sortedArray( values )
	local copy = copyArray( values )
	table.sort( copy )
	return copy
end

local function toStatus( bits )
	local status = {}
	for name, flag in pairs( STATUS_FLAGS ) do
		status[name] = math.floor( bits / flag ) % 2 == 1
	end
	return status
end

local function toProgress( raw )
	return {
		fractionCompleted = raw.fractionCompleted,
		completedUnitCount = raw.completedUnitCount,
		totalUnitCount = raw.totalUnitCount,
	}
end

local function toFailures( raws )
	local failures = {}
	for i, raw in ipairs( raws or {} ) do
		failures[i] = { assetPack = toPack( raw.assetPack ), error = toError( raw.error ) }
	end
	table.sort( failures, function( a, b ) return byIdThenLanguage( a.assetPack, b.assetPack ) end )
	return failures
end

local Manifest = {}
Manifest.__index = Manifest

function Manifest:assetPack( id )
	checkType( "assetPack", 1, id, "string" )
	for _, pack in ipairs( self.assetPacks ) do
		if pack.id == id then return pack end
	end
	return nil
end

function Manifest:localizedAssetPacksForLanguage( language )
	checkType( "localizedAssetPacksForLanguage", 1, language, "string" )
	local packs = {}
	for _, pack in ipairs( self.localizedAssetPacks ) do
		if pack.language == language then packs[#packs + 1] = pack end
	end
	return packs
end

local function toManifest( raw )
	return setmetatable( {
		assetPacks = toPacks( raw.assetPacks ),
		primaryLanguage = raw.primaryLanguage,
		availableLanguages = copyArray( raw.availableLanguages ),
		resolvedLanguage = raw.resolvedLanguage,
		localizedAssetPacks = toPacks( raw.localizedAssetPacks ),
	}, Manifest )
end

-- Events

local function dispatch( listener, event )
	if type( listener ) == "function" then
		listener( event )
	else
		listener[EVENT_NAME]( listener, event )
	end
end

local function newEvent( eventType, err )
	return { name = EVENT_NAME, type = eventType, isError = err ~= nil, error = err }
end

-- callAsync: starts the backend call when this OS has it, or else fails it as unsupported, and hands the call's one
-- event to the listener, never before callAsync returns. succeeded(event, result) and failed(event, rawError) add the
-- payload. refusedName, when given, names what is unsupported in place of callName.
local function callAsync( callName, minimum, listener, start, succeeded, failed, refusedName )
	local returned = false
	local function deliver( event )
		if not listener then return end
		if returned then return dispatch( listener, event ) end
		backend.defer( function() dispatch( listener, event ) end )
	end
	if not available( minimum ) then
		deliver( newEvent( callName, unsupported( refusedName or callName ) ) )
	else
		start( function( result, rawError )
			local event = newEvent( callName, rawError and toError( rawError ) )
			if not rawError and succeeded then succeeded( event, result ) end
			if rawError and failed then failed( event, rawError ) end
			deliver( event )
		end )
	end
	returned = true
end

-- The removed-pack record: the ids this plugin removed and that have not come back since, which stands in for
-- assetPackIsAvailableLocally below iOS 26.4. The backend persists it.

local removedIds

local function removedRecord()
	if not removedIds then
		removedIds = {}
		for _, id in ipairs( backend.loadRemovedAssetPacks() ) do
			removedIds[id] = true
		end
	end
	return removedIds
end

local function markRemoved( id, isRemoved )
	local record = removedRecord()
	if ( record[id] == true ) == isRemoved then return end
	record[id] = isRemoved or nil
	local ids = {}
	for removedId in pairs( record ) do
		ids[#ids + 1] = removedId
	end
	table.sort( ids )
	backend.saveRemovedAssetPacks( ids )
end

local function isLocallyAvailable( id )
	if available( MINIMUM.assetPackIsAvailableLocally ) then
		return backend.assetPackIsAvailableLocally( id )
	end
	return not removedRecord()[id]
end

-- Path calls: every one refuses a pack that is not locally available and a file that is not on disk.

local function refusePathCall( callName, options )
	if not available( MINIMUM[callName] ) then return unsupported( callName ) end
	if options.assetPackId and options.language then
		return pluginError( "invalidArgument", "options.assetPackId and options.language cannot be used together" )
	end
	if options.language and not available( LANGUAGE_MINIMUM ) then
		return unsupported( callName .. " with options.language" )
	end
	if options.assetPackId and not isLocallyAvailable( options.assetPackId ) then
		return pluginError( "assetPackNotAvailable", "asset pack " .. options.assetPackId .. " is not available locally",
			options.assetPackId )
	end
end

-- resolveFile: the file's path on disk after the path call's checks, or nil and an error
local function resolveFile( callName, path, options )
	local refusal = refusePathCall( callName, options )
	if refusal then return nil, refusal end
	local file, rawError = backend.urlForPath( path, options.language )
	if not file then return nil, toError( rawError ) end
	if not backend.fileExists( file ) then
		return nil, pluginError( "fileNotFound", "no file at " .. path, options.assetPackId )
	end
	return file
end

-- The library

local lib = { name = "plugin.backgroundAssets", publisherId = "com.studycat" }

function lib.getCapabilities()
	local calls = { getCapabilities = true }
	for callName, minimum in pairs( MINIMUM ) do
		calls[callName] = available( minimum )
	end
	return {
		isSupported = available( SUPPORTED_MINIMUM ),
		platform = info.platform,
		osVersion = info.osVersion,
		hosting = info.hosting,
		calls = calls,
	}
end

local delegate

local function onDownload( raw )
	if raw.phase == "finished" then markRemoved( raw.assetPack.id, false ) end
	if not delegate then return end
	local event = newEvent( "download", raw.error and toError( raw.error ) )
	event.phase = raw.phase
	event.assetPack = toPack( raw.assetPack )
	event.progress = raw.progress and toProgress( raw.progress )
	dispatch( delegate, event )
end

-- The handler stays registered whether or not the app sets a delegate: a finished download clears the record (D11).
if available( MINIMUM.setDelegate ) then backend.setDelegate( onDownload ) end

function lib.setDelegate( listener )
	checkListener( "setDelegate", 1, listener, true )
	if not available( MINIMUM.setDelegate ) then return end
	delegate = listener
end

function lib.getAssetPack( id, listener )
	checkType( "getAssetPack", 1, id, "string" )
	checkListener( "getAssetPack", 2, listener )
	callAsync( "getAssetPack", MINIMUM.getAssetPack, listener,
		function( done ) backend.getAssetPack( id, done ) end,
		function( event, raw ) event.assetPack = toPack( raw ) end )
end

function lib.getAllAssetPacks( listener )
	checkListener( "getAllAssetPacks", 1, listener )
	callAsync( "getAllAssetPacks", MINIMUM.getAllAssetPacks, listener,
		function( done ) backend.getAllAssetPacks( done ) end,
		function( event, raws ) event.assetPacks = toPacks( raws ) end )
end

function lib.getManifest( listener )
	checkListener( "getManifest", 1, listener )
	callAsync( "getManifest", MINIMUM.getManifest, listener,
		function( done ) backend.getManifest( done ) end,
		function( event, raw ) event.manifest = toManifest( raw ) end )
end

local function setStatus( event, bits )
	event.status = toStatus( bits )
end

function lib.getStatusOfAssetPack( id, listener )
	checkType( "getStatusOfAssetPack", 1, id, "string" )
	checkListener( "getStatusOfAssetPack", 2, listener )
	callAsync( "getStatusOfAssetPack", MINIMUM.getStatusOfAssetPack, listener,
		function( done ) backend.getStatusOfAssetPack( id, done ) end, setStatus )
end

function lib.getStatusRelativeToAssetPack( assetPack, listener )
	checkPack( "getStatusRelativeToAssetPack", 1, assetPack )
	checkListener( "getStatusRelativeToAssetPack", 2, listener )
	callAsync( "getStatusRelativeToAssetPack", MINIMUM.getStatusRelativeToAssetPack, listener,
		function( done ) backend.getStatusRelativeToAssetPack( assetPack.id, done ) end, setStatus )
end

function lib.getLocalStatusOfAssetPack( id, listener )
	checkType( "getLocalStatusOfAssetPack", 1, id, "string" )
	checkListener( "getLocalStatusOfAssetPack", 2, listener )
	callAsync( "getLocalStatusOfAssetPack", MINIMUM.getLocalStatusOfAssetPack, listener,
		function( done ) backend.getLocalStatusOfAssetPack( id, done ) end, setStatus )
end

function lib.assetPackIsAvailableLocally( id )
	checkType( "assetPackIsAvailableLocally", 1, id, "string" )
	if not available( MINIMUM.assetPackIsAvailableLocally ) then
		return nil, unsupported( "assetPackIsAvailableLocally" )
	end
	return backend.assetPackIsAvailableLocally( id )
end

function lib.ensureLocalAvailability( assetPack, options, listener )
	if listener == nil and isListener( options ) then options, listener = nil, options end
	checkPack( "ensureLocalAvailability", 1, assetPack )
	checkOptions( "ensureLocalAvailability", 2, options )
	checkListener( "ensureLocalAvailability", 3, listener )
	local requireLatestVersion = options ~= nil and options.requireLatestVersion == true
	local minimum = requireLatestVersion and LATEST_VERSION_MINIMUM or MINIMUM.ensureLocalAvailability
	callAsync( "ensureLocalAvailability", minimum, listener,
		function( done ) backend.ensureLocalAvailability( assetPack.id, requireLatestVersion, done ) end,
		function( event )
			markRemoved( assetPack.id, false )
			event.assetPack = assetPack
		end,
		function( event ) event.assetPack = assetPack end,
		requireLatestVersion and "ensureLocalAvailability with options.requireLatestVersion" or nil )
end

function lib.ensureLocalAvailabilityOfAssetPacks( assetPacks, options, listener )
	if listener == nil and isListener( options ) then options, listener = nil, options end
	checkPacks( "ensureLocalAvailabilityOfAssetPacks", 1, assetPacks )
	checkOptions( "ensureLocalAvailabilityOfAssetPacks", 2, options )
	checkListener( "ensureLocalAvailabilityOfAssetPacks", 3, listener )
	local ids = {}
	for i, assetPack in ipairs( assetPacks ) do
		ids[i] = assetPack.id
	end
	local requireLatestVersions = options ~= nil and options.requireLatestVersions == true
	callAsync( "ensureLocalAvailabilityOfAssetPacks", MINIMUM.ensureLocalAvailabilityOfAssetPacks, listener,
		function( done ) backend.ensureLocalAvailabilityOfAssetPacks( ids, requireLatestVersions, done ) end,
		function( event ) event.assetPacks = assetPacks end,
		function( event, rawError )
			event.assetPacks = assetPacks
			event.successes = toPacks( rawError.successes )
			event.failures = toFailures( rawError.failures )
		end )
end

function lib.checkForUpdates( listener )
	checkListener( "checkForUpdates", 1, listener, true )
	callAsync( "checkForUpdates", MINIMUM.checkForUpdates, listener,
		function( done ) backend.checkForUpdates( done ) end,
		function( event, raw )
			event.updatingIdentifiers = sortedArray( raw.updatingIdentifiers )
			event.removedIdentifiers = sortedArray( raw.removedIdentifiers )
		end )
end

function lib.removeAssetPack( id, listener )
	checkType( "removeAssetPack", 1, id, "string" )
	checkListener( "removeAssetPack", 2, listener, true )
	callAsync( "removeAssetPack", MINIMUM.removeAssetPack, listener,
		function( done ) backend.removeAssetPack( id, done ) end,
		function()
			markRemoved( id, true )
			backend.unlinkAssetPack( id )
		end )
end

function lib.urlForPath( path, options )
	checkType( "urlForPath", 1, path, "string" )
	checkOptions( "urlForPath", 2, options )
	return resolveFile( "urlForPath", path, options or {} )
end

function lib.pathForFile( path, options )
	checkType( "pathForFile", 1, path, "string" )
	checkOptions( "pathForFile", 2, options )
	local file, err = resolveFile( "pathForFile", path, options or {} )
	if not file then return nil, err end
	local filename, baseDirectory = backend.link( path, file )
	if not filename then return nil, toError( baseDirectory ) end
	return filename, baseDirectory
end

function lib.contentsAtPath( path, options )
	checkType( "contentsAtPath", 1, path, "string" )
	checkOptions( "contentsAtPath", 2, options )
	options = options or {}
	local file, err = resolveFile( "contentsAtPath", path, options )
	if not file then return nil, err end
	local contents, rawError = backend.contentsAtPath( path, options.assetPackId, options.language )
	if not contents then return nil, toError( rawError ) end
	return contents
end

function lib.fileForPath( path, options )
	checkType( "fileForPath", 1, path, "string" )
	checkOptions( "fileForPath", 2, options )
	options = options or {}
	local file, err = resolveFile( "fileForPath", path, options )
	if not file then return nil, err end
	local handle, rawError = backend.fileForPath( path, options.assetPackId, options.language )
	if not handle then return nil, toError( rawError ) end
	return handle
end

function lib.getLocallyAvailableLanguages( listener )
	checkListener( "getLocallyAvailableLanguages", 1, listener )
	callAsync( "getLocallyAvailableLanguages", MINIMUM.getLocallyAvailableLanguages, listener,
		function( done ) backend.getLocallyAvailableLanguages( done ) end,
		function( event, languages ) event.languages = copyArray( languages ) end )
end

function lib.reconcilePreferredLanguages( listener )
	checkListener( "reconcilePreferredLanguages", 1, listener, true )
	callAsync( "reconcilePreferredLanguages", MINIMUM.reconcilePreferredLanguages, listener,
		function( done ) backend.reconcilePreferredLanguages( done ) end )
end

function lib.getResolvedLanguage()
	if not available( MINIMUM.getResolvedLanguage ) then return nil, unsupported( "getResolvedLanguage" ) end
	return backend.getResolvedLanguage()
end

function lib.setResolvedLanguage( language )
	checkLanguage( "setResolvedLanguage", 1, language )
	if not available( MINIMUM.setResolvedLanguage ) then return nil, unsupported( "setResolvedLanguage" ) end
	backend.setResolvedLanguage( language )
	return true
end

return lib
