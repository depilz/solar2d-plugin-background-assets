-- usage: lua tables.lua FILE
-- Fails unless the iphone archive's metadata FILE returns exactly the expected table.
local expected = {
	plugin = {
		format = "staticLibrary",
		staticLibs = { "plugin_backgroundAssets" },
		frameworks = {},
		frameworksOptional = { "BackgroundAssets" },
	},
}

local function same( a, b )
	if type( a ) ~= "table" or type( b ) ~= "table" then
		return a == b
	end
	for k, v in pairs( a ) do
		if not same( v, b[k] ) then return false end
	end
	for k in pairs( b ) do
		if a[k] == nil then return false end
	end
	return true
end

local file = ...
assert( file, "usage: lua tables.lua FILE" )
if not same( dofile( file ), expected ) then
	error( "metadata: not the expected table", 0 )
end
