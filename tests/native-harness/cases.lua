-- usage: lua cases.lua BUILD --list | BUILD CASE
-- --list prints the case ids; CASE runs that case: the backend luaopen_plugin_backgroundAssets gives (BUILD/plugin.so,
-- the real PluginBackgroundAssets.m over a front that returns the backend table), with Background Assets faked by
-- BUILD/harness.so and Solar2D's system.pathForFile stood in, in a fresh folder BUILD/case-<n>. It fails with a message
-- when the case does not hold.
local build, which = ...
local harness = assert( package.loadlib( build .. "/harness.so", "luaopen_harness" ) )()
local backend = assert( package.loadlib( build .. "/plugin.so", "luaopen_plugin_backgroundAssets" ) )()
local PLUGIN_DOMAIN = "plugin.backgroundAssets"
local DATA = "line 1\nline 2\n"

local dir -- the case's folder
local caches -- what system.CachesDirectory resolves to

local function check( condition, message )
	if not condition then error( message, 2 ) end
end

local function checkEqual( actual, expected, what )
	if actual ~= expected then
		error( what .. ": got " .. tostring( actual ) .. ", expected " .. tostring( expected ), 2 )
	end
end

local function checkError( err, domain, code, what )
	check( type( err ) == "table", what .. ": no raw error" )
	checkEqual( err.domain, domain, what .. " domain" )
	checkEqual( err.code, code, what .. " code" )
end

local function shell( command )
	check( os.execute( command ) == 0, "failed: " .. command )
end

local function write( path, contents )
	shell( "mkdir -p '" .. path:match( "^(.*)/" ) .. "'" )
	local file = assert( io.open( path, "w" ) )
	file:write( contents )
	file:close()
end

local function read( path )
	local file = assert( io.open( path ) )
	local contents = file:read( "*a" )
	file:close()
	return contents
end

-- a pack's file pk/a.txt under the namespace root dir/<root>
local function stage( root )
	write( dir .. "/" .. root .. "/pk/a.txt", DATA )
	return dir .. "/" .. root
end

local function openFile()
	harness.setRoot( stage( "Staging/Unlocalized" ) )
	local file, err = backend.fileForPath( "pk/a.txt" )
	check( file, "fileForPath: " .. tostring( err and err.message ) )
	return file
end

-- the milliseconds a urlForPath lookup takes, and its results
local function timedLookup()
	local start = harness.uptime()
	local url, err = backend.urlForPath( "pk/a.txt" )
	return harness.uptime() - start, url, err
end

-- the lines NSLog wrote while fn ran
local function logOf( fn )
	local log = dir .. "/stderr.log"
	check( harness.logTo( log ), "cannot send stderr to " .. log )
	fn()
	io.stderr:flush()
	return read( log )
end

local function count( text, pattern )
	local _, n = text:gsub( pattern, "" )
	return n
end

-- backend.link for pk/a.txt under root, checked to give its name and system.CachesDirectory; returns the link's path
local function link( root )
	local name, base = backend.link( "pk/a.txt", root .. "/pk/a.txt" )
	check( name, "link: " .. tostring( base and base.message ) )
	check( base == system.CachesDirectory, "link's base directory is not system.CachesDirectory" )
	local folder = root:match( "[^/]+$" )
	checkEqual( name, "plugin.backgroundAssets/" .. folder .. "/pk/a.txt", "link name" )
	checkEqual( read( caches .. "/" .. name ), DATA, "the file through the link" )
	return caches .. "/plugin.backgroundAssets/" .. folder
end

local function lookupCase( outcomes, rest, milliseconds, lookups, code )
	harness.setRoot( stage( "Staging/Unlocalized" ) )
	harness.lookups( outcomes, rest, milliseconds )
	local _, url, err = timedLookup()
	checkEqual( harness.lookupCount(), lookups, "lookups" )
	if code then checkError( err, "NSCocoaErrorDomain", code, "urlForPath" ) else check( url, "no url" ) end
end

local function removeWaitCase( completesAfter, atLeast, below )
	harness.setRoot( stage( "Staging/Unlocalized" ) )
	harness.removeCompletesAfter( completesAfter )
	backend.removeAssetPack( "pk", function() end )
	local waited, url = timedLookup()
	check( url, "no url" )
	checkEqual( harness.lookupCount(), 1, "lookups" )
	check( waited >= atLeast and waited < below,
		string.format( "waited %.1f ms, expected at least %d and below %d", waited, atLeast, below ) )
end

