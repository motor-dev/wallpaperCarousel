-- Wallpaper Carousel — Noctalia v5 service entry.
--
-- Noctalia v5 is a native C++ shell: its plugin surface is Luau plus a
-- declarative UI vocabulary, and it has no QML runtime at all. The carousel is a
-- Quickshell overlay built out of PathView/ListView, layer-shell surfaces, skew
-- transforms and per-tile animations — none of which that vocabulary can
-- express. So this service does not draw the carousel; it *owns* a Quickshell
-- child process that does (shell.qml, next to this file), and acts as the bridge
-- between it and the shell.
--
-- Two channels, both deliberately dumb:
--
--   Lua → QML   a single JSON file, <plugin data dir>/host-state.json, watched by
--               a FileView in shell.qml. It carries the settings and the wallpaper
--               state, plus a sequence-numbered command. Writing the file *is*
--               sending the command, which means a command issued before the
--               child has finished starting is still executed — the child reads
--               the same file on startup. No socket-readiness race to lose.
--
--   QML → Lua   `noctalia msg plugin yngwe/wallpaperCarousel:service all <event>
--               <json>`, i.e. this script's onIpc below. Only used for the two
--               things the child cannot do itself: applying a wallpaper (v5
--               renders wallpapers natively; there is no `noctalia msg` command
--               for it, only noctalia.setWallpaper here) and reporting overlay
--               visibility so the Control Center shortcut can show its state.
--
-- The child is started with noctalia.runStream rather than runAsync so the host
-- owns its lifetime: disabling the plugin, reloading the script or quitting the
-- shell tears the stream down and kills the overlay with it, instead of leaving
-- an orphaned Quickshell process holding a layer-shell surface.

local PLUGIN_ID = "yngwe/wallpaperCarousel"
local ENTRY_ID = PLUGIN_ID .. ":service"

-- IpcHandler target in shell.qml. Distinct from Carousel.qml's own
-- "wallpaperCarousel" handler: that one is the user-facing command surface shared
-- with the DankMaterialShell/Noctalia-v4 builds, this one is host plumbing.
local HOST_TARGET = "wallpaperCarouselHost"

local pluginDir = noctalia.pluginDir()
local shellPath = pluginDir .. "/shell.qml"
local dataDir = noctalia.pluginDataDir()
local statePath = (dataDir or pluginDir) .. "/host-state.json"

-- ── Small helpers ─────────────────────────────────────────────────────────────

-- Every command here goes through `/bin/sh -c`, so paths must be quoted. Single
-- quotes with the standard '\'' escape are the only form that is safe for
-- arbitrary bytes.
local function shq(text: string): string
	return "'" .. string.gsub(text, "'", [['\'']]) .. "'"
end

local function isBlank(text): boolean
	return type(text) ~= "string" or noctalia.string.trim(text) == ""
end

local function expand(path: string): string
	return isBlank(path) and "" or noctalia.expandPath(noctalia.string.trim(path))
end

-- ── Reading Noctalia's own wallpaper state ────────────────────────────────────
--
-- The runtime API exposes the effective wallpaper *directory*
-- (noctalia.wallpaperDirectory()) but not which image is currently on which
-- output, and the carousel needs that to open centered on the current wallpaper.
-- v5 persists it in the shell's settings.toml, so read it from there. This is
-- best-effort by design: every field falls back to empty and the carousel simply
-- opens on the first image.

local function settingsTomlPath(): string
	local override = noctalia.getenv("NOCTALIA_STATE_HOME")
	if not isBlank(override) then
		return override .. "/noctalia/settings.toml"
	end
	local xdg = noctalia.getenv("XDG_STATE_HOME")
	if not isBlank(xdg) then
		return xdg .. "/noctalia/settings.toml"
	end
	return noctalia.expandPath("~/.local/state/noctalia/settings.toml")
end

-- Strips the optional quoting TOML allows around a bare key segment.
local function unquoteKey(key: string): string
	return string.match(key, '^"(.*)"$') or string.match(key, "^'(.*)'$") or key
end

