hl.monitor({ output = "", mode = "preferred", position = "auto", scale = @SCALE@ })

local igpuOnly = dofile("/usr/share/vyntaris/hypr/lib/gpu.lua").igpuOnly()
if igpuOnly then
    hl.env("AQ_DRM_DEVICES", igpuOnly)
    hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json")
end

hl.config({
    input = { kb_layout = "@KB_LAYOUT@", kb_variant = "@KB_VARIANT@", kb_options = "@KB_OPTIONS@" },
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        enable_anr_dialog        = false,
        disable_hyprland_guiutils_check = true,
        disable_watchdog_warning = true,
    },
    debug = { suppress_errors = true },
    ecosystem = { no_update_news = true, no_donation_nag = true },
    animations = { enabled = false },
})

hl.on("hyprland.start", function ()
    hl.exec_cmd("qs -p /etc/greetd/greeter; hyprctl dispatch 'hl.dsp.exit()'")
end)
