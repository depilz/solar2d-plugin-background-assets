-- Demo: runs every plugin.backgroundAssets call and event, one after the other, against the demo packs (built by
-- tools/demo/packs.sh), and shows each call and its result as a "[demo] ..." line on the console (tests/sim reads them)
-- and on screen. In the Solar2D Simulator the plugin runs over its folder emulator, which takes the demo packs from the
-- repo's tools/demo/packs/; there the downloads, path calls and removal run as on a device.
local lfs = require( "lfs" )

-- tools/demo/packs/<id>.json; each pack holds its files under <id>/ in the packs' shared file namespace
local PACK_IDS = { "demoondemand", "demoprefetch" }
local REMOVED_ID = "demoondemand"

-- On-screen log: the latest lines, newest at the bottom
local MAX_LINES = 45
local lines = {}
local screen = display.newText( {
	text = "",
	x = display.screenOriginX + 4,
	y = display.screenOriginY + 4,
	width = display.actualContentWidth - 8,
	fontSize = 6,
	align = "left",
} )
screen.anchorX, screen.anchorY = 0, 0

local function log( line )
	line = "[demo] " .. line
	print( line )
	lines[#lines + 1] = line
	if #lines > MAX_LINES then table.remove( lines, 1 ) end
	screen.text = table.concat( lines, "\n" )
end

-- The Simulator only: the emulator module exists in the Simulator archives alone, and packsDirectory is relative to this
-- project folder. Configured before the plugin loads, as apiVersion and hosting would have to be.
if system.getInfo( "environment" ) == "simulator" then
	require( "plugin.backgroundAssets.emulator" ).configure( { packsDirectory = "../tools/demo/packs" } )
end

local ok, lib = pcall( require, "plugin.backgroundAssets" )
log( "require plugin.backgroundAssets: " .. ( ok and "ok" or "failed: " .. tostring( lib ) ) )
if not ok then
	log( "done" )
	return
end

-- Text for the plugin's values

local function listText( values )
	return #values > 0 and table.concat( values, ", " ) or "none"
end

local function errorText( err )
	return string.format( "error %s (%s %s)%s: %s", tostring( err.name ), tostring( err.domain ), tostring( err.code ),
		err.assetPackId and ( " pack " .. err.assetPackId ) or "", tostring( err.message ) )
end

local function packText( pack )
	return string.format( "%s v%s %s B%s", pack.id, tostring( pack.version ), tostring( pack.downloadSize ),
		pack.language and ( " " .. pack.language ) or "" )
end

local function packsText( packs )
	local texts = {}
	for i, pack in ipairs( packs ) do
		texts[i] = packText( pack )
	end
	return listText( texts )
end

local function statusText( status )
	local flags = {}
	for flag, isSet in pairs( status ) do
		if isSet then flags[#flags + 1] = flag end
	end
	table.sort( flags )
	return listText( flags )
end

local function manifestText( manifest )
	return string.format( "packs %s; primary %s; languages %s; resolved %s; localized %s",
		packsText( manifest.assetPacks ), tostring( manifest.primaryLanguage ), listText( manifest.availableLanguages ),
		tostring( manifest.resolvedLanguage ), packsText( manifest.localizedAssetPacks ) )
end

local function eventText( event )
	local parts = {}
	if event.isError then parts[#parts + 1] = errorText( event.error ) end
	if event.assetPack then parts[#parts + 1] = "assetPack " .. packText( event.assetPack ) end
	if event.assetPacks then parts[#parts + 1] = "assetPacks " .. packsText( event.assetPacks ) end
	if event.status then parts[#parts + 1] = "status " .. statusText( event.status ) end
	if event.manifest then parts[#parts + 1] = "manifest " .. manifestText( event.manifest ) end
	if event.languages then parts[#parts + 1] = "languages " .. listText( event.languages ) end
	if event.updatingIdentifiers then
		parts[#parts + 1] = "updating " .. listText( event.updatingIdentifiers ) .. "; removed " ..
			listText( event.removedIdentifiers )
	end
	if event.successes then parts[#parts + 1] = "successes " .. packsText( event.successes ) end
	for _, failure in ipairs( event.failures or {} ) do
		parts[#parts + 1] = "failure " .. failure.assetPack.id .. " " .. errorText( failure.error )
	end
	return #parts > 0 and table.concat( parts, "; " ) or "ok"
end

local function resultText( value, err )
	return err and errorText( err ) or tostring( value )
end

-- firstLine handle: the first line read from an open file, which it closes
local function firstLine( handle, openError )
	if not handle then return "failed: " .. tostring( openError ) end
	local line = handle:read( "*l" )
	handle:close()
	return "first line " .. tostring( line )
end

-- The flow: steps run one after the other; each calls its continue function when it is done

local steps = {}

local function syncStep( run )
	steps[#steps + 1] = function( continue )
		run()
		continue()
	end
end

-- asyncStep label start [onEvent]: start(listener) makes the call; its event is logged, handed to onEvent, and the flow
-- goes on
local function asyncStep( label, start, onEvent )
	steps[#steps + 1] = function( continue )
		start( function( event )
			log( label .. ": " .. eventText( event ) )
			if onEvent then onEvent( event ) end
			continue()
		end )
	end
end

local function runFrom( index )
	local step = steps[index]
	if not step then return log( "done" ) end
	step( function() runFrom( index + 1 ) end )
end

-- The pack tables the calls take: from getAssetPack, or the bare id when it gave none
local packs = {}
for _, id in ipairs( PACK_IDS ) do
	packs[id] = { id = id }
end

local function allPacks()
	local list = {}
	for i, id in ipairs( PACK_IDS ) do
		list[i] = packs[id]
	end
	return list
end

local imageCount = 0

-- loadThroughLink: pathForFile's filename and base directory handed to load (display.newImage or audio.loadSound)
local function loadThroughLink( label, path, options, loaderName, load )
	local filename, baseDirectory = lib.pathForFile( path, options )
	if not filename then return log( "pathForFile " .. path .. label .. ": " .. errorText( baseDirectory ) ) end
	local loaded = load( filename, baseDirectory )
	log( string.format( "pathForFile %s%s: %s, %s %s", path, label, filename, loaderName, loaded and "ok" or "failed" ) )
	return loaded
end

-- runPathCalls: every path call on pack id's files; returns urlForPath's file for the text, if any
local function runPathCalls( id, options, label )
	local image = loadThroughLink( label, id .. "/image.png", options, "display.newImage", display.newImage )
	if image then
		imageCount = imageCount + 1
		image.x, image.y = display.contentWidth - 40 * imageCount, display.contentHeight - 40
	end
	local sound = loadThroughLink( label, id .. "/sound.wav", options, "audio.loadSound", audio.loadSound )
	if sound then audio.play( sound ) end

	local textPath = id .. "/text.txt"
	local file, err = lib.urlForPath( textPath, options )
	log( "urlForPath " .. textPath .. label .. ": " ..
		( file and ( file .. ", io.open " .. firstLine( io.open( file, "r" ) ) ) or errorText( err ) ) )
	local contents, contentsError = lib.contentsAtPath( textPath, options )
	log( "contentsAtPath " .. textPath .. label .. ": " ..
		( contents and ( #contents .. " bytes" ) or errorText( contentsError ) ) )
	local handle, handleError = lib.fileForPath( textPath, options )
	log( "fileForPath " .. textPath .. label .. ": " ..
		( handle and ( "open file, " .. firstLine( handle ) ) or errorText( handleError ) ) )
	return file
end

local function onDownload( event )
	local progress = event.progress and string.format( " %.0f%% (%s of %s)", event.progress.fractionCompleted * 100,
		tostring( event.progress.completedUnitCount ), tostring( event.progress.totalUnitCount ) ) or ""
	log( string.format( "download %s %s%s%s", event.phase, event.assetPack.id, progress,
		event.isError and ( ": " .. errorText( event.error ) ) or "" ) )
end

syncStep( function()
	local capabilities = lib.getCapabilities()
	log( string.format( "getCapabilities: isSupported=%s platform=%s osVersion=%s hosting=%s",
		tostring( capabilities.isSupported ), tostring( capabilities.platform ), tostring( capabilities.osVersion ),
		tostring( capabilities.hosting ) ) )
	local calls = {}
	for name, isAvailable in pairs( capabilities.calls ) do
		if isAvailable then calls[#calls + 1] = name end
	end
	table.sort( calls )
	log( "getCapabilities calls: " .. listText( calls ) )
end )

syncStep( function()
	lib.setDelegate( onDownload )
	log( "setDelegate: download events go to the demo's log" )
end )

asyncStep( "getAllAssetPacks", lib.getAllAssetPacks )
asyncStep( "getManifest", lib.getManifest )

local urlsBeforeRemove = {}
for _, id in ipairs( PACK_IDS ) do
	asyncStep( "getAssetPack " .. id, function( listener ) lib.getAssetPack( id, listener ) end,
		function( event ) packs[id] = event.assetPack or packs[id] end )
	asyncStep( "getStatusOfAssetPack " .. id, function( listener ) lib.getStatusOfAssetPack( id, listener ) end )
	asyncStep( "getStatusRelativeToAssetPack " .. id,
		function( listener ) lib.getStatusRelativeToAssetPack( packs[id], listener ) end )
	asyncStep( "getLocalStatusOfAssetPack " .. id,
		function( listener ) lib.getLocalStatusOfAssetPack( id, listener ) end )
	syncStep( function()
		log( "assetPackIsAvailableLocally " .. id .. ": " .. resultText( lib.assetPackIsAvailableLocally( id ) ) )
	end )
	asyncStep( "ensureLocalAvailability " .. id,
		function( listener ) lib.ensureLocalAvailability( packs[id], listener ) end )
	syncStep( function() urlsBeforeRemove[id] = runPathCalls( id, { assetPackId = id }, "" ) end )
end

asyncStep( "ensureLocalAvailabilityOfAssetPacks",
	function( listener ) lib.ensureLocalAvailabilityOfAssetPacks( allPacks(), listener ) end )
asyncStep( "checkForUpdates", lib.checkForUpdates )
asyncStep( "getLocallyAvailableLanguages", lib.getLocallyAvailableLanguages )
asyncStep( "reconcilePreferredLanguages", lib.reconcilePreferredLanguages )

syncStep( function()
	local language, err = lib.getResolvedLanguage()
	log( "getResolvedLanguage: " .. resultText( language, err ) )
	log( "setResolvedLanguage " .. tostring( language ) .. ": " .. resultText( lib.setResolvedLanguage( language ) ) )
end )

-- the other pack's path calls while the remove is in flight: they wait for it (D12), and none may give a 513
local KEPT_ID = "demoprefetch"
steps[#steps + 1] = function( continue )
	lib.removeAssetPack( REMOVED_ID, function( event )
		log( "removeAssetPack " .. REMOVED_ID .. ": " .. eventText( event ) )
		continue()
	end )
	local started = system.getTimer()
	runPathCalls( KEPT_ID, { assetPackId = KEPT_ID }, " during remove of " .. REMOVED_ID )
	log( string.format( "path calls during remove took %.0f ms", system.getTimer() - started ) )
end

syncStep( function()
	log( "assetPackIsAvailableLocally " .. REMOVED_ID .. " after remove: " ..
		resultText( lib.assetPackIsAvailableLocally( REMOVED_ID ) ) )
	-- a raw check, past the plugin, of whether the removed pack's file left the disk
	local file = urlsBeforeRemove[REMOVED_ID]
	log( "after remove, the file urlForPath gave before it: " ..
		( file and ( file .. " exists=" .. tostring( lfs.attributes( file, "mode" ) ~= nil ) ) or "none" ) )
	-- with the pack id, the pack check answers; without it, only the file check stands between a caller and the file
	runPathCalls( REMOVED_ID, { assetPackId = REMOVED_ID }, " after remove" )
	runPathCalls( REMOVED_ID, nil, " after remove, no assetPackId" )
end )

runFrom( 1 )