-- A deliberately small TOML reader: it only understands section headers and
-- `key = "value"` lines, which is all the [wallpaper] tree uses. Anything else in
-- the file is skipped rather than misparsed.
local function readShellWallpaperState()
	local out = { directory = "", directoryLight = "", directoryDark = "", default = "", monitors = {} }
	local text = noctalia.readFile(settingsTomlPath())
	if type(text) ~= "string" then
		return out
	end

	local section = ""
	for rawLine in string.gmatch(text, "[^\r\n]+") do
		local line = noctalia.string.trim(rawLine)
		-- Array-of-tables headers ([[wallpaper.favorite]]) must be recognised
		-- before plain ones, otherwise the section would still read as the
		-- previous monitor and each favourite's `path` would overwrite it.
		local arrayHeader = string.match(line, "^%[%[(.+)%]%]$")
		local header = arrayHeader == nil and string.match(line, "^%[([^%[%]]+)%]$") or nil
		if arrayHeader ~= nil then
			section = "\0array"
		elseif header ~= nil then
			section = header
		else
			local key, value = string.match(line, '^([%w_%-%.]+)%s*=%s*"(.*)"$')
			if key ~= nil then
				if section == "wallpaper" then
					if key == "directory" then
						out.directory = expand(value)
					elseif key == "directory_light" then
						out.directoryLight = expand(value)
					elseif key == "directory_dark" then
						out.directoryDark = expand(value)
					end
				elseif section == "wallpaper.default" and key == "path" then
					out.default = expand(value)
				elseif key == "path" then
					local monitor = string.match(section, "^wallpaper%.monitors%.(.+)$")
					if monitor ~= nil then
						out.monitors[unquoteKey(monitor)] = expand(value)
					end
				end
			end
		end
	end
	return out
end

-- ── Settings ──────────────────────────────────────────────────────────────────
--
-- Read as literal getConfig calls, one per declared key: that keeps
-- `noctalia plugins lint` able to cross-check the manifest against actual reads,
-- which a table-driven loop would defeat.
local function currentConfig()
	return {
		-- Expanded here rather than in QML: Carousel feeds this straight to a
		-- FolderListModel as `file://` + path, where a leading `~` is a literal
		-- directory name and silently resolves to nothing.
		wallpaperDirectory = expand(noctalia.getConfig("wallpaperDirectory")),
		carouselMode = noctalia.getConfig("carouselMode"),
		overlayOpacity = noctalia.getConfig("overlayOpacity"),
		borderWidth = noctalia.getConfig("borderWidth"),
		cornerRadius = noctalia.getConfig("cornerRadius"),
		itemWidth = noctalia.getConfig("itemWidth"),
		itemHeight = noctalia.getConfig("itemHeight"),
		selectedScale = noctalia.getConfig("selectedScale"),
		expandSelected = noctalia.getConfig("expandSelected"),
		expandMultiplier = noctalia.getConfig("expandMultiplier"),
		enableHoldExpand = noctalia.getConfig("enableHoldExpand"),
		holdExpandRatio = noctalia.getConfig("holdExpandRatio"),
		holdDelay = noctalia.getConfig("holdDelay"),
		cacheSize = noctalia.getConfig("cacheSize"),
	}
end

-- ── Theme ─────────────────────────────────────────────────────────────────────
--
-- Palette colours for the overlay's search field and scrim, re-read on every
-- state write (there is no theme-change hook), so each open picks up the current
-- palette. noctalia.getColor only exists from plugin_api 31 (v5.2.0); on older
-- shells, and for any role it returns nil for, the carousel keeps its defaults.
-- Only role names that predate the plugin_api 43 renames are used, so this needs
-- no plugin_api bump and logs no deprecation warnings.
local function currentTheme()
	if typeof(noctalia.getColor) ~= "function" then
		return {}
	end
	return {
		scrim = noctalia.getColor("scrim"),
		surface = noctalia.getColor("surface"),
		onSurface = noctalia.getColor("on_surface"),
		onSurfaceVariant = noctalia.getColor("on_surface_variant"),
		primary = noctalia.getColor("primary"),
	}
end

-- ── State file ────────────────────────────────────────────────────────────────

local seq = 0
-- Wallpapers picked in this session, keyed by output name ("" = all outputs).
-- settings.toml is written asynchronously by the shell, so right after a pick the
-- file on disk still names the previous image; these keep the carousel's
-- highlight correct until the next open re-reads it.
local pickOverrides: { [string]: string } = {}