local cases = {
	-- the file handle (D14.10): fileForPath's file, as io.open gives one
	{ "file handle: the wrapped fd reads and lines() works", function()
		local file = openFile()
		checkEqual( io.type( file ), "file", "io.type" )
		checkEqual( file:read( "*l" ), "line 1", "read" )
		local lines = {}
		for line in file:lines() do
			lines[#lines + 1] = line
		end
		checkEqual( table.concat( lines, "|" ), "line 2", "lines()" )
	end },
	{ "file handle: close() gives io.type closed file", function()
		local file = openFile()
		local fd = harness.lastFd()
		check( file:close(), "close() failed" )
		checkEqual( io.type( file ), "closed file", "io.type" )
		check( not harness.isOpen( fd ), "fd still open after close()" )
	end },
	{ "file handle: GC of an unclosed handle is safe", function()
		local file = openFile()
		local fd = harness.lastFd()
		file = nil
		collectgarbage( "collect" )
		collectgarbage( "collect" )
		check( not harness.isOpen( fd ), "fd still open after the collector ran" )
	end },
	{ "file handle: a bad fd gives nil and NSPOSIXErrorDomain 9, the stack unchanged", function()
		harness.setRoot( stage( "Staging/Unlocalized" ) )
		local okTop = harness.topAtReturn( backend.fileForPath, "pk/a.txt" )
		harness.badFd( true )
		local top, file, err = harness.topAtReturn( backend.fileForPath, "pk/a.txt" )
		checkEqual( file, nil, "file" )
		checkError( err, "NSPOSIXErrorDomain", 9, "fileForPath" )
		-- the argument and the file, or the argument, nil and the error: nothing else left on the stack
		checkEqual( okTop, 2, "stack size at return with a good fd" )
		checkEqual( top, 3, "stack size at return with a bad fd" )
	end },
	{ "file handle: io = nil gives the unsupported error", function()
		harness.setRoot( stage( "Staging/Unlocalized" ) )
		local savedIo = io
		io = nil
		local file, err = backend.fileForPath( "pk/a.txt" )
		io = savedIo
		checkEqual( file, nil, "file" )
		checkError( err, PLUGIN_DOMAIN, 1, "fileForPath" )
		check( not harness.isOpen( harness.lastFd() ), "fd left open" )
	end },

	-- the transient 513 (D12): lookups through urlForPath
	{ "513 policy: 513 twice then ok gives 3 lookups", function()
		lookupCase( { 513, 513 }, 0, 0, 3 )
	end },
	{ "513 policy: 513 always gives 1+4 lookups, then giving up", function()
		local log = logOf( function() lookupCase( {}, 513, 0, 5, 513 ) end )
		for retry = 1, 4 do
			checkEqual( count( log, "retry " .. retry .. " of 4" ), 1, "log lines for retry " .. retry )
		end
		checkEqual( count( log, "NSCocoaErrorDomain 513 looking up pk/a%.txt, giving up" ), 1, "giving-up lines" )
	end },
	{ "513 policy: a non-513 error gives 1 lookup", function()
		lookupCase( {}, 260, 0, 1, 260 )
	end },
	{ "513 policy: slow 513s stop at the 50 ms budget", function()
		local log = logOf( function() lookupCase( {}, 513, 15, 3, 513 ) end )
		checkEqual( count( log, "giving up" ), 1, "giving-up lines" )
	end },
	{ "513 policy: a remove in flight is waited for", function()
		removeWaitCase( 30, 30, 250 )
	end },
	{ "513 policy: a remove in flight is waited for at most 250 ms", function()
		removeWaitCase( -1, 250, 1000 )
	end },

	-- links (D10) and the removed-pack record
	{ "links: the link name is <Caches>/plugin.backgroundAssets/<root's last component>", function()
		local root = stage( "Staging/Unlocalized" )
		checkEqual( harness.readLink( link( root ) ), root, "link target" )
	end },
	{ "links: idempotent", function()
		local root = stage( "Staging/Unlocalized" )
		local _, inode = harness.readLink( link( root ) )
		local target, again = harness.readLink( link( root ) )
		checkEqual( target, root, "link target" )
		checkEqual( again, inode, "link inode" )
	end },
	{ "links: recreated after the caches folder is deleted", function()
		local root = stage( "Staging/Unlocalized" )
		link( root )
		shell( "rm -rf '" .. caches .. "'" )
		checkEqual( harness.readLink( link( root ) ), root, "link target" )
	end },
	{ "links: retargeted when the root moves", function()
		link( stage( "Staging/Unlocalized" ) )
		local moved = stage( "Moved/Staging/Unlocalized" )
		checkEqual( harness.readLink( link( moved ) ), moved, "link target" )
	end },
	{ "links: a language root gets its own link", function()
		local unlocalized = link( stage( "Staging/Unlocalized" ) )
		local root = stage( "Staging/fr" )
		local french = link( root )
		checkEqual( harness.readLink( french ), root, "fr link target" )
		check( harness.readLink( unlocalized ), "the Unlocalized link is gone" )
	end },
	{ "links: a file without the /path suffix gives nil and plugin error 2", function()
		local name, err = backend.link( "pk/a.txt", dir .. "/Staging/Unlocalized/pk/b.txt" )
		checkEqual( name, nil, "name" )
		checkError( err, PLUGIN_DOMAIN, 2, "link" )
	end },
	{ "record: the removed-pack record loads and saves", function()
		checkEqual( #backend.loadRemovedAssetPacks(), 0, "packs in an empty record" )
		backend.saveRemovedAssetPacks( { "a", "b" } )
		checkEqual( table.concat( backend.loadRemovedAssetPacks(), "," ), "a,b", "record after saving a and b" )
		backend.saveRemovedAssetPacks( {} )
		checkEqual( #backend.loadRemovedAssetPacks(), 0, "packs after saving none" )
	end },
}

if which == "--list" then
	for _, case in ipairs( cases ) do
		print( case[1] )
	end
	return
end
for n, case in ipairs( cases ) do
	if case[1] == which then
		dir = build .. "/case-" .. n
		caches = dir .. "/Caches"
		shell( "rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'" )
		system = {
			CachesDirectory = {},
			pathForFile = function( name, base )
				check( base == system.CachesDirectory, "pathForFile outside system.CachesDirectory" )
				return caches .. "/" .. name
			end,
		}
		return case[2]()
	end
end
error( "no case " .. tostring( which ), 0 )
