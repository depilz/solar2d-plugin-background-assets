-- plugin.backgroundAssets.emulator: the Solar2D Simulator's folder emulator of Background Assets (docs/backend.rst).
-- configure() and reset() are the app's API. _backend, not part of it, is the backend table over this module's settings
-- and emulated device, for the Simulator's backend file to return, so both share them whichever the app requires first.
local json = require( "json" )
local lfs = require( "lfs" )

local MANAGED_DOMAIN = "BAManagedErrorDomain"
local MANAGED_CODES = { assetPackNotFound = 0, fileNotFound = 1 }

-- BAAssetPackStatus option bits
local STATUS = { downloadAvailable = 1, upToDate = 4, obsolete = 16, downloading = 32, downloaded = 64 }

-- The raw errors a download fails with; the offlineError and lowDiskSpaceError settings replace the first two
local FAILURES = {
	offlineError = { domain = "NSURLErrorDomain", code = -1009, message = "The Internet connection appears to be offline." },
	lowDiskSpaceError = { domain = "NSCocoaErrorDomain", code = 640,
		message = "The operation couldn't be completed because there isn't enough space." },
	cancelled = { domain = "NSCocoaErrorDomain", code = 3072, message = "The operation was cancelled." },
}

-- The emulated device, as names relative to system.CachesDirectory. Names always use "/", which Windows accepts too.
local ROOT = "plugin.backgroundAssets/emulator"
local FILES = ROOT .. "/files"
local STAGING = ROOT .. "/staging"
local STATE_FILE = ROOT .. "/state.json"
local UNLOCALIZED = "Unlocalized"

local COPY_CHUNK = 1048576
local PROGRESS_INTERVAL = 100
local POLICIES = { "essential", "prefetch", "onDemand" }

-- Settings

local settings = { apiVersion = "27.0", hosting = "apple", bytesPerSecond = 5000000, offline = false }

-- set by the front's one info() call: from then on apiVersion and hosting are fixed
local frontLoaded = false

local function oneOf( values )
	local set = {}
	for _, value in ipairs( values ) do
		set[value] = true
	end
	return function( value ) return set[value] == true end
end

local function isNumberAtLeast( minimum, isClearable )
	return function( value )
		return ( isClearable and value == false ) or ( type( value ) == "number" and value >= minimum )
	end
end

local function isRawErrorOrFalse( value )
	return value == false or ( type( value ) == "table" and type( value.domain ) == "string" and
		type( value.code ) == "number" and type( value.message ) == "string" )
end

local OPTIONS = {
	packsDirectory = { "non-empty string", function( value ) return type( value ) == "string" and value ~= "" end },
	apiVersion = { '"26.0", "26.4" or "27.0"', oneOf( { "26.0", "26.4", "27.0" } ) },
	hosting = { '"apple" or "self"', oneOf( { "apple", "self" } ) },
	bytesPerSecond = { "number > 0", function( value ) return type( value ) == "number" and value > 0 end },
	downloadDuration = { "number >= 0 or false", isNumberAtLeast( 0, true ) },
	offline = { "boolean", function( value ) return type( value ) == "boolean" end },
	freeDiskSpace = { "number >= 0 or false", isNumberAtLeast( 0, true ) },
	offlineError = { "{ domain, code, message } or false", isRawErrorOrFalse },
	lowDiskSpaceError = { "{ domain, code, message } or false", isRawErrorOrFalse },
}
local LOAD_TIME = { apiVersion = true, hosting = true }

local function describe( value )
	if type( value ) == "string" then return string.format( "%q", value ) end
	if type( value ) == "table" then return "table" end
	return tostring( value )
end

-- Files and folders

local function absolute( name )
	return system.pathForFile( name, system.CachesDirectory )
end

local function parent( path )
	return path:match( "^(.*)/[^/]*$" )
end

local function joinPath( folder, name )
	return folder:gsub( "[/\\]+$", "" ) .. "/" .. name
end

local function isFile( path )
	return lfs.attributes( path, "mode" ) == "file"
end

local function isDirectory( path )
	return lfs.attributes( path, "mode" ) == "directory"
end