local function buildState(command: string, screen: string)
	local shell = readShellWallpaperState()
	local override = noctalia.getConfig("wallpaperDirectory")
	local hostDirectory = noctalia.wallpaperDirectory()
	-- The runtime API resolves theme-mode-specific directories, so prefer it and
	-- only fall back to the raw config value.
	local directory = expand(hostDirectory)
	if directory == "" then
		directory = shell.directory
	end

	-- Directories worth pre-scanning so switching theme mode does not re-read the
	-- disk. Never includes the directory already being browsed.
	local browsing = expand(override)
	if browsing == "" then
		browsing = directory
	end
	local extras = {}
	local seen = { [browsing] = true, [""] = true }
	for _, candidate in { shell.directory, shell.directoryLight, shell.directoryDark } do
		if not seen[candidate] then
			seen[candidate] = true
			table.insert(extras, candidate)
		end
	end

	local current = { [""] = shell.default }
	for output, path in shell.monitors do
		current[output] = path
	end
	for output, path in pickOverrides do
		current[output] = path
	end

	return {
		seq = seq,
		command = command,
		screen = screen,
		entryId = ENTRY_ID,
		config = currentConfig(),
		theme = currentTheme(),
		wallpaperDirectory = directory,
		wallpaperConfigured = directory ~= "" or browsing ~= "",
		currentWallpaper = current,
		extraDirectories = extras,
	}
end

local function writeState(command: string, screen: string)
	local encoded = noctalia.json.encode(buildState(command, screen))
	if type(encoded) ~= "string" then
		noctalia.log("wallpaperCarousel: could not encode host state")
		return
	end
	local ok, err = noctalia.writeFile(statePath, encoded)
	if not ok then
		noctalia.log("wallpaperCarousel: could not write " .. statePath .. ": " .. tostring(err))
	end
end

-- Refresh settings/wallpaper state without re-triggering the last command: the
-- child only acts on `seq` changing.
local function refreshState()
	writeState("", "")
end

-- ── The Quickshell child ──────────────────────────────────────────────────────

local shellRunning = false
local warnedMissingQuickshell = false

local function startShell(): boolean
	if not noctalia.commandExists("qs") then
		if not warnedMissingQuickshell then
			warnedMissingQuickshell = true
			noctalia.notifyError(noctalia.tr("notify.title"), noctalia.tr("notify.quickshell-missing"))
		end
		return false
	end

	-- `exec` so the process the host can signal is Quickshell itself and not an
	-- intermediate shell; `-n` so a stale probe can never produce two overlays.
	local command = "WALLPAPER_CAROUSEL_STATE=" .. shq(statePath) .. " exec qs -n -p " .. shq(shellPath)
	local started = noctalia.runStream(command, function(line)
		noctalia.log("wallpaperCarousel/qs: " .. line)
	end)
	if not started then
		noctalia.notifyError(noctalia.tr("notify.title"), noctalia.tr("notify.start-failed"))
		return false
	end
	shellRunning = true
	return true
end

-- Confirm the child we think we started is still there, and bring it back if it
-- is not. The command itself has already been written to the state file by the
-- time this runs, so a restarted child executes it on startup.
local function ensureShellAlive()
	if not shellRunning then
		startShell()
		return
	end
	noctalia.runAsync("qs -p " .. shq(shellPath) .. " ipc call " .. HOST_TARGET .. " ping", function(result)
		if result.exitCode ~= 0 then
			shellRunning = false
			startShell()
		end
	end)
end

-- Bump the sequence and write the command out. Writing is sending: a child that
-- is already up sees the file change, one that is still starting reads the same
-- file on load.
local function sendCommand(command: string, screen: string)
	-- Reopening is the point at which settings.toml is authoritative again.
	pickOverrides = {}
	seq += 1
	writeState(command, screen)
end

local function dispatch(command: string, screen: string)
	sendCommand(command, screen)
	ensureShellAlive()
end

-- ── Applying a pick ───────────────────────────────────────────────────────────

