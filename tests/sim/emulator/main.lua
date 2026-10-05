-- The Simulator test project of plugin.backgroundAssets' folder emulator (plugin.backgroundAssets.emulator): runs every
-- call and every download event through the plugin in the Solar2D Simulator, on mac-sim or win32-sim, over the packs in
-- this project's packs/ folder. It prints one "[emulator] ok <case>" or "[emulator] FAIL <case>" line per case (a
-- failure's reason on the next line), then "[emulator] done: <n> passed, <m> failed" (tests/sim reads them). The cases
-- run one after the other, from an empty emulated device.
local lfs = require( "lfs" )

local PREFIX = "[emulator] "
local CASE_TIMEOUT_MS = 10000
local POLL_MS = 20
local PLATFORM = package.config:sub( 1, 1 ) == "\\" and "win32-sim" or "mac-sim"
local DEVICE = "plugin.backgroundAssets/emulator"

local emulator = require( "plugin.backgroundAssets.emulator" )
emulator.reset()
emulator.configure( { packsDirectory = "packs", downloadDuration = 0.3 } )
local lib = require( "plugin.backgroundAssets" )

-- Every download event, in order, as { phase, id, progress, error }; onDownload, when a case sets it, sees each one too
local downloadLog = {}
local onDownload
lib.setDelegate( function( event )
	downloadLog[#downloadLog + 1] = { phase = event.phase, id = event.assetPack.id, progress = event.progress,
		error = event.error }
	if onDownload then onDownload( event ) end
end )

-- Checks: each raises an error naming what did not hold

local function check( condition, message )
	if not condition then error( message, 2 ) end
end

local function checkEqual( actual, expected, what )
	if actual ~= expected then
		error( string.format( "%s: got %s, expected %s", what, tostring( actual ), tostring( expected ) ), 2 )
	end
end

-- checkError: err is an error of domain and code, for assetPackId when given
local function checkError( err, domain, code, assetPackId, what )
	check( type( err ) == "table", what .. ": no error" )
	checkEqual( err.domain .. " " .. tostring( err.code ), domain .. " " .. code, what .. " error" )
	if assetPackId then checkEqual( err.assetPackId, assetPackId, what .. " error assetPackId" ) end
end

local function checkOk( event, what )
	check( not event.isError, what .. ": " .. tostring( event.error and event.error.message ) )
end

local function idsOf( packs )
	local ids = {}
	for i, pack in ipairs( packs ) do
		ids[i] = pack.id
	end
	return table.concat( ids, " " )
end

