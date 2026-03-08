# Wallpaper Carousel

Based on the original wallpaper picker by [ilyamiro](https://github.com/ilyamiro/nixos-configuration).

A [DankMaterialShell](https://github.com/nicehash/DankMaterialShell) plugin that lets you browse and pick wallpapers from a fullscreen skewed carousel overlay.

![screenshot](screenshot.png)

## About

Wallpaper Carousel scans your current wallpaper directory and displays all images in an animated 3D-skewed carousel. Navigate with keyboard or mouse, press Enter to apply. Thumbnails are pre-cached in memory at boot for instant opening.

This plugin integrates with all DMS features — selecting a wallpaper updates the shell wallpaper, color scheme, and any other DMS components that react to wallpaper changes.

## Install

> **Note:** DankMaterialShell must be managing your wallpaper for this plugin to work. It does not work with external wallpaper engines (e.g. swww, swaybg, hyprpaper). Enable wallpaper management in DMS Settings → Wallpaper.

1. Download the latest archive from the [Releases](../../releases) page
2. Extract it into your DMS plugins directory:
   ```sh
   tar xf wallpaperCarousel-*.tar.gz -C "${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins/"
   ```
3. Open DankMaterialShell Settings → Plugins and enable **Wallpaper Carousel**
4. Bind keys in your compositor config (see below) or call the IPC commands from a script

## IPC Commands

Control the carousel via DMS IPC:

| Command | Description |
|---------|-------------|
| `dms ipc call wallpaperCarousel toggle` | Open or close the overlay |
| `dms ipc call wallpaperCarousel open` | Open the overlay |
| `dms ipc call wallpaperCarousel close` | Close the overlay |
| `dms ipc call wallpaperCarousel cycleNext` | Open (if closed) and highlight next wallpaper |
| `dms ipc call wallpaperCarousel cyclePrevious` | Open (if closed) and highlight previous wallpaper |

**Keyboard shortcuts** (when open): `←` / `→` to navigate, `Enter` to apply, `Escape` to close.

## Compositor Keybindings

### Niri

In `~/.config/niri/config.kdl`:

```kdl
binds {
    Mod+W { spawn "dms" "ipc" "call" "wallpaperCarousel" "toggle"; }
    Mod+Shift+Right { spawn "dms" "ipc" "call" "wallpaperCarousel" "cycleNext"; }
    Mod+Shift+Left { spawn "dms" "ipc" "call" "wallpaperCarousel" "cyclePrevious"; }
}
```

### Hyprland

In `~/.config/hypr/hyprland.conf`:

```ini
bind = SUPER, W, exec, dms ipc call wallpaperCarousel toggle
bind = SUPER SHIFT, Right, exec, dms ipc call wallpaperCarousel cycleNext
bind = SUPER SHIFT, Left, exec, dms ipc call wallpaperCarousel cyclePrevious
```
