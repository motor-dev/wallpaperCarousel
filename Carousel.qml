import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Item {
    id: root

    // ── Shell integration interface ───────────────────────────────────────────
    // Wrapper provides these; Carousel is fully shell-agnostic.

    property string defaultWallpaperFolder: ""
    property string currentWallpaperPath: ""   // full path; used to highlight current item on open
    property var extraDirectories: []           // other directories to pre-scan/cache (Noctalia multi-monitor)
    property string wlrNamespace: "plugins:wallpaperCarousel"
    property var cfg: ({})                      // raw settings object from the host shell
    property var getFocusedScreen: () => null
    // () => Screen | null
    property bool hasWallpaperConfigured: true
    property string shellSettingsHint: "Open your shell settings → Wallpaper to configure a wallpaper directory."

    // Screen hint for the noctalia v5 wrapper. The wrapper can't detect the focused screen itself.
    // getFocusedScreen(hint) receives this; DMS and Noctalia v4 wrappers that do
    // their own detection can simply ignore the argument.
    property string pendingScreenName: ""

    signal wallpaperPicked(string fullPath, string screenName)

    readonly property var overlayScreen: overlay.screen  // wrappers can bind against this

    // Wrappers that mirror the overlay's state elsewhere (the Noctalia v5 host
    // reports it back to the shell so the Control Center shortcut can show
    // whether the carousel is up) bind against this rather than reaching into
    // the overlay window.
    readonly property bool overlayVisible: overlay.visible

    // ── Style ─────────────────────────────────────────────────────────────────
    property color scrimColor: "#CC000000"          // further scaled by the overlayOpacity setting
    // Text drawn straight on the scrim, which is dark in both light and dark themes.
    property color onScrimTextColor: "white"
    property color onScrimSecondaryTextColor: "#BBBBBB"
    property color onScrimTertiaryTextColor: "#888888"
    // Search field (has its own background, so it can follow the shell theme fully).
    property color searchBackgroundColor: "#BB000000"
    property color searchTextColor: "white"
    property color searchPlaceholderColor: "#55FFFFFF"
    property color searchBorderColor: "#44FFFFFF"
    property color searchFocusBorderColor: "#AAFFFFFF"
    property string fontFamily: Qt.application.font.family
    property real fontSizeSmall: 12
    property real fontSizeMedium: 14
    property real fontSizeLarge: 15
    property real fontSizeTitle: 24
    property real uiRadius: 8
    property real uiSpacing: 12

    // ── Derived settings with defaults ────────────────────────────────────────
    readonly property string wallpaperFolder: {
        const ov = (cfg.wallpaperDirectory ?? "").trim();
        return ov || defaultWallpaperFolder;
    }

    readonly property string _carouselMode: cfg.carouselMode ?? "wrap"
    readonly property bool _isInfinite: _carouselMode === "infinite"
    readonly property bool _wrapsIndex: _carouselMode !== "standard"
    on_CarouselModeChanged: if (_initialSyncDone)
        Qt.callLater(_syncStableModel)

    readonly property var _currentView: (_isInfinite && !carousel.searchActive) ? pathView : listView
    readonly property string wallpaperFolderUrl: "file://" + wallpaperFolder

    // ── Folder cache ──────────────────────────────────────────────────────────
    property var _folderCache: ({})
    property bool _initialSyncDone: false
    property int _currentCacheIndex: -1
    // Pre-cache window contents. A ListModel updated in place (rather than a JS
    // array reassigned on every rebuild) keeps the Repeater's Images for entries
    // that stay in the window alive: reassigning an array recreates every
    // delegate, and Qt keeps only a small pool of unreferenced images, so each
    // wallpaper pick would otherwise reload the whole window from disk.
    ListModel {
        id: cacheModel
    }

    // `urls`: the window, nearest-first; missing ones are appended in that order so
    // they load in it. `keepUrls`: a wider zone whose already-loaded entries are not
    // evicted yet (hysteresis), so scrolling back and forth does not re-decode them.
    function _setCacheEntries(urls, keepUrls) {
        const keep = {};
        for (const url of urls)
            keep[url] = true;
        for (const url of (keepUrls || []))
            keep[url] = true;
        const present = {};
        for (let i = cacheModel.count - 1; i >= 0; i--) {
            const url = cacheModel.get(i).url;
            if (keep[url] && !present[url])
                present[url] = true;
            else
                cacheModel.remove(i);
        }
        for (const url of urls) {
            if (!present[url]) {
                present[url] = true;
                cacheModel.append({ url: url });
            }
        }
    }

    readonly property var _nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.bmp", "*.jxl", "*.avif", "*.heif", "*.exr"]

    onCurrentWallpaperPathChanged: {
        if (folderModel.status === FolderListModel.Ready && folderModel.count > 0) {
            root._currentCacheIndex = root._findCurrentIndex();
            root._rebuildCacheEntries();
        }
    }

    on_WrapsIndexChanged: {
        if (folderModel.status === FolderListModel.Ready && folderModel.count > 0)
            root._rebuildCacheEntries();
    }

    onWallpaperFolderUrlChanged: {
        modelSyncTimer.stop();
        const cached = _folderCache[wallpaperFolder];
        if (cached) {
            _populateStableModel(cached);
            carousel.tryFocus();
        } else {
            stableModel.clear();
        }
        root._initialSyncDone = false;
    }

    ListModel {
        id: stableModel
    }
    ListModel {
        id: filteredModel
    }

    Timer {
        id: modelSyncTimer
        interval: 1500
        onTriggered: root._syncStableModel()
    }

    FolderListModel {
        id: folderModel
        folder: root.wallpaperFolderUrl
        nameFilters: root._nameFilters
        showDirs: false
        sortField: FolderListModel.Name

        onStatusChanged: {
            if (status === FolderListModel.Ready && !root._initialSyncDone) {
                root._syncStableModel();
                root._initialSyncDone = true;
            }
        }
        onCountChanged: {
            if (root._initialSyncDone)
                modelSyncTimer.restart();
        }
    }

    function _readFolderModel(model) {
        var entries = [];
        for (var i = 0; i < model.count; i++)
            entries.push({
                fileName: model.get(i, "fileName"),
                fileUrl: model.get(i, "fileUrl").toString()
            });
        return entries;
    }

    function _findCurrentIndex() {
        const fileName = (root.currentWallpaperPath || "").split('/').pop();
        if (!fileName)
            return 0;
        for (let i = 0; i < folderModel.count; i++) {
            if (folderModel.get(i, "fileName") === fileName)
                return i;
        }
        return 0;
    }

    // While browsing, the pre-cache window follows the highlighted tile rather than
    // the applied wallpaper, so scrolling past cacheSize/2 tiles does not run into
    // uncached images. Throttled, not debounced: auto-repeat and flicks change the
    // index faster than the interval, and a debounce would freeze the window for
    // the whole of a long scroll. The timer is only started when idle, so the
    // window moves at most once per interval but keeps moving while scrolling.
    Timer {
        id: cacheFollowTimer
        interval: 150
        onTriggered: root._rebuildCacheEntries()
    }

    // Last scroll direction in folder order: +1, -1, or 0 (none yet / re-centred).
    property int _scrollDirection: 0

    function _followViewIndex(viewIndex) {
        // Search results are a filtered list whose indices are not folder indices.
        const count = folderModel.count;
        if (!overlay.visible || carousel.searchActive || viewIndex < 0 || count === 0)
            return;
        // The infinite view repeats the folder list, so fold its index back.
        const index = viewIndex % count;
        const previous = root._currentCacheIndex;
        if (previous >= 0 && index !== previous) {
            let delta = index - previous;
            // Wrapping past an end is a single step, not a jump across the list.
            if (root._wrapsIndex) {
                if (delta > count / 2)
                    delta -= count;
                else if (delta < -count / 2)
                    delta += count;
            }
            root._scrollDirection = delta > 0 ? 1 : -1;
        }
        root._currentCacheIndex = index;
        if (!cacheFollowTimer.running)
            cacheFollowTimer.start();
    }

    // Once closed, re-centre on the applied wallpaper so the next open is instant.
    onOverlayVisibleChanged: {
        if (overlayVisible || folderModel.status !== FolderListModel.Ready || folderModel.count === 0)
            return;
        cacheFollowTimer.stop();
        root._scrollDirection = 0;
        root._currentCacheIndex = root._findCurrentIndex();
        root._rebuildCacheEntries();
    }

    // Folder indices around `center`, nearest-first, `ahead` steps in `direction`
    // and `behind` steps against it. Wrap/infinite: neighbours of the first item are
    // the last items (and vice versa), so it wraps around the ends; standard clamps.
    function _windowIndices(center, ahead, behind, direction) {
        const count = folderModel.count;
        const dir = direction < 0 ? -1 : 1;
        const out = [];
        const seen = {};
        const take = i => {
            if (root._wrapsIndex)
                i = ((i % count) + count) % count;
            else if (i < 0 || i >= count)
                return;
            if (seen[i])
                return;
            seen[i] = true;
            out.push(i);
        };
        take(center);
        for (let d = 1; (d <= ahead || d <= behind) && out.length < count; d++) {
            if (d <= ahead)
                take(center + dir * d);
            if (d <= behind)
                take(center - dir * d);
        }
        return out;
    }

    function _rebuildCacheEntries() {
        const count = folderModel.count;
        if (count === 0) {
            root._setCacheEntries([], []);
            return;
        }
        const found = root._currentCacheIndex >= 0 ? root._currentCacheIndex : root._findCurrentIndex();
        const center = Math.max(0, Math.min(count - 1, found));
        const parsed = parseInt(root.cfg.cacheSize);
        const cacheSize = Math.max(1, isNaN(parsed) ? 30 : parsed);  // 30 = settings default
        const urlsOf = indices => indices.map(i => folderModel.get(i, "fileUrl").toString());

        // The window covers the whole folder: cache everything, nearest-first.
        if (cacheSize >= count) {
            root._setCacheEntries(urlsOf(root._windowIndices(center, count, count, 1)), []);
            return;
        }

        // cacheSize tiles in total. While scrolling, two thirds of them lie ahead in
        // the direction of travel, where the next tiles come from; at rest (open,
        // re-centre) the window is symmetric.
        const radius = Math.floor(cacheSize / 2);
        const span = cacheSize - 1;
        const ahead = root._scrollDirection !== 0 ? Math.round(span * 2 / 3) : radius;
        const behind = root._scrollDirection !== 0 ? span - ahead : span - radius;
        // Keep zone: entries up to 2x the radius away on either side survive
        // eviction, so a reversal finds the tiles just passed still decoded. 2x is
        // the smallest that covers the biased "ahead" side after a reversal; less
        // re-decodes a few edge tiles on every change of direction. Costs up to
        // ~2x cacheSize thumbnails in memory.
        const keepReach = Math.max(ahead, radius * 2);
        root._setCacheEntries(
            urlsOf(root._windowIndices(center, ahead, behind, root._scrollDirection)),
            urlsOf(root._windowIndices(center, keepReach, keepReach, 1)));
    }

    function _populateStableModel(entries) {
        const activeView = root._currentView;
        const savedIndex = activeView.currentIndex;
        const savedFile = (savedIndex >= 0 && savedIndex < stableModel.count) ? stableModel.get(savedIndex).fileName : "";

        stableModel.clear();
        for (let i = 0; i < entries.length; i++)
            stableModel.append(entries[i]);

        if (root._isInfinite && entries.length > 0) {
            const viewWidth = pathView.width > 0 ? pathView.width : 2560;
            const minCount = Math.ceil(viewWidth / carousel.itemWidth) + 6;
            const baseCount = entries.length;
            const targetCount = baseCount * Math.ceil(minCount / baseCount);
            while (stableModel.count < targetCount) {
                for (let i = 0; i < baseCount && stableModel.count < targetCount; i++)
                    stableModel.append(entries[i]);
            }
        }

        if (savedFile) {
            for (let i = 0; i < stableModel.count; i++) {
                if (stableModel.get(i).fileName === savedFile) {
                    activeView.currentIndex = i;
                    break;
                }
            }
        }
    }

    function _syncStableModel() {
        const entries = _readFolderModel(folderModel);
        root._folderCache[root.wallpaperFolder] = entries;
        _populateStableModel(entries);
        root._currentCacheIndex = root._findCurrentIndex();
        root._rebuildCacheEntries();
        _applySearch();
        carousel.tryFocus();
    }

    function _applySearch() {
        const text = carousel._searchText.toLowerCase();
        const allEntries = root._folderCache[root.wallpaperFolder] || [];
        filteredModel.clear();
        const entries = text.length === 0 ? allEntries : allEntries.filter(e => e.fileName.toLowerCase().indexOf(text) !== -1);
        for (let i = 0; i < entries.length; i++)
            filteredModel.append(entries[i]);
        if (filteredModel.count > 0 && carousel.searchActive) {
            listView.currentIndex = 0;
            listView.positionViewAtIndex(0, ListView.Center);
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────
    function toggle() {
        if (overlay.visible)
            close();
        else
            open();
    }

    function open() {
        carousel.initialFocusSet = false;
        const screenHint = root.pendingScreenName;
        root.pendingScreenName = "";
        const focusedScreen = root.getFocusedScreen(screenHint);
        if (focusedScreen)
            overlay.screen = focusedScreen;
        overlay.visible = true;
        searchInput.text = "";
        carousel.searchVisible = false;
        carousel.tryFocus();
        Qt.callLater(() => root._currentView.forceActiveFocus());
    }

    function close() {
        overlay.visible = false;
    }

    function cycle(direction: int): string {
        const v = root._currentView;
        if (!overlay.visible) {
            open();
            return "opened:" + v.currentIndex;
        }
        if (direction > 0)
            v.incrementCurrentIndex();
        else
            v.decrementCurrentIndex();
        return "index:" + v.currentIndex;
    }

    // ── IPC (Quickshell — available on both DMS and Noctalia) ─────────────────
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
        function cycleNext(): string {
            return root.cycle(+1);
        }
        function cyclePrevious(): string {
            return root.cycle(-1);
        }

        // Screen-targeted variants for the Noctalia v5 plugin, which is told the focused output by its caller.
        function openOn(screenName: string): string {
            root.pendingScreenName = screenName;
            if (!overlay.visible)
                root.open();
            return "opened";
        }
        function closeOn(screenName: string): string {
            if (overlay.visible)
                root.close();
            return "closed";
        }
        function toggleOn(screenName: string): string {
            root.pendingScreenName = screenName;
            root.toggle();
            return overlay.visible ? "opened" : "closed";
        }
        function cycleNextOn(screenName: string): string {
            root.pendingScreenName = screenName;
            return root.cycle(+1);
        }
        function cyclePreviousOn(screenName: string): string {
            root.pendingScreenName = screenName;
            return root.cycle(-1);
        }
    }

    // ── Fullscreen overlay window ─────────────────────────────────────────────
    PanelWindow {
        id: overlay
        visible: false
        color: "transparent"

        WlrLayershell.namespace: root.wlrNamespace
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
            color: root.scrimColor
            opacity: overlay.visible ? carousel.overlayOpacity / 100 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: overlay.visible && carousel.confirmingIndex < 0
            onClicked: root.close()
        }

        // ── Carousel ──────────────────────────────────────────────────────────
        Item {
            id: carousel
            anchors.fill: parent
            opacity: overlay.visible ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }

            property bool initialFocusSet: false
            property string _searchText: ""
            readonly property bool searchActive: _searchText.length > 0
            property bool searchVisible: false

            function tryFocus() {
                if (initialFocusSet)
                    return;

                let targetIndex = 0;
                const currentFile = (root.currentWallpaperPath || "").split('/').pop();
                if (currentFile && stableModel.count > 0) {
                    for (let i = 0; i < stableModel.count; i++) {
                        if (stableModel.get(i).fileName === currentFile) {
                            targetIndex = i;
                            break;
                        }
                    }
                }

                const v = root._currentView;
                if (v.count > 0) {
                    const safeIndex = Math.min(targetIndex, v.count - 1);
                    v.currentIndex = safeIndex;
                    if (!root._isInfinite)
                        v.positionViewAtIndex(safeIndex, ListView.Center);
                    initialFocusSet = true;
                }

                carousel.heldIndex = -1;
                holdTimer.start();
            }

            readonly property int itemWidth: parseInt(root.cfg.itemWidth) || 300
            readonly property int itemHeight: parseInt(root.cfg.itemHeight) || 420
            readonly property int borderWidth: (root.cfg.borderWidth !== undefined) ? parseInt(root.cfg.borderWidth) : 3
            readonly property int overlayOpacity: (root.cfg.overlayOpacity !== undefined) ? parseInt(root.cfg.overlayOpacity) : 80
            readonly property int cornerRadius: (root.cfg.cornerRadius !== undefined) ? parseInt(root.cfg.cornerRadius) : 0
            readonly property bool enableRounding: cornerRadius > 0
            readonly property real skewFactor: -0.35
            readonly property int _baseWallpaperCount: folderModel.count

            readonly property real selectedScale: {
                let val = (root.cfg.selectedScale !== undefined) ? parseFloat(root.cfg.selectedScale) : 108;
                return val > 10 ? val / 100.0 : val;
            }
            readonly property bool expandSelected: !!(root.cfg.expandSelected === true || root.cfg.expandSelected === "true")
            readonly property real expandMultiplier: ((root.cfg.expandMultiplier !== undefined) ? parseInt(root.cfg.expandMultiplier) : 120) / 100.0
            readonly property bool enableHoldExpand: !!(root.cfg.enableHoldExpand === true || root.cfg.enableHoldExpand === "true")
            readonly property real holdExpandRatio: ((root.cfg.holdExpandRatio !== undefined) ? parseFloat(root.cfg.holdExpandRatio) : 35.0) / 100.0
            readonly property int holdDelay: (root.cfg.holdDelay !== undefined) ? parseInt(root.cfg.holdDelay) : 1500

            property int heldIndex: -1

            Timer {
                id: holdTimer
                interval: carousel.holdDelay
                onTriggered: {
                    if (carousel.enableHoldExpand)
                        carousel.heldIndex = root._currentView.currentIndex;
                }
            }

            property int confirmingIndex: -1

            function confirmPick(idx, path) {
                confirmingIndex = idx;
                confirmTimer.start();
                if (path) {
                    const screenName = overlay.screen ? overlay.screen.name : "";
                    root.wallpaperPicked(path, screenName);
                }
            }

            Timer {
                id: confirmTimer
                interval: 300
                onTriggered: {
                    carousel.confirmingIndex = -1;
                    root.close();
                }
            }

            // ── Shared delegate ───────────────────────────────────────────────
            Component {
                id: carouselDelegate

                Item {
                    id: delegateRoot
                    width: carousel.itemWidth
                    height: carousel.itemHeight
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                    required property int index
                    required property string fileName
                    required property string fileUrl

                    readonly property bool _effectivelyInfinite: root._isInfinite && !carousel.searchActive

                    readonly property bool isCurrent: _effectivelyInfinite ? PathView.isCurrentItem : ListView.isCurrentItem

                    readonly property int distFromCenter: {
                        if (_effectivelyInfinite) {
                            const n = stableModel.count;
                            if (n <= 1)
                                return 0;
                            const d = Math.abs(index - pathView.currentIndex);
                            return Math.min(d, n - d);
                        }
                        return Math.abs(index - listView.currentIndex);
                    }

                    readonly property real falloff: 1.0 / (1.0 + distFromCenter * distFromCenter)

                    readonly property real _dupeFade: {
                        if (!_effectivelyInfinite)
                            return 1.0;
                        const base = carousel._baseWallpaperCount;
                        if (base <= 0 || base >= stableModel.count)
                            return 1.0;
                        const n = stableModel.count;
                        const cur = pathView.currentIndex;
                        const wpOffset = ((index % base) - (cur % base) + base) % base;
                        const leftCount = Math.floor(base / 2);
                        const rightCount = Math.floor((base - 1) / 2);
                        let target;
                        if (wpOffset === 0)
                            target = cur;
                        else if (wpOffset <= rightCount)
                            target = (cur + wpOffset) % n;
                        else if (base - wpOffset <= leftCount)
                            target = (cur - (base - wpOffset) + n) % n;
                        else
                            return 0.0;
                        return index === target ? 1.0 : 0.0;
                    }

                    z: carousel.confirmingIndex === index ? 100 : isCurrent ? 10 : Math.max(1, 10 - distFromCenter)

                    function pickWallpaper() {
                        if (carousel.confirmingIndex >= 0)
                            return;
                        carousel.confirmPick(index, root.wallpaperFolder + "/" + fileName);
                    }

                    MouseArea {
                        id: delegateMouseArea
                        x: carousel.skewFactor * carousel.itemHeight / 2
                        width: parent.width
                        height: parent.height
                        hoverEnabled: true
                        onClicked: delegateRoot.pickWallpaper()
                    }

                    readonly property real extraSpace: carousel.itemWidth * carousel.expandMultiplier - carousel.itemWidth
                    readonly property real heldExtraSpace: carousel.width * carousel.holdExpandRatio - carousel.itemWidth

                    readonly property real visualXOffset: {
                        if (!carousel.expandSelected && carousel.heldIndex < 0)
                            return 0;
                        if (carousel.heldIndex === index)
                            return 0;
                        if (distFromCenter === 0)
                            return 0;
                        const space = (carousel.heldIndex >= 0) ? heldExtraSpace : extraSpace;
                        let signedDist = 0;
                        if (_effectivelyInfinite) {
                            let d = index - pathView.currentIndex;
                            const h = stableModel.count / 2;
                            if (d > h)
                                d -= stableModel.count;
                            else if (d < -h)
                                d += stableModel.count;
                            signedDist = d;
                        } else {
                            signedDist = index - listView.currentIndex;
                        }
                        return signedDist > 0 ? (space / 2) : -(space / 2);
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: visualXOffset

                        readonly property bool isConfirmed: carousel.confirmingIndex === delegateRoot.index
                        readonly property bool isHeld: carousel.heldIndex === delegateRoot.index

                        width: isHeld ? (carousel.width * carousel.holdExpandRatio) : ((carousel.expandSelected && isCurrent) ? (carousel.itemWidth * carousel.expandMultiplier) : carousel.itemWidth)
                        height: isHeld ? (carousel.height * carousel.holdExpandRatio) : parent.height

                        Behavior on anchors.horizontalCenterOffset {
                            NumberAnimation {
                                duration: 400
                                easing.type: Easing.InOutCubic
                            }
                        }
                        Behavior on width {
                            NumberAnimation {
                                duration: 400
                                easing.type: Easing.InOutCubic
                            }
                        }
                        Behavior on height {
                            NumberAnimation {
                                duration: 400
                                easing.type: Easing.InOutCubic
                            }
                        }

                        readonly property bool isOtherConfirming: carousel.confirmingIndex >= 0 && !isConfirmed
                        readonly property bool isHovered: delegateMouseArea.containsMouse && carousel.confirmingIndex < 0

                        readonly property real baseScale: 0.75
                        readonly property real scaleRange: carousel.selectedScale - 0.75

                        scale: isConfirmed ? 1.6 : isOtherConfirming ? (baseScale + scaleRange * delegateRoot.falloff) * 0.8 : isHovered ? baseScale + (scaleRange + 0.20) * delegateRoot.falloff : baseScale + scaleRange * delegateRoot.falloff
                        opacity: (isConfirmed ? 0.0 : isOtherConfirming ? 0.0 : isHovered ? 1.0 : 0.1 + 0.9 * delegateRoot.falloff) * delegateRoot._dupeFade
                        layer.enabled: opacity < 1 && opacity > 0 && !isConfirmed

                        Behavior on scale {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutBack
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 300
                            }
                        }

                        transform: Matrix4x4 {
                            property real s: carousel.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }

                        ClippingRectangle {
                            anchors.fill: parent
                            color: "transparent"
                            radius: carousel.enableRounding ? carousel.cornerRadius : 0
                            antialiasing: carousel.enableRounding

                            Image {
                                anchors.fill: parent
                                source: delegateRoot.fileUrl
                                sourceSize: (carousel.heldIndex === delegateRoot.index) ? Qt.size(width, height) : Qt.size(carousel.itemWidth, carousel.itemHeight)
                                // Must match innerImage and the pre-cache window: fillMode is part of
                                // Qt's image cache key, so any other mode decodes the file again.
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: innerImage.status === Image.Ready
                            }

                            Item {
                                anchors.fill: parent
                                anchors.margins: carousel.borderWidth
                                visible: innerImage.status === Image.Ready

                                Rectangle {
                                    anchors.fill: parent
                                    color: "black"
                                }
                                clip: true

                                Image {
                                    id: innerImage
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: -50
                                    width: parent.width + (parent.height * Math.abs(carousel.skewFactor)) + 50
                                    height: parent.height
                                    fillMode: Image.PreserveAspectCrop
                                    source: delegateRoot.fileUrl
                                    sourceSize: (carousel.heldIndex === delegateRoot.index) ? Qt.size(width, height) : Qt.size(carousel.itemWidth, carousel.itemHeight)
                                    asynchronous: true

                                    transform: Matrix4x4 {
                                        property real s: -carousel.skewFactor
                                        matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── PathView — looping ────────────────────────────────────────────
            PathView {
                id: pathView
                anchors.fill: parent
                visible: root._isInfinite && !carousel.searchActive

                model: (root._isInfinite && !carousel.searchActive) ? stableModel : null
                delegate: carouselDelegate

                pathItemCount: Math.max(1, Math.min(stableModel.count, Math.ceil(width / carousel.itemWidth) + 4))
                cacheItemCount: 4

                preferredHighlightBegin: 0.5
                preferredHighlightEnd: 0.5
                highlightRangeMode: PathView.StrictlyEnforceRange

                highlightMoveDuration: carousel.initialFocusSet ? 150 : 0
                movementDirection: PathView.Shortest

                focus: root._isInfinite && !carousel.searchVisible && overlay.visible

                Keys.onPressed: event => {
                    if (carousel.confirmingIndex >= 0) {
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                        carousel.searchVisible = true;
                        searchInput.forceActiveFocus();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        decrementCurrentIndex();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        incrementCurrentIndex();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (currentItem)
                            currentItem.pickWallpaper();
                        event.accepted = true;
                    }
                }

                onCountChanged: carousel.tryFocus()
                onCurrentIndexChanged: {
                    carousel.heldIndex = -1;
                    holdTimer.restart();
                    root._followViewIndex(currentIndex);
                }

                readonly property real _pathLen: pathItemCount * carousel.itemWidth
                readonly property real _pathX0: (width - _pathLen) / 2
                path: Path {
                    startX: pathView._pathX0
                    startY: pathView.height / 2 - carousel.itemHeight / 2
                    PathLine {
                        x: pathView._pathX0 + pathView._pathLen
                        y: pathView.height / 2 - carousel.itemHeight / 2
                    }
                }
            }

            // ── ListView — wrap / standard ────────────────────────────────────
            ListView {
                id: listView
                anchors.fill: parent
                visible: !root._isInfinite || carousel.searchActive

                model: carousel.searchActive ? filteredModel : (root._isInfinite ? null : stableModel)
                delegate: carouselDelegate

                spacing: 0
                orientation: ListView.Horizontal
                clip: false
                cacheBuffer: 5000

                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width / 2) - (carousel.itemWidth / 2)
                preferredHighlightEnd: (width / 2) + (carousel.itemWidth / 2)

                highlightMoveDuration: carousel.initialFocusSet ? 150 : 0

                focus: !root._isInfinite && !carousel.searchVisible && overlay.visible

                Keys.onPressed: event => {
                    if (carousel.confirmingIndex >= 0) {
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                        carousel.searchVisible = true;
                        searchInput.forceActiveFocus();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        if (currentIndex > 0)
                            decrementCurrentIndex();
                        else if (root._wrapsIndex)
                            currentIndex = count - 1;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        if (currentIndex < count - 1)
                            incrementCurrentIndex();
                        else if (root._wrapsIndex)
                            currentIndex = 0;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Home) {
                        currentIndex = 0;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_End) {
                        currentIndex = count - 1;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (currentItem)
                            currentItem.pickWallpaper();
                        event.accepted = true;
                    }
                }

                onCountChanged: carousel.tryFocus()
                onCurrentIndexChanged: {
                    carousel.heldIndex = -1;
                    holdTimer.restart();
                    root._followViewIndex(currentIndex);
                }
            }
        }

        // ── Search bar ────────────────────────────────────────────────────────
        Item {
            id: searchBar
            visible: carousel.searchVisible
            anchors.top: parent.top
            anchors.topMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            width: searchBox.width
            height: searchBox.height
            z: 200

            MouseArea {
                anchors.fill: parent
            }

            Rectangle {
                id: searchBox
                width: 360
                height: 40
                radius: root.uiRadius
                color: root.searchBackgroundColor
                border.color: searchInput.activeFocus ? root.searchFocusBorderColor : root.searchBorderColor
                border.width: 1

                Behavior on border.color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: root.uiSpacing
                    anchors.rightMargin: root.uiSpacing
                    verticalAlignment: Text.AlignVCenter
                    text: "Search wallpapers..."
                    color: root.searchPlaceholderColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSizeLarge
                    visible: searchInput.text.length === 0
                }

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.leftMargin: root.uiSpacing
                    anchors.rightMargin: root.uiSpacing
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.searchTextColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSizeLarge
                    clip: true

                    onTextChanged: {
                        carousel._searchText = text;
                        root._applySearch();
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            if (text.length > 0) {
                                text = "";
                            } else {
                                carousel.searchVisible = false;
                                root._currentView.forceActiveFocus();
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left) {
                            root._currentView.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Right) {
                            root._currentView.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const v = root._currentView;
                            if (v.currentItem)
                                v.currentItem.pickWallpaper();
                            event.accepted = true;
                        }
                    }
                }
            }
        }

        // ── Invalid override directory ─────────────────────────────────────────
        Column {
            anchors.centerIn: parent
            spacing: root.uiSpacing
            visible: overlay.visible && (root.cfg.wallpaperDirectory ?? "").trim() && folderModel.status !== FolderListModel.Ready

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Directory not found"
                font.family: root.fontFamily
                font.pixelSize: root.fontSizeTitle
                font.bold: true
                color: root.onScrimTextColor
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "The configured directory '" + (root.cfg.wallpaperDirectory ?? "") + "' does not exist.\nCheck the path in Wallpaper Carousel settings."
                font.family: root.fontFamily
                font.pixelSize: root.fontSizeMedium
                color: root.onScrimSecondaryTextColor
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Press Escape to close"
                font.family: root.fontFamily
                font.pixelSize: root.fontSizeSmall
                color: root.onScrimTertiaryTextColor
            }
        }

        // ── Empty folder ──────────────────────────────────────────────────────
        Column {
            anchors.centerIn: parent
            spacing: root.uiSpacing
            visible: overlay.visible && folderModel.status === FolderListModel.Ready && folderModel.count === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hasWallpaperConfigured ? "No images found in wallpaper folder" : "No wallpaper configured"
                font.family: root.fontFamily
                font.pixelSize: root.fontSizeTitle
                font.bold: true
                color: root.onScrimTextColor
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hasWallpaperConfigured ? "The folder '" + root.wallpaperFolder + "' is empty.\nAdd images or choose a different wallpaper directory." : root.shellSettingsHint
                font.family: root.fontFamily
                font.pixelSize: root.fontSizeMedium
                color: root.onScrimSecondaryTextColor
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Press Escape to close"
                font.family: root.fontFamily
                font.pixelSize: root.fontSizeSmall
                color: root.onScrimTertiaryTextColor
            }
        }
    }

    // ── Pre-cache window ──────────────────────────────────────────────────────
    PanelWindow {
        id: cacheWindow
        visible: true
        color: "transparent"
        implicitWidth: 1
        implicitHeight: 1

        WlrLayershell.namespace: root.wlrNamespace + ":precache"
        WlrLayershell.layer: WlrLayershell.Background
        WlrLayershell.exclusiveZone: 0
        anchors {
            top: true
            left: true
        }

        Item {
            width: 1
            height: 1
            clip: true

            Repeater {
                model: cacheModel
                Image {
                    width: carousel.itemWidth
                    height: carousel.itemHeight
                    asynchronous: true
                    source: model.url
                    sourceSize: Qt.size(carousel.itemWidth, carousel.itemHeight)
                    fillMode: Image.PreserveAspectCrop
                }
            }

            // Pre-scan and cache other monitor directories (provided by wrapper)
            Repeater {
                model: root.extraDirectories
                Item {
                    property string dir: modelData
                    FolderListModel {
                        id: extraFolderModel
                        folder: "file://" + dir
                        nameFilters: root._nameFilters
                        showDirs: false
                        sortField: FolderListModel.Name
                        onStatusChanged: {
                            if (status === FolderListModel.Ready)
                                root._folderCache[dir] = root._readFolderModel(extraFolderModel);
                        }
                        onCountChanged: {
                            if (status === FolderListModel.Ready)
                                root._folderCache[dir] = root._readFolderModel(extraFolderModel);
                        }
                    }
                    Repeater {
                        model: extraFolderModel
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
        }
    }
}
