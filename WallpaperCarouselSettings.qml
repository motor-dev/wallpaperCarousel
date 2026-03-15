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

    SelectionSetting {
        settingKey: "carouselMode"
        label: "Carousel Mode"
        description: "Standard stops at the edges. Wrap loops the index. Infinite shows a seamless repeating view."
        defaultValue: "wrap"
        options: [
            { label: "Standard", value: "standard" },
            { label: "Wrap", value: "wrap" },
            { label: "Infinite", value: "infinite" }
        ]
    }
}
