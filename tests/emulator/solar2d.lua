-- Test-only stand-ins for the Solar2D globals the emulator uses, over folders in a case's directory: system (pathForFile
-- into ROOT/caches and ROOT/project) and timer (a queue on a manual clock). Returns the folders and the clock, whose
-- advance(ms) runs every timer due by then in time order.
return function( root )
	local folders = { CachesDirectory = root .. "/caches", ResourceDirectory = root .. "/project" }
	assert( os.execute( "mkdir -p '" .. folders.CachesDirectory .. "' '" .. folders.ResourceDirectory .. "'" ) == 0 )

	system = {
		CachesDirectory = "CachesDirectory",
		ResourceDirectory = "ResourceDirectory",
		pathForFile = function( name, base )
			return folders[base or "ResourceDirectory"] .. "/" .. ( name or "" )
		end,
		getInfo = function( key )
			return ( { environment = "simulator", platform = "ios", platformName = "Mac OS X" } )[key]
		end,
	}

	local clock = { now = 0 }
	local queue = {}

	timer = {
		performWithDelay = function( delay, listener )
			local handle = { at = clock.now + delay, listener = listener }
			queue[#queue + 1] = handle
			return handle
		end,
		cancel = function( handle )
			handle.isCancelled = true
		end,
		cancelAll = function()
			queue = {}
		end,
	}

	local function nextDue( time )
		local due
		for i, handle in ipairs( queue ) do
			if handle.at <= time and ( not due or handle.at < queue[due].at ) then due = i end
		end
		return due
	end

	function clock.advance( ms )
		local time = clock.now + ms
		for due in nextDue, time do
			local handle = table.remove( queue, due )
			clock.now = handle.at
			if not handle.isCancelled then handle.listener( { source = handle, time = clock.now } ) end
		end
		clock.now = time
	end

	return folders, clock
end