local function entries( folder )
	local names = {}
	for name in lfs.dir( folder ) do
		if name ~= "." and name ~= ".." then names[#names + 1] = name end
	end
	table.sort( names )
	return names
end

-- listFiles: the paths, relative to folder, of every file under it
local function listFiles( folder, prefix, files )
	files = files or {}
	for _, name in ipairs( entries( folder ) ) do
		local path = folder .. "/" .. name
		local relative = prefix and ( prefix .. "/" .. name ) or name
		if isDirectory( path ) then
			listFiles( path, relative, files )
		else
			files[#files + 1] = relative
		end
	end
	return files
end

-- makeFolders: creates the folder named relative to system.CachesDirectory one segment at a time, as lfs.mkdir needs
local function makeFolders( name )
	local prefix
	for segment in name:gmatch( "[^/]+" ) do
		prefix = prefix and ( prefix .. "/" .. segment ) or segment
		local path = absolute( prefix )
		if not isDirectory( path ) then lfs.mkdir( path ) end
	end
end

local function removeTree( path )
	if isDirectory( path ) then
		for _, name in ipairs( entries( path ) ) do
			removeTree( path .. "/" .. name )
		end
		lfs.rmdir( path )
	else
		os.remove( path )
	end
end

-- pruneFolders: removes the folder and then its parents up to FILES while they are empty
local function pruneFolders( name )
	while name and name ~= FILES and lfs.rmdir( absolute( name ) ) do
		name = parent( name )
	end
end

local function readFile( path )
	local file = io.open( path, "rb" )
	if not file then return nil end
	local contents = file:read( "*a" )
	file:close()
	return contents
end

local function writeFile( path, contents )
	local file = assert( io.open( path, "wb" ) )
	file:write( contents )
	file:close()
end

local function copyFile( source, destination )
	local input = assert( io.open( source, "rb" ) )
	local output = assert( io.open( destination, "wb" ) )
	for chunk in function() return input:read( COPY_CHUNK ) end do
		output:write( chunk )
	end
	input:close()
	output:close()
end

-- The device's state.json: { installed, resolvedLanguage, removedAssetPacks, packs }, where packs maps a local pack's id
-- to { language, files = { { path, size } } }

local state

local function device()
	if not state then
		local text = readFile( absolute( STATE_FILE ) )
		local saved = text and json.decode( text )
		state = type( saved ) == "table" and saved or {}
		state.packs = state.packs or {}
		state.removedAssetPacks = state.removedAssetPacks or {}
	end
	return state
end

local function saveState()
	makeFolders( ROOT )
	writeFile( absolute( STATE_FILE ), json.encode( device() ) )
end

-- Raw errors

local function managedError( name, message, assetPackId )
	return { domain = MANAGED_DOMAIN, code = MANAGED_CODES[name], message = message, assetPackId = assetPackId }
end

local function packNotFound( id )
	return managedError( "assetPackNotFound", "The asset pack " .. id .. " could not be found.", id )
end

local function fileNotFound( path, assetPackId )
	return managedError( "fileNotFound", "The file " .. path .. " could not be found.", assetPackId )
end

-- failure: a FAILURES error, or the setting replacing it, for the pack
local function failure( name, assetPackId )
	local base = settings[name] or FAILURES[name]
	return { domain = base.domain, code = base.code, message = base.message, assetPackId = assetPackId }
end

-- Pack sources: the ba-package manifests at the top level of packsDirectory

local function packsDirectory()
	local folder = settings.packsDirectory
	if not folder or folder:find( "^[/\\]" ) or folder:find( "^%a:[/\\]" ) then return folder end
	return joinPath( system.pathForFile( "", system.ResourceDirectory ), folder )
end

local function cleanPath( path )
	return ( path:gsub( "^%./", "" ):gsub( "/+$", "" ) )
end

-- globPattern: the Lua pattern of a UNIX glob, where * and ? do not cross "/"
local function globPattern( glob )
	local parts = { "^" }
	local i = 1
	while i <= #glob do
		local char = glob:sub( i, i )
		local close = char == "[" and glob:find( "]", i + 2, true )
		if char == "*" then
			parts[#parts + 1] = "[^/]*"
		elseif char == "?" then
			parts[#parts + 1] = "[^/]"
		elseif close then
			parts[#parts + 1] = "[" .. glob:sub( i + 1, close - 1 ):gsub( "^!", "^" ):gsub( "%%", "%%%%" ) .. "]"
			i = close
		else
			parts[#parts + 1] = char:gsub( "%W", "%%%0" )
		end
		i = i + 1
	end
	return table.concat( parts ) .. "$"
end

-- A selector's kinds, each with the key naming its destination for the two source/destination forms
local SELECTOR_KINDS = {
	file = false,
	directory = false,
	filePattern = false,
	fileSource = "fileDestination",
	directorySource = "directoryDestination",
	fileExclusion = false,
}
local DESTINATION_KEYS = { fileDestination = true, directoryDestination = true }

local function selectorKind( selector )
	if type( selector ) ~= "table" then return nil, "a selector is not an object" end
	local kind
	for key in pairs( selector ) do
		if SELECTOR_KINDS[key] ~= nil then
			kind = key
		elseif not DESTINATION_KEYS[key] then
			return nil, "unknown selector key '" .. tostring( key ) .. "'"
		end
	end
	return kind
end

-- selectFiles: the pack's files as { path, source } (its path in the pack, its file under root), sorted by path
local function selectFiles( root, selectors )
	local chosen, excluded = {}, {}
	local allFiles
	local function add( source, path )
		chosen[cleanPath( path )] = cleanPath( source )
		return true
	end
	local function addFolder( source, destination )
		source, destination = cleanPath( source ), cleanPath( destination )
		if not isDirectory( joinPath( root, source ) ) then return false end
		for _, file in ipairs( listFiles( joinPath( root, source ) ) ) do
			add( source .. "/" .. file, destination .. "/" .. file )
		end
		return true
	end
	local function addPattern( glob )
		allFiles = allFiles or listFiles( root )
		local pattern, found = globPattern( glob ), false
		for _, file in ipairs( allFiles ) do
			if file:find( pattern ) then found = add( file, file ) end
		end
		return found
	end
	local function addFile( source, destination )
		return isFile( joinPath( root, source ) ) and add( source, destination )
	end
	local SELECT = {
		file = function( selector ) return addFile( selector.file, selector.file ) end,
		directory = function( selector ) return addFolder( selector.directory, selector.directory ) end,
		filePattern = function( selector ) return addPattern( selector.filePattern ) end,
		fileSource = function( selector ) return addFile( selector.fileSource, selector.fileDestination ) end,
		directorySource = function( selector )
			return addFolder( selector.directorySource, selector.directoryDestination )
		end,
		fileExclusion = function( selector )
			excluded[cleanPath( selector.fileExclusion )] = true
			return true
		end,
	}

	for _, selector in ipairs( selectors ) do
		local kind, reason = selectorKind( selector )
		if reason then return nil, reason end
		local destinationKey = kind and SELECTOR_KINDS[kind]
		local isComplete = kind and type( selector[kind] ) == "string" and
			( not destinationKey or type( selector[destinationKey] ) == "string" )
		if not ( isComplete and SELECT[kind]( selector ) ) then
			return nil, "a selector names nothing (" .. json.encode( selector ) .. ")"
		end
	end

	local files = {}
	for path, source in pairs( chosen ) do
		if not excluded[source] then files[#files + 1] = { path = path, source = joinPath( root, source ) } end
	end
	table.sort( files, function( a, b ) return a.path < b.path end )
	return files
end

local function downloadPolicy( manifest )
	local policy = type( manifest.downloadPolicy ) == "table" and manifest.downloadPolicy or {}
	for _, name in ipairs( POLICIES ) do
		if policy[name] ~= nil then return name end
	end
	return "onDemand"
end

local function isForIOS( manifest )
	if type( manifest.platforms ) ~= "table" then return true end
	for _, platform in ipairs( manifest.platforms ) do
		if platform == "iOS" then return true end
	end
	return false
end

-- readManifest: the pack a manifest describes; nil when it is not for iOS; nil and the reason when it is bad
local function readManifest( folder, name )
	local manifest = json.decode( readFile( folder .. "/" .. name ) or "" )
	if type( manifest ) ~= "table" then return nil, "invalid JSON" end
	if type( manifest.assetPackID ) ~= "string" then return nil, "no assetPackID" end
	if not isForIOS( manifest ) then return nil end
	local root = type( manifest.sourceRoot ) == "string" and joinPath( folder, manifest.sourceRoot ) or folder
	local selectors = type( manifest.fileSelectors ) == "table" and manifest.fileSelectors or {}
	local files, reason = selectFiles( root, selectors )
	if not files then return nil, reason end
	local downloadSize = 0
	for _, file in ipairs( files ) do
		file.size = lfs.attributes( file.source, "size" )
		downloadSize = downloadSize + file.size
	end
	return {
		id = manifest.assetPackID,
		language = type( manifest.language ) == "string" and manifest.language or nil,
		userInfo = type( manifest.userInfo ) == "table" and json.encode( manifest.userInfo ) or nil,
		policy = downloadPolicy( manifest ),
		files = files,
		downloadSize = downloadSize,
	}
end

-- readSources: the packs in packsDirectory by id. A bad manifest is skipped with one printed line.
local function readSources()
	local sources = {}
	local folder = packsDirectory()
	if not folder or not isDirectory( folder ) then return sources end
	for _, name in ipairs( entries( folder ) ) do
		if name:find( "%.json$" ) and isFile( folder .. "/" .. name ) then
			local pack, reason = readManifest( folder, name )
			if pack and sources[pack.id] then pack, reason = nil, "duplicate assetPackID " .. pack.id end
			if pack then
				sources[pack.id] = pack
			elseif reason then
				print( "plugin.backgroundAssets.emulator: skipped " .. name .. ": " .. reason )
			end
		end
	end
	return sources
end

local function rawPack( pack )
	return { id = pack.id, downloadSize = pack.downloadSize, version = 1, language = pack.language, userInfo = pack.userInfo }
end

-- Local packs

local function languageFolder( language )
	return FILES .. "/" .. ( language or UNLOCALIZED )
end

local function removeStaging( id )
	removeTree( absolute( STAGING .. "/" .. id ) )
	lfs.rmdir( absolute( STAGING ) )
end

local function changeFreeDiskSpace( bytes )
	if settings.freeDiskSpace then settings.freeDiskSpace = math.max( 0, settings.freeDiskSpace + bytes ) end
end

-- installPack: copies the pack's files into a staging folder, then moves them into place and records the pack
local function installPack( pack )
	local staging = STAGING .. "/" .. pack.id
	for _, file in ipairs( pack.files ) do
		local staged = staging .. "/" .. file.path
		makeFolders( parent( staged ) )
		copyFile( file.source, absolute( staged ) )
	end
	local record = { language = pack.language, files = {} }
	for i, file in ipairs( pack.files ) do
		local destination = languageFolder( pack.language ) .. "/" .. file.path
		makeFolders( parent( destination ) )
		os.remove( absolute( destination ) )
		os.rename( absolute( staging .. "/" .. file.path ), absolute( destination ) )
		record.files[i] = { path = file.path, size = file.size }
	end
	removeStaging( pack.id )
	device().packs[pack.id] = record
	saveState()
end

local function deleteLocalPack( id )
	local record = device().packs[id]
	if not record then return end
	local size = 0
	for _, file in ipairs( record.files ) do
		local name = languageFolder( record.language ) .. "/" .. file.path
		os.remove( absolute( name ) )
		pruneFolders( parent( name ) )
		size = size + file.size
	end
	device().packs[id] = nil
	saveState()
	changeFreeDiskSpace( size )
end

-- Downloads

local delegate

-- the downloads in flight by pack id: { pack, raw, waiters (the done functions of the calls waiting on it), timer,
-- duration and elapsed (ms), completed (bytes) }
local downloads = {}

local function notify( event )
	if delegate then delegate( event ) end
end

-- isLive: whether the download is still the pack's one in flight; a delegate handler may have ended it
local function isLive( download )
	return downloads[download.raw.id] == download
end

-- downloadFailure: the raw error a download of the pack that still needs neededBytes fails with now, or nil
local function downloadFailure( id, neededBytes )
	if settings.offline then return failure( "offlineError", id ) end
	if settings.freeDiskSpace and neededBytes > settings.freeDiskSpace then return failure( "lowDiskSpaceError", id ) end
	return nil
end

-- settle: ends the download, as finished or else failed with rawError, and answers every call waiting on it
local function settle( download, rawError )
	local id = download.raw.id
	if download.timer then timer.cancel( download.timer ) end
	if downloads[id] == download then downloads[id] = nil end
	if rawError then removeStaging( id ) end
	notify( { phase = rawError and "failed" or "finished", assetPack = download.raw, error = rawError } )
	for _, done in ipairs( download.waiters ) do
		if rawError then done( nil, rawError ) else done( true ) end
	end
end

local scheduleTick

-- tick: fails the download if it cannot go on, or else advances it by step ms with a progress event and, at its end,
-- installs the pack
local function tick( download, step )
	if not isLive( download ) then return end
	local size = download.raw.downloadSize
	local rawError = downloadFailure( download.raw.id, size - download.completed )
	if rawError then return settle( download, rawError ) end
	download.elapsed = download.elapsed + step
	local fraction = download.duration > 0 and download.elapsed / download.duration or 1
	download.completed = math.floor( size * fraction )
	notify( { phase = "progress", assetPack = download.raw,
		progress = { fractionCompleted = fraction, completedUnitCount = download.completed, totalUnitCount = size } } )
	if not isLive( download ) then return end
	if download.elapsed < download.duration then return scheduleTick( download ) end
	installPack( download.pack )
	changeFreeDiskSpace( -size )
	settle( download )
end

function scheduleTick( download )
	local step = math.min( PROGRESS_INTERVAL, download.duration - download.elapsed )
	download.timer = timer.performWithDelay( step, function() tick( download, step ) end )
end

-- startDownload: joins the pack's download in flight, or else starts one; done, when given, is called when it ends. A
-- download that cannot start sends no began.
local function startDownload( pack, done )
	local download = downloads[pack.id]
	if download then
		download.waiters[#download.waiters + 1] = done
		return
	end
	download = { pack = pack, raw = rawPack( pack ), waiters = { done } }
	local rawError = downloadFailure( pack.id, pack.downloadSize )
	if rawError then
		timer.performWithDelay( 1, function() settle( download, rawError ) end )
		return
	end
	local seconds = settings.downloadDuration or pack.downloadSize / settings.bytesPerSecond
	download.duration, download.elapsed, download.completed = math.ceil( seconds * 1000 ), 0, 0
	downloads[pack.id] = download
	download.timer = timer.performWithDelay( 1, function()
		if not isLive( download ) then return end
		notify( { phase = "began", assetPack = download.raw } )
		if not isLive( download ) then return end
		scheduleTick( download )
	end )
end

local function cancelDownload( id )
	local download = downloads[id]
	if download then settle( download, failure( "cancelled", id ) ) end
end

-- ensurePack: done(true) once the pack is local, starting or joining its download, or done(nil, rawError)
local function ensurePack( sources, id, done )
	local pack = sources[id]
	if not pack then return done( nil, packNotFound( id ) ) end
	if device().packs[id] then return done( true ) end
	startDownload( pack, done )
end

-- installAtLaunch: on a device not installed yet, the essential packs arrive at once, with no events. At every launch, a
-- prefetch pack neither local nor removed by the app downloads, so an interrupted one completes.
local function installAtLaunch()
	local saved = device()
	local removed = {}
	for _, id in ipairs( saved.removedAssetPacks ) do
		removed[id] = true
	end
	for _, pack in pairs( readSources() ) do
		local isForDevice = not pack.language or pack.language == saved.resolvedLanguage
		local isMissing = not saved.packs[pack.id] and not removed[pack.id]
		if isForDevice and pack.policy == "essential" and not saved.installed then installPack( pack ) end
		if isForDevice and pack.policy == "prefetch" and isMissing then startDownload( pack ) end
	end
	if saved.installed then return end
	saved.installed = true
	saveState()
end

local function sortedKeys( set )
	local keys = {}
	for key in pairs( set ) do
		keys[#keys + 1] = key
	end
	table.sort( keys )
	return keys
end

local function hasFile( record, path )
	for _, file in ipairs( record.files ) do
		if file.path == path then return true end
	end
	return false
end

-- Path lookup

-- the absolute path of each file a path call returned, to the name relative to system.CachesDirectory link() gives
local cachesNames = {}

-- deviceName: the name, relative to system.CachesDirectory, of the device's file for a path, or nil
local function deviceName( path, assetPackId, language )
	if assetPackId then
		local record = device().packs[assetPackId]
		return record and hasFile( record, path ) and ( languageFolder( record.language ) .. "/" .. path ) or nil
	end
	local folders = language and { language } or { UNLOCALIZED, device().resolvedLanguage }
	for _, folder in ipairs( folders ) do
		local name = languageFolder( folder ) .. "/" .. path
		if isFile( absolute( name ) ) then return name end
	end
	return nil
end

local function locate( path, assetPackId, language )
	local name = deviceName( path, assetPackId, language )
	if not name then return nil, fileNotFound( path, assetPackId ) end
	local file = absolute( name )
	cachesNames[file] = name
	return file
end

-- The backend

local backend = {}

function backend.info()
	frontLoaded = true
	installAtLaunch()
	local isWindows = package.config:sub( 1, 1 ) == "\\"
	return { platform = isWindows and "win32-sim" or "mac-sim", apiVersion = settings.apiVersion, hosting = settings.hosting }
end

function backend.defer( fn )
	timer.performWithDelay( 1, fn )
end

function backend.setDelegate( handler )
	delegate = handler
end

function backend.loadRemovedAssetPacks()
	return device().removedAssetPacks
end

function backend.saveRemovedAssetPacks( ids )
	device().removedAssetPacks = ids
	saveState()
end

function backend.getAssetPack( id, done )
	if settings.offline then return done( nil, failure( "offlineError", id ) ) end
	local pack = readSources()[id]
	if not pack then return done( nil, packNotFound( id ) ) end
	done( rawPack( pack ) )
end

function backend.getAllAssetPacks( done )
	if settings.offline then return done( nil, failure( "offlineError" ) ) end
	local packs = {}
	for _, pack in pairs( readSources() ) do
		packs[#packs + 1] = rawPack( pack )
	end
	done( packs )
end

function backend.getManifest( done )
	if settings.offline then return done( nil, failure( "offlineError" ) ) end
	local assetPacks, localizedAssetPacks, languages = {}, {}, {}
	for _, pack in pairs( readSources() ) do
		local packs = pack.language and localizedAssetPacks or assetPacks
		packs[#packs + 1] = rawPack( pack )
		if pack.language then languages[pack.language] = true end
	end
	done( {
		assetPacks = assetPacks,
		localizedAssetPacks = localizedAssetPacks,
		availableLanguages = sortedKeys( languages ),
		resolvedLanguage = device().resolvedLanguage,
	} )
end

-- statusCall: a status function over the status bits of a pack that is in the pack sources or local, plus downloading
-- while it downloads; a store call fails while offline
local function statusCall( bits, isStoreCall )
	return function( id, done )
		if isStoreCall and settings.offline then return done( nil, failure( "offlineError", id ) ) end
		local sources = readSources()
		local isLocal = device().packs[id] ~= nil
		if not sources[id] and not isLocal then return done( nil, packNotFound( id ) ) end
		local downloading = downloads[id] and STATUS.downloading or 0
		done( bits( isLocal, sources[id] ~= nil ) + downloading )
	end
end

local function storeStatus( isLocal, isKnown )
	if not isLocal then return STATUS.downloadAvailable end
	return STATUS.downloaded + STATUS.upToDate + ( isKnown and 0 or STATUS.obsolete )
end

backend.getStatusOfAssetPack = statusCall( storeStatus, true )
backend.getStatusRelativeToAssetPack = statusCall( storeStatus, true )
backend.getLocalStatusOfAssetPack = statusCall( function( isLocal )
	return isLocal and STATUS.downloaded + STATUS.upToDate or 0
end )

function backend.assetPackIsAvailableLocally( id )
	return device().packs[id] ~= nil
end

function backend.ensureLocalAvailability( id, _, done )
	ensurePack( readSources(), id, done )
end

-- multiPackError: the first failure's raw error with the call's successes and failures
local function multiPackError( first, successes, failures )
	return { domain = first.domain, code = first.code, message = first.message, assetPackId = first.assetPackId,
		successes = successes, failures = failures }
end

-- The packs download side by side; requireLatestVersions changes nothing, every pack being at version 1.
function backend.ensureLocalAvailabilityOfAssetPacks( ids, _, done )
	local sources = readSources()
	local successes, failures, firstError = {}, {}, nil
	local pending = #ids
	local function answer( id )
		return function( isLocal, rawError )
			if isLocal then
				successes[#successes + 1] = rawPack( sources[id] )
			else
				firstError = firstError or rawError
				failures[#failures + 1] = { assetPack = sources[id] and rawPack( sources[id] ) or { id = id }, error = rawError }
			end
			pending = pending - 1
			if pending > 0 then return end
			if firstError then return done( nil, multiPackError( firstError, successes, failures ) ) end
			done( true )
		end
	end
	if pending == 0 then return done( true ) end
	for _, id in ipairs( ids ) do
		ensurePack( sources, id, answer( id ) )
	end
end

function backend.checkForUpdates( done )
	if settings.offline then return done( nil, failure( "offlineError" ) ) end
	local sources, removed = readSources(), {}
	for id in pairs( device().packs ) do
		if not sources[id] then removed[#removed + 1] = id end
	end
	for _, id in ipairs( removed ) do
		deleteLocalPack( id )
	end
	done( { updatingIdentifiers = {}, removedIdentifiers = removed } )
end

function backend.removeAssetPack( id, done )
	if not readSources()[id] and not device().packs[id] then return done( nil, packNotFound( id ) ) end
	cancelDownload( id )
	deleteLocalPack( id )
	done( true )
end

-- There are no links to delete: link() returns the device's own files.
function backend.unlinkAssetPack()
end

function backend.getLocallyAvailableLanguages( done )
	local languages = {}
	for _, record in pairs( device().packs ) do
		if record.language then languages[record.language] = true end
	end
	done( sortedKeys( languages ) )
end

function backend.reconcilePreferredLanguages( done )
	done( true )
end

function backend.getResolvedLanguage()
	return device().resolvedLanguage
end

function backend.setResolvedLanguage( language )
	device().resolvedLanguage = language
	saveState()
end

function backend.urlForPath( path, language )
	return locate( path, nil, language )
end

function backend.fileExists( file )
	return isFile( file )
end

function backend.contentsAtPath( path, assetPackId, language )
	local file, rawError = locate( path, assetPackId, language )
	if not file then return nil, rawError end
	local contents = readFile( file )
	if not contents then return nil, fileNotFound( path, assetPackId ) end
	return contents
end

function backend.fileForPath( path, assetPackId, language )
	local file, rawError = locate( path, assetPackId, language )
	if not file then return nil, rawError end
	local handle, message, code = io.open( file, "rb" )
	if not handle then return nil, { domain = "NSPOSIXErrorDomain", code = code, message = message, assetPackId = assetPackId } end
	return handle
end

function backend.link( path, file )
	local name = cachesNames[file]
	if not name then return nil, fileNotFound( path ) end
	return name, system.CachesDirectory
end

-- The module

local emulator = { _backend = backend }

function emulator.configure( options )
	if type( options ) ~= "table" then
		error( "bad argument #1 to 'configure' (table expected, got " .. type( options ) .. ")", 2 )
	end
	for field, value in pairs( options ) do
		local option = OPTIONS[field]
		if not option then error( "bad option to 'configure' (unknown field " .. describe( field ) .. ")", 2 ) end
		local expected, accepts = option[1], option[2]
		if not accepts( value ) then
			error( string.format( "bad option '%s' to 'configure' (%s expected, got %s)", field, expected,
				describe( value ) ), 2 )
		end
		if frontLoaded and LOAD_TIME[field] and value ~= settings[field] then
			error( "emulator option '" .. field .. "' must be set before the first require(\"plugin.backgroundAssets\")", 2 )
		end
	end
	for field, value in pairs( options ) do
		settings[field] = value
	end
end

function emulator.reset()
	for _, id in ipairs( sortedKeys( downloads ) ) do
		cancelDownload( id )
	end
	removeTree( absolute( ROOT ) )
	state = nil
	cachesNames = {}
end

return emulator
