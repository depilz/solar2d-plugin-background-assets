-- A backend for the front's tests (docs/backend.rst) that reports the iOS version it is made with. It keeps each
-- function's last arguments in fake.log, answers from fake.answers (async calls at once, or later from fake.pending
-- when fake.hold is set) and runs deferred functions only on fake.runDeferred().
local RAW_PACK = { id = "packa", downloadSize = 10, version = 1 }

local ASYNC = {
	"getAssetPack", "getAllAssetPacks", "getManifest", "getStatusOfAssetPack", "getStatusRelativeToAssetPack",
	"getLocalStatusOfAssetPack", "ensureLocalAvailability", "ensureLocalAvailabilityOfAssetPacks", "checkForUpdates",
	"removeAssetPack", "getLocallyAvailableLanguages", "reconcilePreferredLanguages",
}

return function( apiVersion )
	local fake = {
		log = {},
		pending = {},
		deferred = {},
		files = {},
		available = {},
		stored = {},
		answers = {
			getAssetPack = { RAW_PACK },
			getAllAssetPacks = { { RAW_PACK } },
			getManifest = { { assetPacks = { RAW_PACK }, availableLanguages = {}, localizedAssetPacks = {} } },
			getStatusOfAssetPack = { 0 },
			getStatusRelativeToAssetPack = { 0 },
			getLocalStatusOfAssetPack = { 0 },
			ensureLocalAvailability = { true },
			ensureLocalAvailabilityOfAssetPacks = { true },
			checkForUpdates = { { updatingIdentifiers = {}, removedIdentifiers = {} } },
			removeAssetPack = { true },
			getLocallyAvailableLanguages = { {} },
			reconcilePreferredLanguages = { true },
		},
	}

	local function logged( name, fn )
		return function( ... )
			fake.log[name] = { ... }
			return fn( ... )
		end
	end

	local function async( name )
		return function( ... )
			local args = { ... }
			local count = select( "#", ... )
			local done = args[count]
			args[count] = nil
			fake.log[name] = args
			if fake.hold then
				fake.pending[name] = done
				return
			end
			local answer = fake.answers[name]
			done( answer[1], answer[2] )
		end
	end

	for _, name in ipairs( ASYNC ) do
		fake[name] = async( name )
	end

	function fake.info()
		return { platform = "ios", osVersion = apiVersion, apiVersion = apiVersion, hosting = "apple" }
	end

	function fake.defer( fn )
		fake.deferred[#fake.deferred + 1] = fn
	end

	function fake.runDeferred()
		local queue = fake.deferred
		fake.deferred = {}
		for _, fn in ipairs( queue ) do
			fn()
		end
	end

	fake.setDelegate = logged( "setDelegate", function( handler ) fake.delegate = handler end )
	fake.assetPackIsAvailableLocally = logged( "assetPackIsAvailableLocally", function( id )
		return fake.available[id] == true
	end )
	fake.urlForPath = logged( "urlForPath", function( path )
		if fake.answers.urlForPath then return unpack( fake.answers.urlForPath ) end
		return "/container/" .. path
	end )
	fake.fileExists = logged( "fileExists", function( file ) return fake.files[file] == true end )
	fake.contentsAtPath = logged( "contentsAtPath", function( path ) return "contents of " .. path end )
	fake.fileForPath = logged( "fileForPath", function() return io.tmpfile() end )
	fake.link = logged( "link", function( path ) return "links/" .. path, "CachesDirectory" end )
	fake.unlinkAssetPack = logged( "unlinkAssetPack", function() end )
	fake.loadRemovedAssetPacks = logged( "loadRemovedAssetPacks", function() return fake.stored end )
	fake.saveRemovedAssetPacks = logged( "saveRemovedAssetPacks", function( ids ) fake.stored = ids end )
	fake.getResolvedLanguage = logged( "getResolvedLanguage", function() return fake.resolvedLanguage end )
	fake.setResolvedLanguage = logged( "setResolvedLanguage", function( language ) fake.resolvedLanguage = language end )

	return fake
end
