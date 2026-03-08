import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    // -------------------------------------------------------------------------
    // WALLPAPER FOLDER — derived from the current DMS wallpaper path
    // -------------------------------------------------------------------------
    readonly property string wallpaperFolder: {
        const p = SessionData.wallpaperPath;
        if (!p || p.startsWith("#"))
            return Paths.strip(Paths.pictures);
        const lastSlash = p.lastIndexOf('/');
        return lastSlash > 0 ? p.substring(0, lastSlash) : Paths.strip(Paths.pictures);
    }

    readonly property string wallpaperFolderUrl: "file://" + wallpaperFolder

    function toggle() {
        if (overlay.visible) {
            close();
        } else {
            open();
        }
    }

    function open() {
        carousel.initialFocusSet = false;
        const focusedScreen = CompositorService.getFocusedScreen();
        if (focusedScreen)
            overlay.screen = focusedScreen;
        overlay.visible = true;
        carousel.tryFocus();
        view.forceActiveFocus();
        Qt.callLater(() => view.forceActiveFocus());
    }

    function close() {
        overlay.visible = false;
    }

    function cycle(direction: int): string {
        if (!overlay.visible) {
            open();
            return "opened:" + view.currentIndex;
        }

        if (direction > 0)
            view.incrementCurrentIndex();
        else
            view.decrementCurrentIndex();

        return "index:" + view.currentIndex;
    }

    // -------------------------------------------------------------------------
    // IPC — allows triggering via: dms ipc call wallpaperCarousel <command>
    // (bind these commands to your preferred keys in your compositor config)
    //
    //   toggle         — open / close the overlay
    //   open           — open the overlay (no-op if already open)
    //   close          — close the overlay (no-op if already closed)
    //   cycle-next     — if closed: open; then highlight next wallpaper
    //   cycle-previous — if closed: open; then highlight previous wallpaper
    // -------------------------------------------------------------------------
    IpcHandler {
        target: "wallpaperCarousel"

        function toggle(): string {
            root.toggle();
            return overlay.visible ? "opened" : "closed";
        }

        function open(): string {
            if (!overlay.visible)
                root.open();
            return "opened";
        }

        function close(): string {
            if (overlay.visible)
                root.close();
            return "closed";
        }

        function cycleNext(): string  { return root.cycle(+1); }
        function cyclePrevious(): string { return root.cycle(-1); }
    }

    // -------------------------------------------------------------------------
    // FULLSCREEN OVERLAY WINDOW
    // -------------------------------------------------------------------------
    PanelWindow {
        id: overlay
        visible: false
        color: "transparent"

        WlrLayershell.namespace: "dms:plugins:wallpaperCarousel"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        Rectangle {
            anchors.fill: parent
            color: "#CC000000"
            opacity: overlay.visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // Click background to close
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        // -------------------------------------------------------------------------
        // CAROUSEL
        // -------------------------------------------------------------------------
        Item {
            id: carousel
            anchors.fill: parent
            opacity: overlay.visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            property bool initialFocusSet: false

            function tryFocus() {
                if (initialFocusSet)
                    return;

                let targetIndex = 0;
                const wp = (SessionData.perMonitorWallpaper && overlay.screen)
                           ? SessionData.getMonitorWallpaper(overlay.screen.name)
                           : SessionData.wallpaperPath;
                const currentFile = (wp || "").split('/').pop();
                if (currentFile && folderModel.count > 0) {
                    for (let i = 0; i < folderModel.count; i++) {
                        if (folderModel.get(i, "fileName") === currentFile) {
                            targetIndex = i;
                            break;
                        }
                    }
                }

                if (view.count > targetIndex) {
                    view.currentIndex = targetIndex;
                    view.positionViewAtIndex(targetIndex, ListView.Center);
                    initialFocusSet = true;
                } else if (folderModel.status === FolderListModel.Ready && view.count > 0) {
                    const safeIndex = Math.min(targetIndex, view.count - 1);
                    view.currentIndex = safeIndex;
                    view.positionViewAtIndex(safeIndex, ListView.Center);
                    initialFocusSet = true;
                }
            }

            readonly property int itemWidth: 300
            readonly property int itemHeight: 420
            readonly property int borderWidth: 3
            readonly property real skewFactor: -0.35

            ListView {
                id: view
                anchors.fill: parent

                spacing: 0
                orientation: ListView.Horizontal
                clip: false

                cacheBuffer: 5000

                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width / 2) - (carousel.itemWidth / 2)
                preferredHighlightEnd:   (width / 2) + (carousel.itemWidth / 2)

                highlightMoveDuration: carousel.initialFocusSet ? 300 : 0

                focus: overlay.visible
                activeFocusOnTab: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left) {
                        decrementCurrentIndex();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right) {
                        incrementCurrentIndex();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (currentItem)
                            currentItem.pickWallpaper();
                        event.accepted = true;
                    }
                }

                onCountChanged: carousel.tryFocus()

                model: FolderListModel {
                    id: folderModel
                    folder: root.wallpaperFolderUrl
                    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif",
                                  "*.bmp", "*.jxl", "*.avif", "*.heif", "*.exr"]
                    showDirs: false
                    sortField: FolderListModel.Name

                    onStatusChanged: carousel.tryFocus()
                }

                delegate: Item {
                    id: delegateRoot
                    width: carousel.itemWidth
                    height: carousel.itemHeight
                    anchors.verticalCenter: parent.verticalCenter

                    readonly property bool isCurrent: ListView.isCurrentItem
                    readonly property int distFromCenter: Math.abs(index - view.currentIndex)

                    z: isCurrent ? 10 : Math.max(1, 10 - distFromCenter)

                    function pickWallpaper() {
                        const fullPath = root.wallpaperFolder + "/" + fileName;
                        if (SessionData.perMonitorWallpaper && overlay.screen)
                            SessionData.setMonitorWallpaper(overlay.screen.name, fullPath);
                        else
                            SessionData.setWallpaper(fullPath);
                        root.close();
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            view.currentIndex = index;
                            delegateRoot.pickWallpaper();
                        }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height

                        // Non-linear falloff: center = 1.15, neighbors shrink and fade
                        // using 1/(1+d²) curve for a gentle rolloff
                        readonly property real falloff: 1.0 / (1.0 + delegateRoot.distFromCenter * delegateRoot.distFromCenter)
                        scale: 0.75 + 0.40 * falloff
                        opacity: 0.25 + 0.75 * falloff
                        layer.enabled: opacity < 1

                        Behavior on scale   { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                        Behavior on opacity { NumberAnimation { duration: 500 } }

                        transform: Matrix4x4 {
                            property real s: carousel.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0,
                                                 0, 1, 0, 0,
                                                 0, 0, 1, 0,
                                                 0, 0, 0, 1)
                        }

                        // Outer skewed border image
                        Image {
                            anchors.fill: parent
                            source: fileUrl
                            sourceSize: Qt.size(carousel.itemWidth, carousel.itemHeight)
                            fillMode: Image.Stretch
                            asynchronous: true
                            visible: innerImage.status === Image.Ready
                        }

                        Item {
                            anchors.fill: parent
                            anchors.margins: carousel.borderWidth
                            visible: innerImage.status === Image.Ready

                            Rectangle { anchors.fill: parent; color: "black" }
                            clip: true

                            Image {
                                id: innerImage
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: -50

                                width: parent.width + (parent.height * Math.abs(carousel.skewFactor)) + 50
                                height: parent.height

                                fillMode: Image.PreserveAspectCrop
                                source: fileUrl
                                sourceSize: Qt.size(carousel.itemWidth, carousel.itemHeight)
                                asynchronous: true

                                transform: Matrix4x4 {
                                    property real s: -carousel.skewFactor
                                    matrix: Qt.matrix4x4(1, s, 0, 0,
                                                         0, 1, 0, 0,
                                                         0, 0, 1, 0,
                                                         0, 0, 0, 1)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Empty state message
        Column {
            anchors.centerIn: parent
            spacing: 12
            visible: overlay.visible && folderModel.status === FolderListModel.Ready && folderModel.count === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    const p = SessionData.wallpaperPath;
                    return (!p || p.startsWith("#"))
                        ? "No wallpaper configured"
                        : "No images found in wallpaper folder";
                }
                font.pixelSize: 24
                font.bold: true
                color: "white"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    const p = SessionData.wallpaperPath;
                    return (!p || p.startsWith("#"))
                        ? "Open DankMaterialShell Settings → Wallpaper,\nenable DMS wallpaper management and select a wallpaper."
                        : "The folder '" + root.wallpaperFolder + "' is empty.\nAdd images or choose a different wallpaper in DMS Settings.";
                }
                font.pixelSize: 14
                color: "#BBBBBB"
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.4
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Press Escape to close"
                font.pixelSize: 12
                color: "#888888"
            }
        }
    }

    // -------------------------------------------------------------------------
    // PRE-CACHE — force Qt to decode wallpaper thumbnails at boot by rendering
    // them inside a real 1×1 PanelWindow on the Background layer.
    // -------------------------------------------------------------------------
    FolderListModel {
        id: precacheModel
        folder: root.wallpaperFolderUrl
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif",
                      "*.bmp", "*.jxl", "*.avif", "*.heif", "*.exr"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    PanelWindow {
        id: cacheWindow
        visible: true
        color: "transparent"
        width: 1
        height: 1

        WlrLayershell.namespace: "dms:plugins:wallpaperCarousel:precache"
        WlrLayershell.layer: WlrLayershell.Background
        WlrLayershell.exclusiveZone: 0

        anchors { top: true; left: true }

        Item {
            width: 1; height: 1
            clip: true

            Repeater {
                model: precacheModel
                Image {
                    width: carousel.itemWidth
                    height: carousel.itemHeight
                    asynchronous: true
                    source: fileUrl
                    sourceSize: Qt.size(carousel.itemWidth, carousel.itemHeight)
                    fillMode: Image.PreserveAspectCrop
                }
            }
        }
    }

    Component.onCompleted: {
        console.info("WallpaperCarousel: daemon loaded — use 'dms ipc call wallpaperCarousel toggle' to open");
    }
}
