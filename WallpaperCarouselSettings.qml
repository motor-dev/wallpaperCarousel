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

    StringSetting {
        settingKey: "itemWidth"
        label: "Item Width"
        description: "Width of each wallpaper thumbnail in pixels. Enter a number (e.g. 300). Default: 300"
        placeholder: "300"
        defaultValue: "300"
    }

    StringSetting {
        settingKey: "itemHeight"
        label: "Item Height"
        description: "Height of each wallpaper thumbnail in pixels. Enter a number (e.g. 420). Default: 420"
        placeholder: "420"
        defaultValue: "420"
    }

    SliderSetting {
        settingKey: "borderWidth"
        label: "Border Width"
        description: "Width of the skewed border around each wallpaper thumbnail (in pixels). Default: 3"
        defaultValue: 3
        minimum: 0
        maximum: 20
        unit: "px"
    }

    StringSetting {
        settingKey: "selectedScale"
        label: "Selected Item Scale"
        description: "Scale of the currently selected (centered) wallpaper thumbnail. Other items scale down proportionally based on distance. Enter a decimal value (e.g. 1.15). Default: 1.15"
        placeholder: "1.15"
        defaultValue: "1.15"
    }

    SliderSetting {
        settingKey: "overlayOpacity"
        label: "Background Dimming"
        description: "Opacity of the dark overlay behind the carousel. 0 = transparent, 100 = fully dark. Default: 80"
        defaultValue: 80
        minimum: 0
        maximum: 100
        unit: "%"
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
