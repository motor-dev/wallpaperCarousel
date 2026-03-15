import QtQuick
import qs.Modules.Plugins

PluginSettings {
    pluginId: "wallpaperCarousel"

    StringSetting {
        settingKey: "wallpaperDirectory"
        label: "Wallpaper Directory"
        description: "Override the wallpaper directory. Leave empty to automatically follow the current wallpaper's directory."
        placeholder: "/home/user/Pictures/Wallpapers"
        defaultValue: ""
    }
}
