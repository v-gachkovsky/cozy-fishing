-- The game's Lua 5.1: string.format's %s takes only a string or a number, and errors on nil (Lua 5.4 and later
-- write "nil"). Loaded first by the tests, so they fail where the game would.
local format = string.format
string.format = function(text, ...)
    local i = 0
    for spec in text:gsub("%%%%", ""):gmatch("%%[-+ #0]*%d*%.?%d*(%a)") do
        i = i + 1
        local v = select(i, ...)
        if spec == "s" and type(v) ~= "string" and type(v) ~= "number" then
            error(format("bad argument #%d to 'format' (string expected, got %s)", i + 1, type(v)), 2)
        end
    end
    return format(text, ...)
end
