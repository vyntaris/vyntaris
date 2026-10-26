local M = {}

local escapes = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
    b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}

local function fail(pos, msg)
    error(string.format("json: %s at position %d", msg, pos), 0)
end

local function skip_ws(str, pos)
    return str:find("[^ \t\r\n]", pos) or #str + 1
end

local parse_value

local function parse_string(str, pos)
    local out, i = {}, pos + 1
    while true do
        local c = str:sub(i, i)
        if c == "" then fail(pos, "unterminated string") end
        if c == '"' then return table.concat(out), i + 1 end
        if c == "\\" then
            local e = str:sub(i + 1, i + 1)
            if e == "u" then
                local cp = tonumber(str:sub(i + 2, i + 5), 16) or fail(i, "bad unicode escape")
                out[#out + 1] = utf8.char(cp)
                i = i + 6
            else
                out[#out + 1] = escapes[e] or fail(i, "bad escape")
                i = i + 2
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

local function parse_number(str, pos)
    local s, e = str:find("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if not s then fail(pos, "bad number") end
    return tonumber(str:sub(s, e)) or fail(pos, "bad number"), e + 1
end

local function parse_literal(str, pos)
    if str:sub(pos, pos + 3) == "true" then return true, pos + 4 end
    if str:sub(pos, pos + 4) == "false" then return false, pos + 5 end
    if str:sub(pos, pos + 3) == "null" then return nil, pos + 4 end
    fail(pos, "unexpected character")
end

local function parse_array(str, pos)
    local arr, n = {}, 0
    pos = skip_ws(str, pos + 1)
    if str:sub(pos, pos) == "]" then return arr, pos + 1 end
    while true do
        local value
        value, pos = parse_value(str, pos)
        n = n + 1
        arr[n] = value
        pos = skip_ws(str, pos)
        local c = str:sub(pos, pos)
        if c == "]" then return arr, pos + 1 end
        if c ~= "," then fail(pos, "expected ',' or ']'") end
        pos = skip_ws(str, pos + 1)
    end
end

local function parse_object(str, pos)
    local obj = {}
    pos = skip_ws(str, pos + 1)
    if str:sub(pos, pos) == "}" then return obj, pos + 1 end
    while true do
        if str:sub(pos, pos) ~= '"' then fail(pos, "expected key") end
        local key, value
        key, pos = parse_string(str, pos)
        pos = skip_ws(str, pos)
        if str:sub(pos, pos) ~= ":" then fail(pos, "expected ':'") end
        value, pos = parse_value(str, pos + 1)
        obj[key] = value
        pos = skip_ws(str, pos)
        local c = str:sub(pos, pos)
        if c == "}" then return obj, pos + 1 end
        if c ~= "," then fail(pos, "expected ',' or '}'") end
        pos = skip_ws(str, pos + 1)
    end
end

parse_value = function(str, pos)
    pos = skip_ws(str, pos)
    local c = str:sub(pos, pos)
    if c == "{" then return parse_object(str, pos) end
    if c == "[" then return parse_array(str, pos) end
    if c == '"' then return parse_string(str, pos) end
    if c == "-" or c:match("%d") then return parse_number(str, pos) end
    return parse_literal(str, pos)
end

function M.decode(str)
    local value, pos = parse_value(str, 1)
    pos = skip_ws(str, pos)
    if pos <= #str then fail(pos, "trailing data") end
    return value
end

return M
