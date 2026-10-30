# What Vyntaris ships that others made

Vyntaris's own files (the shell, the setup, the installer, the boot splash, the sounds its tools
synthesize) are this repository's. Shipped with them, under their own licenses:

| What | Where | Made by | License |
|------|-------|---------|---------|
| Bibata Modern Ice (cursor theme) | `config/icons/Bibata-Modern-Ice`, installed to `/usr/share/icons` | Abdulkaiz Khatri (ful1e5), github.com/ful1e5/Bibata_Cursor | GPL-3.0, text in its `LICENSE` |
| powerlevel10k (the zsh prompt), fetched at build time | `/usr/share/vyntaris/zsh/powerlevel10k` | Roman Perepelitsa, github.com/romkatv/powerlevel10k | MIT, text in its `LICENSE` |
| Material Symbols, Rounded (the shell's icons: the ones it uses, outlined and filled) | `config/quickshell/components/MaterialIcons.js` (made by `tools/make-icons.py`) | Google, fonts.google.com/icons | Apache-2.0 |
| Floating cubes and glowing yellow spheres (the default wallpaper, resized, with its lights recoloured) | `config/quickshell/assets/wallpapers/default*` | [Sebastian Svenson](https://unsplash.com/photos/d2w-_1LJioQ) | [Unsplash License](https://unsplash.com/license) |
| Catppuccin's palettes (Mocha, Frappé, Latte: the colour values) | `config/quickshell/config/Palettes.js` (Hyprland's config and the Python read them from there) | Catppuccin, github.com/catppuccin/catppuccin | MIT |

Everything else the desktop uses (Hyprland, Quickshell, Papirus, the fonts, the apps) comes as Arch
packages, each with its own license in `/usr/share/licenses`.
