local dir = arg[1]
package.path = dir .. "/?.lua;" .. package.path

local binds, notes = 0, {}
local function anything(name)
    return setmetatable({}, {
        __index = function (_, k) return anything(name .. "." .. k) end,
        __call = function (_, ...) return anything(name .. "()") end,
        __concat = function (a, b) return tostring(a) .. tostring(b) end,
        __tostring = function () return name end,
    })
end
hl = anything("hl")
rawset(hl, "bind", function (_, _, opts) binds = binds + 1 end)
rawset(hl, "notification", { create = function (t) notes[#notes + 1] = t.text end })
rawset(hl, "get_config", function () return nil end)
rawset(hl, "exec_cmd", function (cmd) if tostring(cmd):match("notify%-send") then notes[#notes + 1] = cmd end end)

local ok, err = pcall(dofile, dir .. "/hyprland.lua")
print("BINDS=" .. binds)
for _, n in ipairs(notes) do print("NOTE=" .. tostring(n):gsub("\n", " ")) end
if not ok then print("ERROR=" .. tostring(err)) os.exit(1) end
