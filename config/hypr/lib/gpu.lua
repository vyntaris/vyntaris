local M = {}

function M.igpuOnly()
    local function first(path)
        local f = io.open(path)
        if not f then return nil end
        local s = f:read("*l")
        f:close()
        return s
    end
    local igpu, dgpu, dgpuScreen = nil, false, false
    local pci = io.popen("ls -d /sys/bus/pci/devices/* 2>/dev/null")
    if not pci then return nil end
    for d in pci:lines() do
        if (first(d .. "/class") or ""):match("^0x03") and first(d .. "/vendor") == "0x10de" then dgpu = true end
    end
    pci:close()
    local p = io.popen("ls -d /sys/class/drm/card[0-9]*-* 2>/dev/null")
    if not p then return nil end
    for conn in p:lines() do
        local card, name = conn:match("/(card%d+)%-(.+)$")
        local nvidia = first("/sys/class/drm/" .. card .. "/device/vendor") == "0x10de"
        local connected = first(conn .. "/status") == "connected"
        if nvidia then
            if connected then dgpuScreen = true end
        elseif name:match("^eDP") and connected then
            igpu = "/dev/dri/" .. card
        end
    end
    p:close()
    if igpu and dgpu and not dgpuScreen then return igpu end
    return nil
end

return M
