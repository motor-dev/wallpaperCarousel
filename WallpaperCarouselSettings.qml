import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "wallpaperCarousel"

    StringSetting {
        settingKey: "wallpaperDirectory"
        label: "Wallpaper Directory"
        description: "Override the wallpaper directory. Leave empty to follow system wallpaper."
        placeholder: "/home/user/Pictures/Wallpapers"
        defaultValue: ""
    }

    SelectionSetting {
        settingKey: "carouselMode"
        label: "Carousel Mode"
        description: "Standard, Wrap, or Infinite view types."
        defaultValue: "wrap"
        options: [
            { label: "Standard", value: "standard" },
            { label: "Wrap", value: "wrap" },
            { label: "Infinite", value: "infinite" }
        ]
    }

    // -------------------------------------------------------------
    // Item Width
    // -------------------------------------------------------------
    Column {
        id: colWidth
        width: parent.width; spacing: Theme.spacingXS
        property int defaultValue: 300
        property var val: root.loadValue("itemWidth", defaultValue)
        Row {
            width: parent.width; spacing: Theme.spacingS
            StyledText { text: "Item Width"; font.weight: Font.Medium; color: Theme.surfaceText; width: parent.width - 24 - Theme.spacingS }
            DankIcon {
                name: "restart_alt"; size: 20
                opacity: String(colWidth.val) !== String(colWidth.defaultValue) ? 0.8 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveValue("itemWidth", colWidth.defaultValue) }
            }
        }
        StyledText { text: "Width of each wallpaper thumbnail in pixels."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap; opacity: 0.8 }
        DankSlider { width: parent.width; minimum: 100; maximum: 1000; value: Number(colWidth.val) || colWidth.defaultValue; unit: "px"; onSliderValueChanged: v => root.saveValue("itemWidth", v) }
    }

    // -------------------------------------------------------------
    // Item Height
    // -------------------------------------------------------------
    Column {
        id: colHeight
        width: parent.width; spacing: Theme.spacingXS
        property int defaultValue: 420
        property var val: root.loadValue("itemHeight", defaultValue)
        Row {
            width: parent.width; spacing: Theme.spacingS
            StyledText { text: "Item Height"; font.weight: Font.Medium; color: Theme.surfaceText; width: parent.width - 24 - Theme.spacingS }
            DankIcon {
                name: "restart_alt"; size: 20
                opacity: String(colHeight.val) !== String(colHeight.defaultValue) ? 0.8 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveValue("itemHeight", colHeight.defaultValue) }
            }
        }
        StyledText { text: "Height of each wallpaper thumbnail in pixels."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap; opacity: 0.8 }
        DankSlider { width: parent.width; minimum: 100; maximum: 1440; value: Number(colHeight.val) || colHeight.defaultValue; unit: "px"; onSliderValueChanged: v => root.saveValue("itemHeight", v) }
    }

    // -------------------------------------------------------------
    // Border Width
    // -------------------------------------------------------------
    Column {
        id: colBorder
        width: parent.width; spacing: Theme.spacingXS
        property int defaultValue: 3
        property var val: root.loadValue("borderWidth", defaultValue)
        Row {
            width: parent.width; spacing: Theme.spacingS
            StyledText { text: "Border Width"; font.weight: Font.Medium; color: Theme.surfaceText; width: parent.width - 24 - Theme.spacingS }
            DankIcon {
                name: "restart_alt"; size: 20
                opacity: String(colBorder.val) !== String(colBorder.defaultValue) ? 0.8 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveValue("borderWidth", colBorder.defaultValue) }
            }
        }
        StyledText { text: "Width of the skewed border around thumbnails."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap; opacity: 0.8 }
        DankSlider { width: parent.width; minimum: 0; maximum: 20; value: Number(colBorder.val) || colBorder.defaultValue; unit: "px"; onSliderValueChanged: v => root.saveValue("borderWidth", v) }
    }

    // -------------------------------------------------------------
    // Selected Scale
    // -------------------------------------------------------------
    Column {
        id: colScale
        width: parent.width; spacing: Theme.spacingXS
        property int defaultValue: 115
        property var val: root.loadValue("selectedScale", defaultValue)
        Row {
            width: parent.width; spacing: Theme.spacingS
            StyledText { text: "Selected Scale (%)"; font.weight: Font.Medium; color: Theme.surfaceText; width: parent.width - 24 - Theme.spacingS }
            DankIcon {
                name: "restart_alt"; size: 20
                opacity: String(colScale.val) !== String(colScale.defaultValue) ? 0.8 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveValue("selectedScale", colScale.defaultValue) }
            }
        }
        StyledText { text: "Scale of the centered image (e.g. 115 for 1.15x)."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap; opacity: 0.8 }
        DankSlider { width: parent.width; minimum: 100; maximum: 150; value: Number(colScale.val) || colScale.defaultValue; unit: "%"; onSliderValueChanged: v => root.saveValue("selectedScale", v) }
    }

    // -------------------------------------------------------------
    // Background Dimming
    // -------------------------------------------------------------
    Column {
        id: colDimming
        width: parent.width; spacing: Theme.spacingXS
        property int defaultValue: 80
        property var val: root.loadValue("overlayOpacity", defaultValue)
        Row {
            width: parent.width; spacing: Theme.spacingS
            StyledText { text: "Background Dimming (%)"; font.weight: Font.Medium; color: Theme.surfaceText; width: parent.width - 24 - Theme.spacingS }
            DankIcon {
                name: "restart_alt"; size: 20
                opacity: String(colDimming.val) !== String(colDimming.defaultValue) ? 0.8 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveValue("overlayOpacity", colDimming.defaultValue) }
            }
        }
        StyledText { text: "Opacity of the dark overlay behind the carousel."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap; opacity: 0.8 }
        DankSlider { width: parent.width; minimum: 0; maximum: 100; value: Number(colDimming.val) || colDimming.defaultValue; unit: "%"; onSliderValueChanged: v => root.saveValue("overlayOpacity", v) }
    }

    SelectionSetting {
        settingKey: "enableRounding"
        label: "Enable Rounded Corners"
        description: "Apply rounded corners to image thumbnails."
        defaultValue: "false"
        options: [
            { label: "Disabled", value: "false" },
            { label: "Enabled", value: "true" }
        ]
    }

    // -------------------------------------------------------------
    // Corner Radius
    // -------------------------------------------------------------
    Column {
        id: colRadius
        width: parent.width; spacing: Theme.spacingXS
        property int defaultValue: 10
        property var val: root.loadValue("cornerRadius", defaultValue)
        Row {
            width: parent.width; spacing: Theme.spacingS
            StyledText { text: "Corner Radius (px)"; font.weight: Font.Medium; color: Theme.surfaceText; width: parent.width - 24 - Theme.spacingS }
            DankIcon {
                name: "restart_alt"; size: 20
                opacity: String(colRadius.val) !== String(colRadius.defaultValue) ? 0.8 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveValue("cornerRadius", colRadius.defaultValue) }
            }
        }
        StyledText { text: "Adjust the corner radius when enabled."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap; opacity: 0.8 }
        DankSlider { width: parent.width; minimum: 0; maximum: 100; value: Number(colRadius.val) || colRadius.defaultValue; unit: "px"; onSliderValueChanged: v => root.saveValue("cornerRadius", v) }
    }

    SelectionSetting {
        settingKey: "expandSelected"
        label: "Expand Selected Image"
        description: "When an image is centered, expand its width to show more."
        defaultValue: "false"
        options: [
            { label: "Disabled", value: "false" },
            { label: "Enabled", value: "true" }
        ]
    }

    SelectionSetting {
        settingKey: "enableHoldExpand"
        label: "Enable Hold to Expand"
        description: "Stay on an image to trigger a larger immersive preview."
        defaultValue: "true"
        options: [
            { label: "Disabled", value: "false" },
            { label: "Enabled", value: "true" }
        ]
    }

    // -------------------------------------------------------------
    // Expansion Amount
    // -------------------------------------------------------------
    Column {
        id: colExpand
        width: parent.width; spacing: Theme.spacingXS
        property int defaultValue: 150
        property var val: root.loadValue("expandMultiplier", defaultValue)
        Row {
            width: parent.width; spacing: Theme.spacingS
            StyledText { text: "Expansion Amount (%)"; font.weight: Font.Medium; color: Theme.surfaceText; width: parent.width - 24 - Theme.spacingS }
            DankIcon {
                name: "restart_alt"; size: 20
                opacity: String(colExpand.val) !== String(colExpand.defaultValue) ? 0.8 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveValue("expandMultiplier", colExpand.defaultValue) }
            }
        }
        StyledText { text: "Width multiplier for the centered image."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap; opacity: 0.8 }
        DankSlider { width: parent.width; minimum: 100; maximum: 300; value: Number(colExpand.val) || colExpand.defaultValue; unit: "%"; onSliderValueChanged: v => root.saveValue("expandMultiplier", v) }
    }

    // -------------------------------------------------------------
    // Hold Screen Coverage
    // -------------------------------------------------------------
    Column {
        id: colCoverage
        width: parent.width; spacing: Theme.spacingXS
        property int defaultValue: 80
        property var val: root.loadValue("holdExpandRatio", defaultValue)
        Row {
            width: parent.width; spacing: Theme.spacingS
            StyledText { text: "Hold Screen Coverage (%)"; font.weight: Font.Medium; color: Theme.surfaceText; width: parent.width - 24 - Theme.spacingS }
            DankIcon {
                name: "restart_alt"; size: 20
                opacity: String(colCoverage.val) !== String(colCoverage.defaultValue) ? 0.8 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveValue("holdExpandRatio", colCoverage.defaultValue) }
            }
        }
        StyledText { text: "Percentage of screen dimensions the image unfolds to."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap; opacity: 0.8 }
        DankSlider { width: parent.width; minimum: 30; maximum: 100; value: Number(colCoverage.val) || colCoverage.defaultValue; unit: "%"; onSliderValueChanged: v => root.saveValue("holdExpandRatio", v) }
    }

    // -------------------------------------------------------------
    // Hold Delay
    // -------------------------------------------------------------
    Column {
        id: colDelay
        width: parent.width; spacing: Theme.spacingXS
        property int defaultValue: 5000
        property var val: root.loadValue("holdDelay", defaultValue)
        Row {
            width: parent.width; spacing: Theme.spacingS
            StyledText { text: "Hold Delay (ms)"; font.weight: Font.Medium; color: Theme.surfaceText; width: parent.width - 24 - Theme.spacingS }
            DankIcon {
                name: "restart_alt"; size: 20
                opacity: String(colDelay.val) !== String(colDelay.defaultValue) ? 0.8 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveValue("holdDelay", colDelay.defaultValue) }
            }
        }
        StyledText { text: "Time to stay on an image before it expands."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap; opacity: 0.8 }
        DankSlider { width: parent.width; minimum: 200; maximum: 10000; value: Number(colDelay.val) || colDelay.defaultValue; unit: "ms"; onSliderValueChanged: v => root.saveValue("holdDelay", v) }
    }

}