-- phasesSince: the phases of id's download events after the first `from` logged, repeats merged ("began progress finished")
local function phasesSince( from, id )
	local phases = {}
	for i = from + 1, #downloadLog do
		local entry = downloadLog[i]
		if entry.id == id and entry.phase ~= phases[#phases] then phases[#phases + 1] = entry.phase end
	end
	return table.concat( phases, " " )
end

local function lastEvent( id, phase )
	for i = #downloadLog, 1, -1 do
		if downloadLog[i].id == id and downloadLog[i].phase == phase then return downloadLog[i] end
	end
end

local function readDeviceFile( name )
	local file = io.open( system.pathForFile( name, system.CachesDirectory ), "rb" )
	if not file then return nil end
	local contents = file:read( "*a" )
	file:close()
	return contents
end

local function text( id )
	return id .. " text\n"
end

-- The cases: run(t) ends with t.pass() or by raising an error; t.guard(fn) wraps a listener so its error fails the case

local cases = {}

local function case( name, run )
	cases[#cases + 1] = { name = name, run = run }
end

-- waitUntil: calls next once condition() holds, polling
local function waitUntil( t, condition, next )
	local function poll()
		if condition() then return next() end
		timer.performWithDelay( POLL_MS, t.guard( poll ) )
	end
	t.guard( poll )()
end

-- download: ensureLocalAvailability of pack id; done(event, from) gets its event and the download log's length before it
local function download( t, id, done )
	local from = #downloadLog
	lib.ensureLocalAvailability( { id = id }, t.guard( function( event ) done( event, from ) end ) )
end

case( "getCapabilities: supported on the platform package.config gives", function( t )
	local capabilities = lib.getCapabilities()
	check( capabilities.isSupported, "not supported" )
	checkEqual( capabilities.platform, PLATFORM, "platform" )
	checkEqual( capabilities.hosting, "apple", "hosting" )
	for name, isAvailable in pairs( capabilities.calls ) do
		check( isAvailable, name .. " not available" )
	end
	t.pass()
end )

case( "the essential pack is local at the first launch, with no events", function( t )
	checkEqual( lib.assetPackIsAvailableLocally( "emuessential" ), true, "emuessential local" )
	checkEqual( lib.contentsAtPath( "emuessential/text.txt", { assetPackId = "emuessential" } ), text( "emuessential" ),
		"contents" )
	checkEqual( phasesSince( 0, "emuessential" ), "", "emuessential events" )
	t.pass()
end )

case( "the prefetch pack downloads at the first launch: began, progress, finished", function( t )
	waitUntil( t, function() return lastEvent( "emuprefetch", "finished" ) end, function()
		checkEqual( phasesSince( 0, "emuprefetch" ), "began progress finished", "emuprefetch events" )
		checkEqual( lib.assetPackIsAvailableLocally( "emuprefetch" ), true, "emuprefetch local" )
		t.pass()
	end )
end )

case( "getAllAssetPacks and getManifest list the packs", function( t )
	lib.getAllAssetPacks( t.guard( function( event )
		checkOk( event, "getAllAssetPacks" )
		checkEqual( idsOf( event.assetPacks ), "emuessential emufrench emuondemand emuprefetch", "getAllAssetPacks" )
		lib.getManifest( t.guard( function( manifestEvent )
			checkOk( manifestEvent, "getManifest" )
			local manifest = manifestEvent.manifest
			checkEqual( idsOf( manifest.assetPacks ), "emuessential emuondemand emuprefetch", "assetPacks" )
			checkEqual( idsOf( manifest.localizedAssetPacks ), "emufrench", "localizedAssetPacks" )
			checkEqual( table.concat( manifest.availableLanguages, " " ), "fr", "availableLanguages" )
			t.pass()
		end ) )
	end ) )
end )

case( "getAssetPack gives the pack at version 1 with its size", function( t )
	lib.getAssetPack( "emuondemand", t.guard( function( event )
		checkOk( event, "getAssetPack" )
		checkEqual( event.assetPack.version, 1, "version" )
		checkEqual( event.assetPack.downloadSize, #text( "emuondemand" ), "downloadSize" )
		t.pass()
	end ) )
end )

case( "status calls: downloadAvailable before a download, downloading during it", function( t )
	lib.getStatusOfAssetPack( "emuondemand", t.guard( function( event )
		checkOk( event, "getStatusOfAssetPack" )
		check( event.status.downloadAvailable and not event.status.downloaded, "store status before" )
		lib.getStatusRelativeToAssetPack( { id = "emuondemand" }, t.guard( function( relativeEvent )
			check( relativeEvent.status.downloadAvailable, "relative status before" )
			-- a download for the status, cancelled at its end by removeAssetPack
			download( t, "emuondemand", function() end )
			lib.getLocalStatusOfAssetPack( "emuondemand", t.guard( function( localEvent )
				check( localEvent.status.downloading and not localEvent.status.downloaded, "local status during" )
				lib.removeAssetPack( "emuondemand", t.guard( function( removeEvent )
					checkOk( removeEvent, "removeAssetPack" )
					t.pass()
				end ) )
			end ) )
		end ) )
	end ) )
end )

case( "offline: store calls and a download fail with -1009, failed and no began; local calls work", function( t )
	emulator.configure( { offline = true } )
	lib.getAssetPack( "emuondemand", t.guard( function( event )
		checkError( event.error, "NSURLErrorDomain", -1009, "emuondemand", "getAssetPack" )
		download( t, "emuondemand", function( ensureEvent, from )
			emulator.configure( { offline = false } )
			checkError( ensureEvent.error, "NSURLErrorDomain", -1009, "emuondemand", "ensureLocalAvailability" )
			checkEqual( phasesSince( from, "emuondemand" ), "failed", "events" )
			checkError( lastEvent( "emuondemand", "failed" ).error, "NSURLErrorDomain", -1009, "emuondemand", "failed" )
			checkEqual( lib.assetPackIsAvailableLocally( "emuessential" ), true, "local call" )
			t.pass()
		end )
	end ) )
end )

case( "offline mid-flight: began, progress, then failed with -1009, no file left", function( t )
	onDownload = function( event )
		if event.phase == "progress" then emulator.configure( { offline = true } ) end
	end
	download( t, "emuondemand", function( event, from )
		emulator.configure( { offline = false } )
		checkError( event.error, "NSURLErrorDomain", -1009, "emuondemand", "ensureLocalAvailability" )
		checkEqual( phasesSince( from, "emuondemand" ), "began progress failed", "events" )
		checkEqual( lib.assetPackIsAvailableLocally( "emuondemand" ), false, "emuondemand local" )
		t.pass()
	end )
end )

case( "low disk space: a download fails at start with 640, failed and no began", function( t )
	emulator.configure( { freeDiskSpace = 1 } )
	download( t, "emuondemand", function( event, from )
		emulator.configure( { freeDiskSpace = false } )
		checkError( event.error, "NSCocoaErrorDomain", 640, "emuondemand", "ensureLocalAvailability" )
		checkEqual( phasesSince( from, "emuondemand" ), "failed", "events" )
		checkError( lastEvent( "emuondemand", "failed" ).error, "NSCocoaErrorDomain", 640, "emuondemand", "failed" )
		t.pass()
	end )
end )

case( "ensureLocalAvailability downloads: began, progress to the pack's size, finished, then the listener", function( t )
	download( t, "emuondemand", function( event, from )
		checkOk( event, "ensureLocalAvailability" )
		checkEqual( phasesSince( from, "emuondemand" ), "began progress finished", "events" )
		local progress = lastEvent( "emuondemand", "progress" ).progress
		checkEqual( progress.fractionCompleted, 1, "last fractionCompleted" )
		checkEqual( progress.completedUnitCount, #text( "emuondemand" ), "last completedUnitCount" )
		checkEqual( progress.totalUnitCount, #text( "emuondemand" ), "totalUnitCount" )
		lib.getLocalStatusOfAssetPack( "emuondemand", t.guard( function( statusEvent )
			check( statusEvent.status.downloaded and statusEvent.status.upToDate, "local status after" )
			t.pass()
		end ) )
	end )
end )

case( "path calls read the pack's file: urlForPath, pathForFile, contentsAtPath, fileForPath", function( t )
	local path, options = "emuondemand/text.txt", { assetPackId = "emuondemand" }
	local file, err = lib.urlForPath( path, options )
	check( file, "urlForPath: " .. tostring( err and err.message ) )
	local filename, baseDirectory = lib.pathForFile( path, options )
	checkEqual( filename, DEVICE .. "/files/Unlocalized/" .. path, "pathForFile filename" )
	checkEqual( baseDirectory, system.CachesDirectory, "pathForFile baseDirectory" )
	checkEqual( readDeviceFile( filename ), text( "emuondemand" ), "pathForFile file" )
	checkEqual( lib.contentsAtPath( path, options ), text( "emuondemand" ), "contentsAtPath" )
	local handle = lib.fileForPath( path, options )
	check( handle, "fileForPath gave no file" )
	checkEqual( handle:read( "*a" ), text( "emuondemand" ), "fileForPath" )
	handle:close()
	t.pass()
end )

case( "ensureLocalAvailabilityOfAssetPacks of local packs, and checkForUpdates", function( t )
	lib.ensureLocalAvailabilityOfAssetPacks( { { id = "emuessential" }, { id = "emuondemand" } }, t.guard( function( event )
		checkOk( event, "ensureLocalAvailabilityOfAssetPacks" )
		lib.checkForUpdates( t.guard( function( updatesEvent )
			checkOk( updatesEvent, "checkForUpdates" )
			checkEqual( #updatesEvent.updatingIdentifiers + #updatesEvent.removedIdentifiers, 0, "updating and removed" )
			t.pass()
		end ) )
	end ) )
end )

case( "language calls: resolved language, a localized pack, its language local", function( t )
	checkEqual( lib.setResolvedLanguage( "fr" ), true, "setResolvedLanguage" )
	checkEqual( lib.getResolvedLanguage(), "fr", "getResolvedLanguage" )
	lib.reconcilePreferredLanguages( t.guard( function( event )
		checkOk( event, "reconcilePreferredLanguages" )
		download( t, "emufrench", function( ensureEvent )
			checkOk( ensureEvent, "ensureLocalAvailability emufrench" )
			checkEqual( lib.contentsAtPath( "emufrench/text.txt", { language = "fr" } ), text( "emufrench" ), "contents" )
			lib.getLocallyAvailableLanguages( t.guard( function( languagesEvent )
				checkEqual( table.concat( languagesEvent.languages, " " ), "fr", "getLocallyAvailableLanguages" )
				t.pass()
			end ) )
		end )
	end ) )
end )

case( "removeAssetPack: the files go, path calls give assetPackNotAvailable", function( t )
	local filename = lib.pathForFile( "emuondemand/text.txt" )
	lib.removeAssetPack( "emuondemand", t.guard( function( event )
		checkOk( event, "removeAssetPack" )
		checkEqual( lib.assetPackIsAvailableLocally( "emuondemand" ), false, "emuondemand local" )
		checkEqual( readDeviceFile( filename ), nil, "removed file" )
		local contents, err = lib.contentsAtPath( "emuondemand/text.txt", { assetPackId = "emuondemand" } )
		checkEqual( contents, nil, "contentsAtPath" )
		checkEqual( err.name, "assetPackNotAvailable", "contentsAtPath error" )
		t.pass()
	end ) )
end )

case( "reset: an in-flight download fails with 3072, the device is emptied", function( t )
	onDownload = function( event )
		if event.phase == "began" then timer.performWithDelay( 1, function() emulator.reset() end ) end
	end
	download( t, "emuondemand", function( event, from )
		checkError( event.error, "NSCocoaErrorDomain", 3072, "emuondemand", "ensureLocalAvailability" )
		checkEqual( phasesSince( from, "emuondemand" ), "began failed", "events" )
		-- reset answers the download before it deletes the device
		timer.performWithDelay( 1, t.guard( function()
			checkEqual( lib.assetPackIsAvailableLocally( "emuessential" ), false, "emuessential local" )
			checkEqual( lfs.attributes( system.pathForFile( DEVICE, system.CachesDirectory ), "mode" ), nil, "device folder" )
			t.pass()
		end ) )
	end )
end )

-- The runner

local function runFrom( index, failed )
	local current = cases[index]
	if not current then
		return print( string.format( "%sdone: %d passed, %d failed", PREFIX, #cases - failed, failed ) )
	end
	local ended, watchdog = false, nil
	local function finish( reason )
		if ended then return end
		ended = true
		onDownload = nil
		timer.cancel( watchdog )
		print( PREFIX .. ( reason and "FAIL " or "ok " ) .. current.name )
		if reason then print( PREFIX .. "  " .. reason ) end
		timer.performWithDelay( 1, function() runFrom( index + 1, failed + ( reason and 1 or 0 ) ) end )
	end
	local t = { pass = function() finish() end }
	function t.guard( fn )
		return function( ... )
			if ended then return end
			local ok, message = pcall( fn, ... )
			if not ok then finish( tostring( message ) ) end
		end
	end
	watchdog = timer.performWithDelay( CASE_TIMEOUT_MS, function() finish( "timed out" ) end )
	t.guard( current.run )( t )
end

runFrom( 1, 0 )
