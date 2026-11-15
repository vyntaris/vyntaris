local M = {}

function M.accent(palette, name)
    if type(name) == "string" and name:match("^#%x%x%x%x%x%x$") then return name:sub(2):lower() end
    return palette[name] or palette.blue
end

return M
