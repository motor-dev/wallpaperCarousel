import QtQuick
import Quickshell
import Quickshell.Io

// Standalone Quickshell entry point for the Noctalia v5 integration.
//
// Noctalia v5 is a native C++ shell with no QML runtime, so this file is not
// loaded *by* Noctalia the way Main.qml (v4) and WallpaperCarousel.qml (DMS) are.
// It is a separate `qs -p .../shell.qml` process started and owned by the
// wallpaper-carousel.luau service. Where those adapters bind Carousel's interface
// straight to a live Settings/SessionData singleton in the same process, this one
// has no singleton to bind to: everything comes in through one JSON file the
// service writes and this file watches.
//
//   host-state.json  →  settings, wallpaper directory, current wallpaper per
//                       output, and a sequence-numbered command. A command runs
//                       when `seq` changes, which also covers the startup case:
//                       the service writes the command *before* launching us, so
//                       the very first open is not lost to a socket that is not
//                       listening yet.
//
//   noctalia msg     →  back the other way, for the two things this process
//                       cannot do itself: applying a wallpaper (v5 renders
//                       wallpapers natively and exposes no IPC command for it —
//                       only the plugin's Luau side can call setWallpaper) and
//                       reporting overlay visibility for the Control Center
//                       shortcut's toggle state.
ShellRoot {
    id: root

    // ── State pushed in by wallpaper-carousel.luau ─────────────────────────────

    // Plugin settings, mirroring plugin.toml's [[setting]] keys.
    property var pluginConfig: ({})

    // wallpaperDirectory must never be "": FolderListModel resolves an empty — or
    // even a nonexistent — folder by silently scanning this process's working
    // directory instead, so until the host names a real one, fall back to
    // something guaranteed to exist.
    readonly property string _fallbackDirectory: Quickshell.env("HOME") || "/tmp"
    property string wallpaperDirectory: root._fallbackDirectory
    property var currentWallpaperByScreen: ({})  // { [outputName]: path }; "" = the shell-wide default
    property var extraWallpaperDirectories: []
    property bool wallpaperConfigured: false
    // Palette from noctalia.getColor, as "#RRGGBB" per role; any role may be
    // missing (older shell, unknown role), in which case Carousel's default stays.
    property var theme: ({})

    // A themed colour with alpha prepended, or the fallback when the role is missing.
    function themeColor(role, alphaHex, fallback) {
        const hex = root.theme[role];
        return (typeof hex === "string" && /^#[0-9A-Fa-f]{6}$/.test(hex)) ? "#" + alphaHex + hex.slice(1) : fallback;
    }

    // Set from the state file so the reply address is never hardcoded here.
    property string serviceEntryId: "yngwe/wallpaperCarousel:service"

    property int lastCommandSeq: -1

    function findScreen(name) {
        if (!name)
            return null;
        for (const screen of Quickshell.screens) {
            if (screen.name === name)
                return screen;
        }
        return null;
    }

    // Fire-and-forget event back to the Luau service. `noctalia msg` joins its
    // trailing arguments with spaces and the plugin router takes everything after
    // the event name as the payload, so a single JSON argument survives intact.
    function notifyService(event, payload) {
        Quickshell.execDetached(["noctalia", "msg", "plugin", root.serviceEntryId, "all", event, JSON.stringify(payload ?? {})]);
    }

    function applyCommand(command, screenName) {
        switch (command) {
        case "open":
            carousel.pendingScreenName = screenName;
            if (!carousel.overlayVisible)
                carousel.open();
            break;
        case "close":
            if (carousel.overlayVisible)
                carousel.close();
            break;
        case "toggle":
            carousel.pendingScreenName = screenName;
            carousel.toggle();
            break;
        case "next":
            carousel.pendingScreenName = screenName;
            carousel.cycle(+1);
            break;
        case "prev":
            carousel.pendingScreenName = screenName;
            carousel.cycle(-1);
            break;
        case "quit":
            Qt.quit();
            break;
        case "":
        case undefined:
            break;                       // state-only refresh
        default:
            console.warn("wallpaperCarousel: unknown command '" + command + "'");
        }
    }

    function applyState(state) {
        root.pluginConfig = state.config ?? {};
        root.wallpaperDirectory = (state.wallpaperDirectory ?? "").trim() || root._fallbackDirectory;
        root.currentWallpaperByScreen = state.currentWallpaper ?? {};
        // An empty Lua table serializes to `{}`, not `[]`, so coerce rather than
        // handing a bare object to the Repeater that pre-scans these.
        root.extraWallpaperDirectories = Array.isArray(state.extraDirectories) ? state.extraDirectories : [];
        root.wallpaperConfigured = !!state.wallpaperConfigured;
        // An empty Lua table serializes to `[]` or `{}`; either way, no roles.
        root.theme = (state.theme && !Array.isArray(state.theme)) ? state.theme : {};
        if (state.entryId)
            root.serviceEntryId = state.entryId;

        const seq = state.seq ?? 0;
        if (seq !== root.lastCommandSeq) {
            root.lastCommandSeq = seq;
            // Settings above are applied first so a command that opens the
            // overlay already sees the directory it should be browsing.
            Qt.callLater(() => root.applyCommand(state.command ?? "", state.screen ?? ""));
        }
    }

    // The service resolves this (it owns the plugin data dir) and hands it over in
    // the environment, so this process needs no knowledge of Noctalia's directory
    // layout. The literal fallback only exists so `qs -p shell.qml` by hand, for
    // debugging, still finds the file a running service is writing.
    readonly property string statePath: Quickshell.env("WALLPAPER_CAROUSEL_STATE")
        || ((Quickshell.env("HOME") || "") + "/.local/state/noctalia/plugins/data/yngwe/wallpaperCarousel/host-state.json")

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true

        onFileChanged: reload()
        onLoaded: root.readState()
        onLoadFailed: error => console.warn("wallpaperCarousel: cannot read " + root.statePath + ": " + error)
    }

    // The service writes this file in place rather than atomically, so a read can
    // land mid-write and fail to parse. That is transient by definition — retry
    // shortly rather than dropping the update.
    Timer {
        id: retryTimer
        interval: 120
        onTriggered: stateFile.reload()
    }

    function readState() {
        try {
            root.applyState(JSON.parse(stateFile.text()));
        } catch (e) {
            retryTimer.restart();
        }
    }

    Carousel {
        id: carousel

        wlrNamespace: "noctalia:plugins:wallpaperCarousel"
        cfg: root.pluginConfig

        // This process has no compositor connection of its own to detect focus
        // with, so the focused output is whatever the service told us when it
        // wrote the command. Fall back to the first known screen so a bare
        // `qs -p shell.qml` still opens somewhere.
        getFocusedScreen: hint => root.findScreen(hint) ?? (Quickshell.screens[0] ?? null)

        defaultWallpaperFolder: root.wallpaperDirectory
        extraDirectories: root.extraWallpaperDirectories
        hasWallpaperConfigured: root.wallpaperConfigured

        currentWallpaperPath: {
            const name = carousel.overlayScreen?.name ?? "";
            return root.currentWallpaperByScreen[name] ?? root.currentWallpaperByScreen[""] ?? "";
        }

        shellSettingsHint: "Open Noctalia Settings → Wallpaper,\nand select a wallpaper directory."

        // Palette colours (fallbacks are Carousel's defaults). Text drawn straight
        // on the scrim keeps its light defaults: the scrim stays dark in light mode.
        // No font/radius tokens: the v5 runtime API exposes neither.
        scrimColor: root.themeColor("scrim", "CC", "#CC000000")
        searchBackgroundColor: root.themeColor("surface", "F2", "#BB000000")
        searchTextColor: root.themeColor("onSurface", "FF", "white")
        searchPlaceholderColor: root.themeColor("onSurfaceVariant", "FF", "#55FFFFFF")
        searchBorderColor: root.themeColor("onSurfaceVariant", "66", "#44FFFFFF")
        searchFocusBorderColor: root.themeColor("primary", "FF", "#AAFFFFFF")

        onWallpaperPicked: (fullPath, screenName) => {
            root.notifyService("picked", {
                path: fullPath,
                screen: screenName ?? ""
            });
        }

        onOverlayVisibleChanged: root.notifyService(carousel.overlayVisible ? "opened" : "closed", {})
    }

    // ── Host plumbing IPC ─────────────────────────────────────────────────────
    // Kept on its own target, separate from Carousel's user-facing
    // "wallpaperCarousel" handler (toggle/open/close/cycle…), so the service's
    // liveness probe and shutdown request never collide with a user command.
    IpcHandler {
        target: "wallpaperCarouselHost"

        function ping(): string {
            return "ok";
        }

        function quit(): string {
            Qt.quit();
            return "quitting";
        }
    }
}