local function applyPick(payload: string)
	local data = noctalia.json.decode(payload)
	if type(data) ~= "table" or type(data.path) ~= "string" or data.path == "" then
		noctalia.log("wallpaperCarousel: ignoring malformed pick payload: " .. tostring(payload))
		return
	end

	-- Noctalia has no global "one wallpaper everywhere" mode: every output carries
	-- its own path, and the built-in picker resolves the ambiguity with a monitor
	-- dropdown. The carousel has no dropdown — it opens on whichever output had
	-- focus — so this setting decides what picking there means.
	local screen = ""
	if noctalia.getConfig("applyToAllMonitors") ~= true then
		screen = type(data.screen) == "string" and data.screen or ""
	end

	if screen ~= "" then
		noctalia.setWallpaper(screen, data.path)
		pickOverrides[screen] = data.path
	else
		-- The one-argument form sets every connected output *plus* the default,
		-- matching the wallpaper panel's "All monitors" (per-output paths win over
		-- the default, so setting only the default would change nothing). Mirror
		-- that across the overrides or the per-output paths still on disk would
		-- keep the carousel highlighting the previous image.
		noctalia.setWallpaper(data.path)
		pickOverrides = { [""] = data.path }
		for _, output in noctalia.outputs() do
			pickOverrides[output.name] = data.path
		end
	end
	refreshState()
end

-- ── Host callbacks ────────────────────────────────────────────────────────────

-- The DMS and Noctalia-v4 builds drive Carousel through its Quickshell IpcHandler,
-- whose functions are named cycleNext/cyclePrevious. Those names are in people's
-- compositor keybindings, so accept them here too rather than making a rename the
-- price of upgrading. Keys are lowercase: event names are folded before lookup.
local COMMAND_ALIASES: { [string]: string } = {
	cyclenext = "next",
	cycleprevious = "prev",
	cycleprev = "prev",
}

-- `noctalia msg plugin yngwe/wallpaperCarousel:service all <event> [payload]`
function onIpc(event, payload)
	local name = string.lower(noctalia.string.trim(tostring(event or "")))
	name = COMMAND_ALIASES[name] or name
	local body = noctalia.string.trim(tostring(payload or ""))

	if name == "toggle" or name == "open" or name == "close" or name == "next" or name == "prev" then
		-- The payload names the output to open on; without one, follow focus.
		local screen = body
		if screen == "" then
			screen = noctalia.focusedOutputName() or ""
		end
		dispatch(name, screen)
	elseif name == "quit" then
		-- Not via dispatch(): the liveness probe would race the child's own
		-- shutdown and restart what we just asked to stop.
		sendCommand("quit", "")
		shellRunning = false
	elseif name == "picked" then
		applyPick(body)
	elseif name == "opened" then
		noctalia.state.set("overlayOpen", true)
	elseif name == "closed" then
		noctalia.state.set("overlayOpen", false)
	else
		noctalia.log("wallpaperCarousel: unknown ipc event '" .. name .. "'")
	end
end

function onConfigChanged()
	refreshState()
	if noctalia.getConfig("preload") == true and not shellRunning then
		startShell()
	end
end

function onOutputsChanged()
	refreshState()
end

function onEnable()
	if noctalia.getConfig("preload") == true and not shellRunning then
		startShell()
	end
end

function onExit(signal, reason)
	if shellRunning then
		-- The host kills the stream on teardown anyway; asking first lets
		-- Quickshell release its layer-shell surfaces cleanly.
		noctalia.runAsync("qs -p " .. shq(shellPath) .. " ipc call " .. HOST_TARGET .. " quit")
	end
end

-- ── Load ──────────────────────────────────────────────────────────────────────

-- Writing the state file before anything else clears whatever command the
-- previous run left in it, so a child started later cannot replay a stale one.
refreshState()
noctalia.state.set("overlayOpen", false)

-- The Control Center shortcut runs in its own runtime and reaches us through the
-- per-plugin state store rather than through a subprocess.
noctalia.state.watch("command", function(value)
	if type(value) ~= "table" or type(value.action) ~= "string" then
		return
	end
	local screen = type(value.screen) == "string" and value.screen or (noctalia.focusedOutputName() or "")
	dispatch(value.action, screen)
end)

if noctalia.getConfig("preload") == true then
	startShell()
end
