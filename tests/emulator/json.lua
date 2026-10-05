-- A test-only stand-in for Solar2D's built-in json module, found by require("json") through this folder on
-- package.path: json.encode, and json.decode giving nil, a position and a message for invalid JSON. Like Solar2D's, it
-- encodes an empty table as [] and decodes null as nil.
local json = {}

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r",
	["\t"] = "\\t" }
local UNESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function isArray( value )
	local count = 0
	for _ in pairs( value ) do
		count = count + 1
	end
	return count == #value
end

function json.encode( value )
	local kind = type( value )
	if kind == "nil" then return "null" end
	if kind == "boolean" then return tostring( value ) end
	if kind == "number" then return string.format( "%.14g", value ) end
	if kind == "string" then
		return '"' .. value:gsub( '[%c"\\]', function( char )
			return ESCAPES[char] or string.format( "\\u%04x", char:byte() )
		end ) .. '"'
	end
	local parts = {}
	if isArray( value ) then
		for i, item in ipairs( value ) do
			parts[i] = json.encode( item )
		end
		return "[" .. table.concat( parts, "," ) .. "]"
	end
	for key, item in pairs( value ) do
		parts[#parts + 1] = json.encode( tostring( key ) ) .. ":" .. json.encode( item )
	end
	return "{" .. table.concat( parts, "," ) .. "}"
end

function json.decode( text )
	local pos = 1
	local function fail( message ) error( { message = message }, 0 ) end
	local function skip() pos = text:find( "[^ \t\r\n]", pos ) or #text + 1 end
	local function peek() return text:sub( pos, pos ) end
	local value

	local function literal( word, result )
		if text:sub( pos, pos + #word - 1 ) ~= word then fail( "unexpected character" ) end
		pos = pos + #word
		return result
	end

	local function str()
		local out = {}
		pos = pos + 1
		while true do
			local char = peek()
			if char == "" then fail( "unterminated string" ) end
			pos = pos + 1
			if char == '"' then return table.concat( out ) end
			if char == "\\" then
				local escaped = peek()
				pos = pos + 1
				if escaped == "u" then
					local code = tonumber( text:sub( pos, pos + 3 ), 16 )
					if not code or code > 127 then fail( "unsupported \\u escape" ) end
					char = string.char( code )
					pos = pos + 4
				else
					char = UNESCAPES[escaped] or fail( "bad escape" )
				end
			end
			out[#out + 1] = char
		end
	end

	local function sequence( close, item )
		pos = pos + 1
		skip()
		if peek() == close then
			pos = pos + 1
			return
		end
		while true do
			item()
			skip()
			local char = peek()
			pos = pos + 1
			if char == close then return end
			if char ~= "," then fail( "expected , or " .. close ) end
			skip()
		end
	end

	function value()
		skip()
		local char = peek()
		if char == "{" then
			local object = {}
			sequence( "}", function()
				if peek() ~= '"' then fail( "expected a key" ) end
				local key = str()
				skip()
				if peek() ~= ":" then fail( "expected :" ) end
				pos = pos + 1
				object[key] = value()
			end )
			return object
		elseif char == "[" then
			local array = {}
			sequence( "]", function() array[#array + 1] = value() end )
			return array
		elseif char == '"' then
			return str()
		elseif char == "t" then
			return literal( "true", true )
		elseif char == "f" then
			return literal( "false", false )
		elseif char == "n" then
			return literal( "null", nil )
		end
		local number = text:match( "^-?%d+%.?%d*[eE]?[-+]?%d*", pos )
		if not number then fail( "unexpected character" ) end
		pos = pos + #number
		return tonumber( number )
	end

	local ok, result = pcall( function()
		local decoded = value()
		skip()
		if pos <= #text then fail( "trailing characters" ) end
		return decoded
	end )
	if ok then return result end
	if type( result ) ~= "table" then error( result, 0 ) end
	return nil, pos, result.message
end

return json
