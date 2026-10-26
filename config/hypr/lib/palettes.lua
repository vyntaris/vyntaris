local here = (package.searchpath("lib.palettes", package.path) or ""):match("^(.*)/lib/[^/]*$") or "."
local sources = { here .. "/../quickshell/config/Palettes.js", "/etc/xdg/quickshell/vyntaris/config/Palettes.js" }

local palettes = {}
for _, path in ipairs(sources) do
    local file = io.open(path, "r")
    if file then
        local src = file:read("a")
        file:close()
        for flavor, body in src:gmatch("(%w+):%s*(%b{})") do
            local colours = {}
            for name, hex in body:gmatch('(%w+):%s*"#(%x%x%x%x%x%x)"') do colours[name] = hex end
            if colours.base then palettes[flavor] = colours end
        end
        break
    end
end

palettes.mocha = palettes.mocha or { base = "1e1e2e", surface0 = "313244", mauve = "cba6f7" }
return palettes
