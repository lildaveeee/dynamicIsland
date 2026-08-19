import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

ShellRoot {
    Scope {
        id: root
        property string islandState: "default"
        property bool   islandVisible: true

        property string clickLeft:   "music"
        property string clickRight:  "controlPanel"
        property string clickMiddle: "notifHistory"
        property string dragDown:      "appLauncher"
        property string dragDownRight: "screenTime"

        function doClickAction(action) {
            if (action === "none" || action === "") return
            if (action === "appLauncher") {
                root.appLauncherQuery = ""
                appLauncherModel.clear()
                root.appLauncherOpen = true
                root.islandState = "appLauncher"
                appLauncherLoader.running = false
                appLauncherLoader.running = true
            } else if (action === "screenTime") {
                root.islandState = "screenTime"
                root.screenTimeOpen = true
                root.refreshPlaytimeModel()
            } else {
                root.islandState = (root.islandState === action) ? "default" : action
            }
        }

        property string pillColor:   "#000000"
        property real   pillOpacity: 1.0
        property string accentColor: root.accentColor
        property string textColor:   root.textColor
        property string fontFamily:  ""

        function tc(a) {
            var c = Qt.color(root.textColor)
            return Qt.rgba(c.r, c.g, c.b, a)
        }

        function pillBg(extraAlpha) {
            var c = Qt.color(root.pillColor)
            return Qt.rgba(c.r, c.g, c.b, (extraAlpha !== undefined ? extraAlpha : 1.0) * root.pillOpacity)
        }

        function arcColor(pct) {
            if (pct < 60) return root.textColor
            if (pct < 85) return "#F5A623"
            return "#FF5F5F"
        }
        // ── Per-monitor scaling ─────────────────────────────────────────
        // Hyprland.focusedMonitor updates whenever focus moves to a different
        // screen (including via ctrl+space toggling the island on another
        // monitor). height/scale gives logical pixels; 1080 is the baseline.
        readonly property real uiScale: {
            var m = Hyprland.focusedMonitor
            if (!m || m.height <= 0 || m.scale <= 0) return 1.0
            return (m.height / m.scale) / 1080.0
        }

        property string currentTime: Qt.formatDateTime(new Date(), "HH:mm")
        property string currentDate: Qt.formatDateTime(new Date(), "ddd, d MMM")
	property var    cavaBars: []
	property var    cavaPending: []
	property bool   cavaUpdatePending: false
        property string songTitle:  ""
        property string songArtist: ""
        property string albumArt:   ""
        property bool   isPlaying:  false

        GlobalShortcut {
            name: "toggleIsland"
            description: "Toggle the Dynamic Island visibility"
            onPressed: root.islandVisible = !root.islandVisible
        }

        property string notifSummary:      ""
        property string notifBody:         ""
        property string notifAppName:      ""
        property string notifIconPath:     ""
        property string notifDesktopEntry: ""
        property string notifUrl:          ""
        property bool   notifVisible:      false

        Process {
            id: notifLaunchProcess
            command: []
        }
        function launchNotifApp(desktopEntry, appName, url) {
            var u = (url || "").trim()
            if (u !== "") {
                notifLaunchProcess.command = ["xdg-open", u]
                notifLaunchProcess.running = true
                return
            }
            var entry = (desktopEntry || "").trim()
            if (entry === "")
                entry = (appName || "").toLowerCase().replace(/ /g, "-")
            if (entry === "") return
            notifLaunchProcess.command = ["gtk-launch", entry]
            notifLaunchProcess.running = true
        }

        Timer {
            id: notifDismissTimer
            interval: 5000
            repeat: false
            onTriggered: {
                root.notifVisible = false
                if (root.islandState === "notification")
                    root.islandState = "default"
            }
        }

        Process {
            id: dunstSetup
            running: true
            command: ["bash", Qt.resolvedUrl("./scripts/dunst-setup.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var parts = data.split("\x1f")
                    if (parts.length < 1) return
                    var summary  = (parts[0] || "").trim()
                    var body     = (parts[1] || "").replace(/<[^>]*>/g, "").trim()
                    var app      = (parts[2] || "").trim()
                    var iconPath = (parts[3] || "").trim()
                    var desktop  = (parts[4] || "").trim()
                    var url      = (parts[5] || "").trim()
                    if (summary === "" && body === "" && app === "") return

                    if (root.notifReady) {
                        root.notifSummary      = summary
                        root.notifBody         = body
                        root.notifAppName      = app
                        root.notifIconPath     = iconPath
                        root.notifDesktopEntry = desktop
                        root.notifUrl          = url
                        root.notifVisible  = true
                        if (!root.silenced)
                            root.islandState   = "notification"
                        notifDismissTimer.restart()
                    }

                    if (!root.historyCleared) {
                        var isDupe = false
                        for (var di = 0; di < notifHistory.count; di++) {
                            var ex = notifHistory.get(di)
                            if (ex.hApp === app && ex.hSummary === summary) { isDupe = true; break }
                        }
                        if (!isDupe) {
                            notifHistory.insert(0, { hApp: app, hSummary: summary, hBody: body, hIcon: iconPath, hTime: Qt.formatTime(new Date(), "hh:mm"), hDesktop: desktop, hUrl: url })
                            if (notifHistory.count > 50) notifHistory.remove(50, notifHistory.count - 50)
                            root.saveHistory()
                        }
                    }
                }
            }
        }

        property bool notifReady: false
        property bool historyCleared: true
        Timer {
            id: notifReadyTimer
            interval: 1000
            repeat: false
            running: true
            onTriggered: {
                root.notifReady = true
                root.historyCleared = false
            }
        }

        Process {
            id: historySaveProcess
            property string payload: ""
            command: ["bash", Qt.resolvedUrl("./scripts/notif-history-save.sh").toString().replace("file://", "")]
            environment: ({ "NOTIF_HISTORY_PAYLOAD": payload })
        }

        function saveHistory() {
            var lines = []
            for (var i = 0; i < notifHistory.count; i++) {
                var e = notifHistory.get(i)
                lines.push(JSON.stringify({
                    hApp: e.hApp||"", hSummary: e.hSummary||"", hBody: e.hBody||"",
                    hIcon: e.hIcon||"", hTime: e.hTime||"",
                    hDesktop: e.hDesktop||"", hUrl: e.hUrl||""
                }))
            }
            var payload = lines.join("\n")
            historySaveProcess.payload = payload
            historySaveProcess.running = true
        }

        Process {
            id: historyLoadProcess
            command: ["bash", Qt.resolvedUrl("./scripts/notif-history-load.sh").toString().replace("file://", "")]
            running: true
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    if (root.historyCleared) return
                    var line = data.trim()
                    if (line === "") return
                    try {
                        var e = JSON.parse(line)
                        if (e && (e.hApp || e.hSummary)) notifHistory.append(e)
                    } catch(err) {}
                }
            }
        }

        property bool   appLauncherOpen:  false
        property string appLauncherQuery: ""
        property var    appFavourites:    []

        function fuzzyScore(haystack, needle) {
            if (needle === "") return 1
            var h = haystack.toLowerCase()
            var n = needle.toLowerCase()
            var hi = 0, ni = 0, score = 0, consecutive = 0
            while (hi < h.length && ni < n.length) {
                if (h[hi] === n[ni]) {
                    score += 10 + consecutive * 5
                    if (hi === 0 || h[hi-1] === " " || h[hi-1] === "-") score += 15
                    consecutive++
                    ni++
                } else {
                    consecutive = 0
                }
                hi++
            }
            if (ni < n.length) return -1
            return score
        }

        function appLauncherFiltered() {
            var q = appLauncherQuery.trim()
            var results = []
            for (var i = 0; i < appLauncherModel.count; i++) {
                var app = appLauncherModel.get(i)
                var s = fuzzyScore(app.name, q)
                if (s >= 0) results.push({app: {name: app.name, exec: app.exec, desktopId: app.desktopId, icon: app.icon}, score: s})
            }
            results.sort(function(a, b) {
                var aFav = appFavourites.indexOf(a.app.desktopId) >= 0 ? 1 : 0
                var bFav = appFavourites.indexOf(b.app.desktopId) >= 0 ? 1 : 0
                if (aFav !== bFav) return bFav - aFav
                return b.score - a.score
            })
            return results.map(function(r) { return r.app })
        }

        function toggleFavourite(desktopId) {
            var favs = appFavourites.slice()
            var idx = favs.indexOf(desktopId)
            if (idx >= 0) favs.splice(idx, 1)
            else favs.unshift(desktopId)
            appFavourites = favs
            saveFavourites()
        }

        Process {
            id: appLauncherLoader
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/app-launcher.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var p = data.split("\x1f")
                    if (p.length < 3) return
                    appLauncherModel.append({ name: p[0], exec: p[1], desktopId: p[2], icon: p[3] || "" })
                }
            }
        }

        Process { id: appLaunchProc; running: false; command: [] }

        function launchApp(desktopId, exec) {
            appLaunchProc.command = [
                "bash",
                Qt.resolvedUrl("./scripts/app-launch.sh").toString().replace("file://", ""),
                desktopId, exec
            ]
            appLaunchProc.running = false
            appLaunchProc.running = true
            root.islandState = "default"
            root.appLauncherQuery = ""
        }

        readonly property string favsFile: configDir + "/favourites"

        Process {
            id: favsSaveProc
            running: false
            property string favsPayload: ""
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/favs-save.sh").toString().replace("file://", ""),
                root.configDir, root.favsFile
            ]
            environment: ({ "FAVS_PAYLOAD": favsPayload })
        }
        function saveFavourites() {
            favsSaveProc.favsPayload = appFavourites.join("\n")
            favsSaveProc.running = false
            favsSaveProc.running = true
        }

        Process {
            id: favsLoadProc
            running: true
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/favs-load.sh").toString().replace("file://", ""),
                root.favsFile
            ]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var id = data.trim()
                    if (id === "") return
                    var favs = root.appFavourites.slice()
                    if (favs.indexOf(id) < 0) favs.push(id)
                    root.appFavourites = favs
                }
            }
        }

        property bool   controlPanelOpen: false
        property bool   wifiEnabled:      true
        property bool   bluetoothEnabled: false
        property real   brightness:       0.5
        property real   volume:           0.8
        property string wifiStatus:       "No device"
        property string bluetoothStatus:  "Unavailable"
        property bool   soundAppsOpen:     false
        property bool   wifiNetworksOpen:  false
        property bool   colorWheelOpen:    false
        property string colorWheelTarget:  "pill"
        onIslandStateChanged: {
            if (islandState !== "settings")     colorWheelOpen    = false
            if (islandState !== "controlPanel") vpnLocationsOpen  = false
        }
        property bool silenced: false
        property string wifiConnectingTo: ""
        property string wifiConnectedSsid: ""
        ListModel { id: appVolumeModel }
        ListModel { id: wifiNetworkModel }
        ListModel { id: notifHistory }
        ListModel { id: appLauncherModel }
        ListModel { id: playtimeModel }

        // ── Screen Time ────────────────────────────────────────────────
        property bool   screenTimeOpen:        false
        property string screenTimeSort:        "session"  // "session" or "total"
        property var    steamNameCache:        ({})
        property string steamIconHome:         ""
        property var    steamIconCache:        ({})   // path → true, for files that exist

        // Resolve $HOME once so icon path building doesn't need shell
        Process {
            id: homeResolver
            running: true
            command: ["bash", "-c", "echo \"$HOME\""]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => { var h = data.trim(); if (h !== "") root.steamIconHome = h }
            }
            onExited: (exitCode, exitStatus) => {
                steamIconScanner.running = false
                steamIconScanner.running = true
            }
        }

        // Scan all Steam librarycache + games dirs and record which icon files exist.
        // Runs after homeResolver finishes (triggered from its onExited via steamIconScanner).
        Process {
            id: steamIconScanner
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/steam-icon-scan.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var p = data.trim()
                    if (p === "") return
                    var c = root.steamIconCache
                    c[p] = true
                    root.steamIconCache = c
                }
            }
            onExited: (exitCode, exitStatus) => {
                if (root.screenTimeOpen) root.refreshPlaytimeModel()
            }
        }

        Process {
            id: steamNameLoader
            running: true
            command: ["bash", Qt.resolvedUrl("./scripts/steam-names.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var p = data.trim().split("|")
                    if (p.length >= 2 && p[0] !== "") {
                        var cache = root.steamNameCache
                        cache[p[0]] = p.slice(1).join("|")
                        root.steamNameCache = cache
                    }
                }
            }
            // Once all manifests are read, re-populate the model so any
            // steam_app_NNNNNN entries that were already recorded get their
            // real names (fixes the race between startup tracking and cache load).
            onExited: (exitCode, exitStatus) => {
                if (root.screenTimeOpen) root.refreshPlaytimeModel()
            }
        }

        // System uptime
        property string systemUptimeStr:       "0s"
        property real   systemUptimeMs:        0

        // Total PC uptime ever (accumulated across boots, saved to disk)
        property real   totalPcUptimeMs:       0
        property string totalPcUptimeStr:      "0s"

        // System overview (CPU / RAM / GPU)
        property real   sysCpuPct:  0
        property real   sysRamPct:  0
        property real   sysGpuPct:  0

        Timer {
            interval: 2000; running: true; repeat: true
            onTriggered: { sysOverviewPoller.running = false; sysOverviewPoller.running = true }
        }

        Process {
            id: sysOverviewPoller
            running: true
            command: ["bash", Qt.resolvedUrl("./scripts/sys-overview.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var p = data.trim().split("|")
                    if (p.length < 3) return
                    var cpu = parseInt(p[0]); if (!isNaN(cpu)) root.sysCpuPct = Math.min(100, Math.max(0, cpu))
                    var ram = parseInt(p[1]); if (!isNaN(ram)) root.sysRamPct = Math.min(100, Math.max(0, ram))
                    var gpu = parseInt(p[2]); if (!isNaN(gpu)) root.sysGpuPct = Math.min(100, Math.max(0, gpu))
                }
            }
        }

        // Active window tracking
        property string activeWindowClass:     ""
        property real   activeWindowSince:     Date.now()

        // playtime data: { [appClass]: { totalMs: number, sessionMs: number } }  (runtime: ms)
        property var    playtimeData:          ({})

        // Combined save file: { uptime: { totalS }, apps: { [class]: { totalS } } }  (on disk: seconds)
        readonly property string screentimeFile: configDir + "/screentime.json"

        function fmtDuration(ms) {
            if (ms < 0) ms = 0
            var s   = Math.floor(ms / 1000)
            var m   = Math.floor(s / 60);   s = s % 60
            var h   = Math.floor(m / 60);   m = m % 60
            var d   = Math.floor(h / 24);   h = h % 24
            if (d > 0) return d + "d " + h + "h"
            if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m"
            if (m > 0) return m + "m " + (s < 10 ? "0" : "") + s + "s"
            return s + "s"
        }

        function recordWindowSwitch(newClass) {
    		var now = Date.now()
   		var prev = root.activeWindowClass
    		var normNew = newClass.toLowerCase()
    		if (prev !== "" && prev !== normNew) {
        		var elapsed = now - root.activeWindowSince
        		var d = root.playtimeData
        		if (!d[prev]) d[prev] = { totalMs: 0, sessionMs: 0 }
        		d[prev].totalMs   += elapsed
        		d[prev].sessionMs += elapsed
        		root.playtimeData = d
    		}
    		if (normNew === "steam_app_default") {
        		steamAppResolver.running = false
        		steamAppResolver.running = true
        		root.activeWindowSince = now
    		} else {
        		root.activeWindowClass = normNew
        		root.activeWindowSince = now
    		}
	}

        function flushActiveWindow() {
            var now = Date.now()
            var cls = root.activeWindowClass.toLowerCase()
            if (cls === "") return
            var elapsed = now - root.activeWindowSince
            var d = root.playtimeData
            if (!d[cls]) d[cls] = { totalMs: 0, sessionMs: 0 }
            d[cls].totalMs   += elapsed
            d[cls].sessionMs += elapsed
            root.playtimeData = d
            root.activeWindowSince = now
        }

        function refreshPlaytimeModel() {
            root.flushActiveWindow()
            playtimeModel.clear()
            var d = root.playtimeData
            var keys = Object.keys(d)
            keys.sort(function(a, b) {
                var ka = d[a] || { totalMs: 0, sessionMs: 0 }
                var kb = d[b] || { totalMs: 0, sessionMs: 0 }
                return root.screenTimeSort === "session"
                    ? kb.sessionMs - ka.sessionMs
                    : kb.totalMs   - ka.totalMs
            })
            for (var i = 0; i < keys.length; i++) {
                var k  = keys[i]
                var e  = d[k] || { totalMs: 0, sessionMs: 0 }
                var icon = ""
                var displayName = k
                var kl = k.toLowerCase()
                // Try to match: desktopId exact, name exact, desktopId last segment (org.app.Name → name)
                var kSegment = kl.indexOf(".") >= 0 ? kl.split(".").pop() : kl
                for (var j = 0; j < appLauncherModel.count; j++) {
                    var la = appLauncherModel.get(j)
                    var did = (la.desktopId || "").toLowerCase()
                    var nm  = (la.name      || "").toLowerCase()
                    var didSeg = did.indexOf(".") >= 0 ? did.split(".").pop() : did
                    if (did === kl || nm === kl || didSeg === kl || did === kSegment || didSeg === kSegment) {
                        icon = la.icon || ""
                        displayName = la.name || k
                        break
                    }
                }
                // Resolve steam_app_NNNNNN → real game name + icon from Steam cache
                var steamMatch = k.match(/^steam_app_(\d+)$/i)
                if (steamMatch) {
                    var appId = steamMatch[1]
                    if (displayName === k) {
                        var gameName = root.steamNameCache[appId]
                        if (gameName && gameName !== "") displayName = gameName
                    }
                    // Try Steam librarycache icon paths when no desktop icon was found
                    if (icon === "") {
                        var home = root.steamIconHome
                        var candidates = [
                            home + "/.local/share/Steam/appcache/librarycache/" + appId + "_icon.jpg",
                            home + "/.steam/steam/appcache/librarycache/"       + appId + "_icon.jpg",
                            home + "/.local/share/Steam/appcache/librarycache/" + appId + "_icon.png",
                            home + "/.steam/steam/appcache/librarycache/"       + appId + "_icon.png",
                            home + "/.local/share/Steam/steam/games/"           + appId + ".ico",
                            home + "/.steam/steam/steam/games/"                 + appId + ".ico",
                        ]
                        for (var ci = 0; ci < candidates.length; ci++) {
                            if (root.steamIconCache[candidates[ci]]) {
                                icon = candidates[ci]
                                break
                            }
                        }
                    }
                }
                playtimeModel.append({
                    appClass:    k,
                    displayName: displayName,
                    totalMs:     e.totalMs,
                    sessionMs:   e.sessionMs,
                    icon:        icon
                })
            }
        }

        // ── Combined screentime save / load ────────────────────────────
        Process {
            id: screentimeSaveProc
            running: false
            property string screentimePayload: ""
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/screentime-save.sh").toString().replace("file://", ""),
                root.configDir, root.screentimeFile
            ]
            environment: ({ "SCREENTIME_PAYLOAD": screentimePayload })
        }
        function saveScreentimeData() {
            root.flushActiveWindow()
            var d    = root.playtimeData
            var keys = Object.keys(d)
            var apps = {}
            for (var i = 0; i < keys.length; i++) {
                var k = keys[i]
                apps[k] = { totalS: Math.round(d[k].totalMs / 1000) }   // session resets each run; only save total
            }
            var payload = JSON.stringify({
                uptime: { totalS: Math.round((root.totalPcUptimeMs + root.systemUptimeMs) / 1000) },
                apps:   apps
            })
            screentimeSaveProc.screentimePayload = payload
            screentimeSaveProc.running = false
            screentimeSaveProc.running = true
        }

        Process {
            id: screentimeLoadProc
            running: false
            command: []
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var line = data.trim()
                    if (line === "" || line === "{}") return
                    try {
                        var obj  = JSON.parse(line)

                        // Restore uptime (subtract current boot so we don't double-count)
                        // Accept totalS (new) or totalMs (old files) for migration
                        var uptimeObj = obj.uptime || {}
                        var savedUptimeMs = uptimeObj.totalS !== undefined
                            ? uptimeObj.totalS * 1000
                            : (uptimeObj.totalMs || 0)
                        root.totalPcUptimeMs = Math.max(0, savedUptimeMs - root.systemUptimeMs)

                        // Restore app playtime (normalize keys to lowercase, merging duplicates)
                        // Accept totalS (new) or totalMs (old files) for migration
                        var appsObj = obj.apps || {}
                        var d = root.playtimeData
                        var keys = Object.keys(appsObj)
                        for (var i = 0; i < keys.length; i++) {
                            var k = keys[i].toLowerCase()
                            if (!d[k]) d[k] = { totalMs: 0, sessionMs: 0 }
                            var entry = appsObj[keys[i]]
                            var ms = entry.totalS !== undefined ? entry.totalS * 1000 : (entry.totalMs || 0)
                            d[k].totalMs += ms
                        }
                        root.playtimeData = d
                    } catch(e) {}
                }
            }
        }
        function loadPlaytimeData() {
            // Also migrate old separate files if the combined file doesn't exist yet
            screentimeLoadProc.command = [
                "bash",
                Qt.resolvedUrl("./scripts/screentime-load.sh").toString().replace("file://", ""),
                root.screentimeFile, root.configDir
            ]
            screentimeLoadProc.running = false
            screentimeLoadProc.running = true
        }

        // Poll Hyprland active window every 2 s
        Process {
            id: activeWindowPoller
            running: true
            command: ["bash", Qt.resolvedUrl("./scripts/active-window.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var cls = data.trim()
                    if (cls !== root.activeWindowClass)
                        root.recordWindowSwitch(cls)
                }
            }
        }

	Process {
    		id: steamAppResolver
    		running: false
    		command: ["bash", "-c", "hyprctl activewindow -j 2>/dev/null | python3 -c \"\nimport json,sys\nd=json.load(sys.stdin)\ntitle=(d.get('title') or '').strip()\ncls=(d.get('class') or '').strip().lower()\nprint(title if cls=='steam_app_default' else cls)\n\""]
    		stdout: SplitParser {
        		splitMarker: "\n"
        		onRead: data => {
            		var resolved = data.trim().toLowerCase()
            		if (resolved === "" || resolved === "steam_app_default") {
                		root.activeWindowClass = "steam_app_default"
            		} else {
                		root.activeWindowClass = resolved
            		}
            		root.activeWindowSince = Date.now()
        		}
    		}
	}

        Timer {
            interval: 60000; running: true; repeat: true
            onTriggered: root.saveScreentimeData()
        }

        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: {
                systemUptimePoller.running = false
                systemUptimePoller.running = true
            }
        }

        Process {
            id: systemUptimePoller
            running: true
            command: ["bash", Qt.resolvedUrl("./scripts/uptime-poll.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var ms = parseInt(data.trim())
                    if (!isNaN(ms)) {
                        root.systemUptimeMs  = ms
                        root.systemUptimeStr = root.fmtDuration(ms)
                        root.totalPcUptimeStr = root.fmtDuration(root.totalPcUptimeMs + ms)
                    }
                }
            }
        }

        // Pre-populate app icons for screentime
        Component.onCompleted: {
            appLauncherLoader.running = true
        }

        // Load saved screentime once at startup, after uptime has been read
        Timer {
            id: screentimeStartupLoader
            interval: 1500
            running: true
            repeat: false
            onTriggered: root.loadPlaytimeData()
        }

	Timer {
    		id: cavaFrame
    		interval: 16
    		repeat: false
    		onTriggered: {
        		root.cavaBars = root.cavaPending
        		root.cavaUpdatePending = false
    		}
	}

        Process {
            command: ["bash", Qt.resolvedUrl("./scripts/cava.sh").toString().replace("file://", "")]
            running: true
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var parts = data.trim().split(";")
		    var nums = parts.map(s => { var n = parseInt(s); return isNaN(n) ? 0 : n })
		    if (nums.length > 0) {
    			root.cavaPending = nums
    			if (!root.cavaUpdatePending) {
        			root.cavaUpdatePending = true
        			cavaFrame.start()
    			}
		}
                }
            }
        }

        property string musicDir: ""

        Process {
            id: musicDirFinder
            running: true
            command: ["bash", Qt.resolvedUrl("./scripts/music-dir.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var d = data.trim()
                    if (d !== "") root.musicDir = d
                }
            }
        }

        Process {
            command: ["bash", "-c", `
                while true; do
                    INFO=$(mpc --format '%title%\t%artist%\t%file%' current 2>/dev/null)
                    STATUS=$(mpc status 2>/dev/null | grep -oP '\\[(playing|paused)\\]' | tr -d '[]')
                    echo "$INFO\t$STATUS"
                    mpc current --wait > /dev/null 2>&1
                done
            `]
            running: true
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var parts = data.split("\t")
                    root.songTitle  = parts[0] || ""
                    root.songArtist = parts[1] || ""
                    root.isPlaying  = (parts[3] || "").trim() === "playing"
                    var file = parts[2] || ""
                    if (file !== "") artFetcher.startFetch(file)
                    else root.albumArt = ""
                }
            }
        }

        Process {
            id: artFetcher
            property string _file: ""
            function startFetch(file) {
                if (file === _file && root.albumArt !== "") return
                _file = file

                artFetcher.command = ["bash", "-c",
                    "FILE=\"$1\"; MUSIC_DIR=\"$2\"; OUT=/tmp/island_cover.jpg; " +
                    "[ -z \"$MUSIC_DIR\" ] && MUSIC_DIR=\"$HOME/Music\"; " +
                    "FULL=\"$MUSIC_DIR/$FILE\"; " +
                    "ffmpeg -loglevel quiet -y -i \"$FULL\" -map 0:v:0 -vframes 1 \"$OUT\" 2>/dev/null " +
                    "  && [ -s \"$OUT\" ] && echo \"file://$OUT\" && exit 0; " +
                    "DIR=$(dirname \"$FULL\"); " +
                    "COVER=$(find \"$DIR\" -maxdepth 1 \\( -iname 'cover.*' -o -iname 'folder.*' -o -iname 'front.*' -o -iname 'artwork.*' \\) 2>/dev/null | head -1); " +
                    "[ -n \"$COVER\" ] && cp \"$COVER\" \"$OUT\" && echo \"file://$OUT\" && exit 0; " +
                    "echo ''",
                    "_", file, root.musicDir
                ]
                artFetcher.running = false
                artFetcher.running = true
            }
            running: false
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var path = data.trim()
                    root.albumArt = path ? (path + "?" + Date.now()) : ""
                }
            }
        }

        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: statusPoller.running = true
        }
        Process {
            id: statusPoller
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/music-status.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var s = data.trim()
                    if (s !== "") root.isPlaying = (s === "playing")
                    statusPoller.running = false
                }
            }
        }



        Process { id: mpcPrev;   running: false; command: ["mpc", "prev"] }
        Process { id: mpcToggle; running: false; command: ["mpc", "toggle"] }
        Process { id: mpcNext;   running: false; command: ["mpc", "next"] }

        Process {
            id: volumePoller
            running: true
            command: ["bash", Qt.resolvedUrl("./scripts/volume-get.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var v = parseFloat(data.trim())
                    if (!isNaN(v)) root.volume = Math.min(1.0, v)
                }
            }
        }

        Process {
            id: appVolumePoller
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/app-volumes.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var p = data.trim().split("|")
                    if (p.length < 3) return
                    var id = parseInt(p[0])
                    var vol = parseFloat(p[p.length - 1])
                    if (isNaN(id) || isNaN(vol)) return
                    var name = p.slice(1, p.length - 1).join("|").trim()
                    if (!name) name = "Audio stream " + id
                    var found = -1
                    for (var i = 0; i < appVolumeModel.count; i++) {
                        if (appVolumeModel.get(i).nodeId === id) { found = i; break }
                    }
                    var v = Math.max(0, Math.min(1, vol))
                    if (found >= 0) {
                        appVolumeModel.setProperty(found, "appName", name)
                        appVolumeModel.setProperty(found, "appVolume", v)
                    } else {
                        appVolumeModel.append({nodeId: id, appName: name, appVolume: v})
                    }
                }
            }
        }

        Process {
            id: appVolumeSetter
            running: false
            property int targetNode: 0
            property real targetVol: 0
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/app-volume-set.sh").toString().replace("file://", ""),
                targetNode.toString(), Math.round(targetVol * 100).toString()
            ]
        }

        Timer {
            interval: 2000; running: true; repeat: true
            onTriggered: {
                volumePoller.running = false
                volumePoller.running = true
                brightnessPoller.running = false
                brightnessPoller.running = true
                obsStatePoller.running = false
                obsStatePoller.running = true
            }
        }
        Process {
            id: obsStatePoller
            running: true
            command: ["bash", Qt.resolvedUrl("./scripts/obs-status.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var s = data.trim()
                    if (s === "recording" || s === "stopped")
                        root.obsRecording = s === "recording"
                }
            }
        }
        Process {
            id: brightnessPoller
            running: true
            command: ["bash", Qt.resolvedUrl("./scripts/brightness-get.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var v = parseFloat(data.trim())
                    if (!isNaN(v)) root.brightness = Math.max(0.0, Math.min(1.0, v))
                }
            }
        }

        Process {
            id: volumeSetter
            running: false
            property real targetVol: 0
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/volume-set.sh").toString().replace("file://", ""),
                Math.round(targetVol * 100).toString()
            ]
        }

        Process {
            id: brightnessSetter
            running: false
            property real targetBright: 0
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/brightness-set.sh").toString().replace("file://", ""),
                Math.round(targetBright * 100).toString()
            ]
        }

        Process {
            id: wifiToggleProc
            running: false
            property bool enabling: true
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/wifi-toggle.sh").toString().replace("file://", ""),
                enabling ? "enable" : "disable"
            ]
        }

        Process {
            id: btToggleProc
            running: false
            property bool enabling: true
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/bt-toggle.sh").toString().replace("file://", ""),
                enabling ? "enable" : "disable"
            ]
        }

        Process {
            id: wifiScanProc
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/wifi-scan.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var parts = data.trim().split("\x1f")
                    if (parts.length < 5) return
                    var ssid      = parts[0]
                    var service   = parts[1]
                    var strength  = parseInt(parts[2]) || 0
                    var security  = parts[3]
                    var connected = parts[4] === "1"

                    for (var i = 0; i < wifiNetworkModel.count; i++) {
                        if (wifiNetworkModel.get(i).service === service) {
                            wifiNetworkModel.setProperty(i, "ssid",      ssid)
                            wifiNetworkModel.setProperty(i, "strength",  strength)
                            wifiNetworkModel.setProperty(i, "security",  security)
                            wifiNetworkModel.setProperty(i, "connected", connected)
                            return
                        }
                    }
                    wifiNetworkModel.append({ ssid: ssid, service: service, strength: strength, security: security, connected: connected })
                    if (connected) root.wifiConnectedSsid = ssid
                }
            }
        }

        Process {
            id: wifiConnectProc
            running: false
            property string targetService: ""
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/wifi-connect.sh").toString().replace("file://", ""),
                targetService
            ]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var out = data.trim().toLowerCase()
                    if (out.indexOf("connected") >= 0 || out.indexOf("already") >= 0) {
                        root.wifiConnectedSsid = root.wifiConnectingTo

                        wifiNetworkModel.clear()
                        wifiScanProc.running = false
                        wifiScanProc.running = true
                    }
                    root.wifiConnectingTo = ""
                }
            }
        }

        Process {
            id: wifiDisconnectProc
            running: false
            property string targetService: ""
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/wifi-disconnect.sh").toString().replace("file://", ""),
                targetService
            ]
        }

        Process {
            id: screenshotProc
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/screenshot.sh").toString().replace("file://", "")]
        }

        Timer {
            id: screenshotDelayTimer
            interval: 300
            repeat: false
            onTriggered: {
                screenshotProc.running = false
                screenshotProc.running = true
            }
        }

        property bool obsRecording: false
        Process {
            id: obsStartProc
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/obs-start.sh").toString().replace("file://", "")]
        }
        Process {
            id: obsStopProc
            running: false
            command: ["obs-cmd", "-w", "obsws://localhost:4455", "recording", "stop"]
        }

        property bool   vpnConnected:     false
        property string vpnLocation:      ""
        property bool   vpnLocationsOpen: false
        property bool   vpnLongDidFire:   false
        ListModel { id: vpnLocationModel }
        Process {
            id: vpnStatusPoller
            running: true
            command: ["bash", Qt.resolvedUrl("./scripts/vpn-watch.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var s = data.trim()
                    root.vpnConnected = s.startsWith("connected")
                    root.vpnLocation  = s.startsWith("connected · ") ? s.slice("connected · ".length) : ""
                }
            }
        }
        Process {
            id: vpnConnectProc
            running: false
            command: ["mullvad", "connect"]
        }
        Process {
            id: vpnDisconnectProc
            running: false
            command: ["mullvad", "disconnect"]
        }

        Process {
            id: vpnLocationLoader
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/vpn-locations.sh").toString().replace("file://", "")]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var parts = data.trim().split("|")
                    if (parts.length < 4) return
                    vpnLocationModel.append({
                        locCountry:     parts[0],
                        locCountryCode: parts[1],
                        locCity:        parts[2],
                        locCityCode:    parts[3]
                    })
                }
            }
        }

        Process {
            id: vpnLocationSetProc
            running: false
            property string countryCode: ""
            property string cityCode:    ""
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/vpn-location-set.sh").toString().replace("file://", ""),
                countryCode, cityCode
            ]
        }

        Process {
            id: sleepProc
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/sleep.sh").toString().replace("file://", "")]
        }
        Process {
            id: rebootProc
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/reboot.sh").toString().replace("file://", "")]
        }
        Process {
            id: shutdownProc
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/shutdown.sh").toString().replace("file://", "")]
        }
        Process {
            id: lockProc
            running: false
            command: ["bash", Qt.resolvedUrl("./scripts/lock.sh").toString().replace("file://", "")]
        }

        property var    notchLayout:    [["Date", "Cava", "Time"], ["Workspaces"], ["Timer"]]
        property var    _notchParsed:   []
        property string notchLayoutRaw: "notch1 = [Date, Cava, Time]\nnotch2 = [Workspaces]\nnotch3 = [Timer]"

        readonly property string configDir:  "/home/daveee/.config/quickshell/dynamic-island"
        readonly property string configFile: configDir + "/config"


        Process {
            id: configInitProc
            running: true
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/config-init.sh").toString().replace("file://", ""),
                root.configDir, root.configFile
            ]
            property string _raw: ""
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var line = data.trim()
                    if (line === "" || line[0] === "#") return
                    var ma = line.match(/^\w+\s*=\s*\[([^\]]*)\]/)
                    if (ma) {
                        configInitProc._raw += data + "\n"
                        var widgets = ma[1].split(",")
                            .map(function(s) { return s.trim() })
                            .filter(function(s) { return s !== "" })
                        if (widgets.length > 0) {
                            var copy = root._notchParsed.slice()
                            copy.push(widgets)
                            root._notchParsed = copy
                        }
                        return
                    }
                    var mf = line.match(/^(fontFamily)\s*=\s*(.*)/)
                    if (mf) { root.fontFamily = mf[2].trim(); return }
                    var ms = line.match(/^(\w+)\s*=\s*(\S+)/)
                    if (!ms) return
                    var key = ms[1], val = ms[2]
                    if      (key === "clickLeft")   root.clickLeft   = val
                    else if (key === "clickRight")  root.clickRight  = val
                    else if (key === "clickMiddle") root.clickMiddle = val
                    else if (key === "dragDown")      root.dragDown      = val
                    else if (key === "dragDownRight") root.dragDownRight = val
                    else if (key === "pillColor")   root.pillColor   = val
                    else if (key === "pillOpacity") root.pillOpacity = parseFloat(val)
                    else if (key === "accentColor") root.accentColor = val
                    else if (key === "textColor")   root.textColor   = val
                    else if (key === "fontFamily")  root.fontFamily  = val
                }
            }
            onRunningChanged: {
                if (!running) {
                    var raw = _raw
                    _raw = ""
                    root.notchLayoutRaw = raw.replace(/\n$/, "")
                    if (root._notchParsed.length > 0) root.notchLayout = root._notchParsed.slice()
                    root._notchParsed = []
                }
            }
        }

        FileView {
            id: configWatcher
            path:    root.configFile
            watchChanges: true
            onFileChanged: {
                configReloadProc._raw = ""
                configReloadProc._notchParsed = []
                configReloadProc.running = false
                configReloadProc.running = true
            }
        }

        Process {
            id: configReloadProc
            running: false
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/config-read.sh").toString().replace("file://", ""),
                root.configFile
            ]
            property string _raw: ""
            property var _notchParsed: []
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var line = data.trim()
                    if (line === "" || line[0] === "#") return
                    var ma = line.match(/^\w+\s*=\s*\[([^\]]*)\]/)
                    if (ma) {
                        configReloadProc._raw += data + "\n"
                        var widgets = ma[1].split(",")
                            .map(function(s) { return s.trim() })
                            .filter(function(s) { return s !== "" })
                        if (widgets.length > 0) {
                            var copy = configReloadProc._notchParsed.slice()
                            copy.push(widgets)
                            configReloadProc._notchParsed = copy
                        }
                        return
                    }
                    var mf = line.match(/^(fontFamily)\s*=\s*(.*)/)
                    if (mf) { root.fontFamily = mf[2].trim(); return }
                    var ms = line.match(/^(\w+)\s*=\s*(\S+)/)
                    if (!ms) return
                    var key = ms[1], val = ms[2]
                    if      (key === "clickLeft")   root.clickLeft   = val
                    else if (key === "clickRight")  root.clickRight  = val
                    else if (key === "clickMiddle") root.clickMiddle = val
                    else if (key === "dragDown")      root.dragDown      = val
                    else if (key === "dragDownRight") root.dragDownRight = val
                    else if (key === "pillColor")   root.pillColor   = val
                    else if (key === "pillOpacity") root.pillOpacity = parseFloat(val)
                    else if (key === "accentColor") root.accentColor = val
                    else if (key === "textColor")   root.textColor   = val
                    else if (key === "fontFamily")  root.fontFamily  = val
                }
            }
            onRunningChanged: {
                if (!running) {
                    var raw = _raw
                    _raw = ""
                    root.notchLayoutRaw = raw.replace(/\n$/, "")
                    if (_notchParsed.length > 0) root.notchLayout = _notchParsed.slice()
                    _notchParsed = []
                }
            }
        }


        Process {
            id: configSaveProc
            running: false
            property string pendingContent: ""
            command: [
                "bash",
                Qt.resolvedUrl("./scripts/config-save.sh").toString().replace("file://", ""),
                root.configFile
            ]
            environment: ({ "_ISLAND_CFG": pendingContent })
        }

        function saveNotchLayout(rawText) {
            root.notchLayoutRaw = rawText
            root.saveConfig()
        }

        function saveConfig() {
            var content =
                "clickLeft   = " + root.clickLeft   + "\n" +
                "clickRight  = " + root.clickRight  + "\n" +
                "clickMiddle = " + root.clickMiddle + "\n" +
                "dragDown      = " + root.dragDown      + "\n" +
                "dragDownRight = " + root.dragDownRight + "\n" +
                "pillColor   = " + root.pillColor   + "\n" +
                "pillOpacity = " + root.pillOpacity + "\n" +
                "accentColor = " + root.accentColor + "\n" +
                "textColor   = " + root.textColor   + "\n" +
                "fontFamily  = " + root.fontFamily  + "\n" +
                "\n" +
                root.notchLayoutRaw + "\n"
            configSaveProc.pendingContent = content
            configSaveProc.running = false
            configSaveProc.running = true
        }


        function drawBar(ctx, x, y, w, h, r) {
            r = Math.min(r, w / 2, h / 2)
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.lineTo(x + w - r, y)
            ctx.arcTo(x + w, y,     x + w, y + r, r)
            ctx.lineTo(x + w, y + h - r)
            ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
            ctx.lineTo(x + r, y + h)
            ctx.arcTo(x,     y + h, x,     y + h - r, r)
            ctx.lineTo(x, y + r)
            ctx.arcTo(x, y, x + r, y, r)
            ctx.closePath()
            ctx.fill()
        }

        PanelWindow {
            visible: root.islandVisible
            anchors.top:   true
            anchors.left:  true
            anchors.right: true
            implicitHeight: Math.round(44 * root.uiScale)
            color: "transparent"
            exclusiveZone: implicitHeight
        }

        PanelWindow {
            visible: root.islandVisible
            anchors.top:   true
            anchors.left:  true
            anchors.right: true
            implicitHeight: Math.round(530 * root.uiScale)
            color: "transparent"
            exclusiveZone: -1
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.islandState === "appLauncher" || root.islandState === "screenTime" || root.islandState === "settings") ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            mask: Region {
                x:      root.wifiNetworksOpen ? pillWrapper.x - 196 - 8 : pillWrapper.x
                y:      0
                width:  (root.soundAppsOpen       ? pillWrapper.width + 196 + 8 : pillWrapper.width)
                      + (root.wifiNetworksOpen    ? 196 + 8                     : 0)
                      + (root.vpnLocationsOpen && root.islandState === "controlPanel" ? 196 + 8 : 0)
                      + (root.colorWheelOpen && root.islandState === "settings" ? 240 + 8 : 0)
                height: pillWrapper.height + ((root.islandState === "appLauncher" || root.islandState === "screenTime" || root.islandState === "settings") ? 30 : 0)
            }

            Item {
                id: pillWrapper
                anchors.top: parent.top
                x: (parent.width - width) / 2

                property real defaultContentWidth: Math.round(260 * root.uiScale)

                property real availableNotchWidth: Math.max(210, parent.width - 32)
                property real musicContentWidth: Math.min(
                    availableNotchWidth,
                    Math.max(
                        300,
                        78
                        + Math.max(songTitleText.contentWidth, songArtistText.contentWidth)
                        + 94
                        + 28
                    )
                )

                width: root.islandState === "default" ? Math.min(defaultContentWidth, availableNotchWidth) :
                       root.islandState === "music" ? musicContentWidth :
                       root.islandState === "notification" ? Math.min(340, availableNotchWidth) :
                       root.islandState === "notifHistory" ? Math.min(380, availableNotchWidth) :
                       root.islandState === "appLauncher" ? Math.min(440, availableNotchWidth) :
                       root.islandState === "screenTime" ? Math.min(440, availableNotchWidth) :
                       root.islandState === "settings" ? Math.min(440, availableNotchWidth) :
                       Math.min(410, availableNotchWidth)

                Behavior on width {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }

                property bool silenceHandleOpen: false
                property real controlPanelHeight: 16 + 52
                    + 10 + 52
                    + 10 + 52
                    + 10 + 52
                    + 10 + 52
                    + 10 + 14
                    + (silenceHandleOpen ? 8 + 52 + 8 + 52 : 0)

                property real notifHistoryHeight: Math.min(420, 52 + Math.max(1, notifHistory.count) * 68)
                property real appLauncherHeight: 500
                property real screenTimeHeight: 480
                property real settingsHeight: 540
                height: root.islandState === "default" ? Math.round(44 * root.uiScale) :
                        root.islandState === "music" ? 90 :
                        root.islandState === "notification" ? 72 :
                        root.islandState === "notifHistory" ? notifHistoryHeight :
                        root.islandState === "appLauncher" ? appLauncherHeight :
                        root.islandState === "screenTime" ? screenTimeHeight :
                        root.islandState === "settings" ? settingsHeight :
                        controlPanelHeight

                Behavior on width {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on height {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }

            Canvas {
                id: pillCanvas
                anchors.fill: parent
                z: 1

                readonly property real br: root.islandState === "appLauncher" ? 22 : 22
                property color fillColor: root.pillBg()

                onWidthChanged:  requestPaint()
                onHeightChanged: requestPaint()
                onFillColorChanged: requestPaint()

                property bool roundTop: false
                onRoundTopChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = pillCanvas.fillColor

                    var w = width, h = height
                    var br = pillCanvas.br
                    var tr = 0

                    ctx.beginPath()

                    ctx.moveTo(0, 0)
                    ctx.lineTo(w, 0)

                    ctx.lineTo(w, h - br)
                    ctx.arcTo(w, h, w - br, h, br)

                    ctx.lineTo(br, h)
                    ctx.arcTo(0, h, 0, h - br, br)

                    ctx.lineTo(0, 0)
                    ctx.closePath()
                    ctx.fill()
                }
            }

            Item {
                id: pill
                anchors.fill: parent
                z: 2

                Item {
                    anchors.fill: parent
                    clip: true
                    z: 1

                    Item {
                        id: defaultView
                        anchors.fill: parent
                        opacity: root.islandState === "default" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 100 } }

                        property int page: 0
                        readonly property int pageCount: root.notchLayout.length

                        Item {
                            id: timerPage

                            visible: false
                            width:  defaultView.width
                            height: defaultView.height

                            property int  preset:   0
                            property int  elapsed:  0
                            property bool running:  false
                            property bool finished: false

                            readonly property bool  isTimer:   preset > 0
                            readonly property int   remaining: Math.max(0, preset - elapsed)
                            readonly property color orange:    "#FF8C42"
                            readonly property color orangeDim: Qt.rgba(1, 0.55, 0.26, 0.18)

                            Timer {
                                id: tick
                                interval: 10; repeat: true; running: timerPage.running
                                onTriggered: {
                                    timerPage.elapsed += 10
                                    if (timerPage.isTimer && timerPage.elapsed >= timerPage.preset) {
                                        timerPage.elapsed  = timerPage.preset
                                        timerPage.running  = false
                                        timerPage.finished = true
                                    }
                                }
                            }
                            SequentialAnimation {
                                running: timerPage.finished; loops: Animation.Infinite
                                PropertyAnimation { target: timeDisplay; property: "opacity"; to: 0.2; duration: 350 }
                                PropertyAnimation { target: timeDisplay; property: "opacity"; to: 1.0; duration: 350 }
                            }
                            function fmtCountdown(ms) {
                                var sec = Math.floor(ms / 1000), min = Math.floor(sec / 60)
                                sec = sec % 60
                                return (min < 10 ? "0" : "") + min + ":" + (sec < 10 ? "0" : "") + sec
                            }
                            function fmtStopwatch(ms) {
                                var cs = Math.floor(ms / 10) % 100, sec = Math.floor(ms / 1000) % 60, min = Math.floor(ms / 60000)
                                return (min<10?"0":"")+min+":"+(sec<10?"0":"")+sec+"."+(cs<10?"0":"")+cs
                            }
                            Process {
                                id: timerNotify; running: false
                                command: ["notify-send", "-u", "critical", "-t", "6000", "-i", "alarm-clock", "Timer done", "Your countdown has finished."]
                            }
                            Process {
                                id: timerBeep; running: false
                                command: ["bash", "-c",
                                    "for i in 1 2 3; do " +
                                    "  paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || " +
                                    "  paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null || " +
                                    "  paplay /usr/share/sounds/ubuntu/notifications/Xylo.ogg 2>/dev/null || " +
                                    "  ( python3 -c \"" +
                                    "import struct,wave,math,tempfile,os;" +
                                    "f=tempfile.NamedTemporaryFile(suffix='.wav',delete=False);" +
                                    "sr=44100;dur=0.18;freq=880;" +
                                    "n=int(sr*dur);" +
                                    "data=bytes([int(127+127*math.sin(2*math.pi*freq*i/sr)*(1-i/n)) for i in range(n)]);" +
                                    "w=wave.open(f.name,'wb');w.setnchannels(1);w.setsampwidth(1);w.setframerate(sr);w.writeframes(data);w.close();" +
                                    "print(f.name)" +
                                    "\" | xargs paplay ) 2>/dev/null; " +
                                    "  sleep 0.22; " +
                                    "done"
                                ]
                            }
                            onFinishedChanged: {
                                if (finished) { timerNotify.running = true; timerBeep.running = false; timerBeep.running = true }
                            }
                            RowLayout {
                                anchors.centerIn: parent; spacing: 6
                                Rectangle {
                                    width: 20; height: 20; radius: 10
                                    color: timerPage.isTimer ? timerPage.orangeDim : root.tc(0.08)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text { anchors.centerIn: parent; text: "−"; color: timerPage.isTimer ? timerPage.orange : root.tc(0.4); font.pixelSize: 14; font.family: root.fontFamily; font.weight: Font.Medium; Behavior on color { ColorAnimation { duration: 150 } } }
                                    MouseArea { anchors.fill: parent; onClicked: { if (timerPage.running) return; timerPage.finished = false; timerPage.elapsed = 0; timerPage.preset = Math.max(0, timerPage.preset - 5000) } }
                                }
                                Rectangle {
                                    width: 20; height: 20; radius: 10; color: root.tc(0.08)
                                    Text { anchors.centerIn: parent; text: "↺"; color: root.tc(0.45); font.pixelSize: 12; font.family: root.fontFamily }
                                    MouseArea { anchors.fill: parent; onClicked: { timerPage.running = false; timerPage.elapsed = 0; timerPage.preset = 0; timerPage.finished = false; timeDisplay.opacity = 1 } }
                                }
                                Text {
                                    id: timeDisplay
                                    text: timerPage.isTimer ? timerPage.fmtCountdown(timerPage.remaining) : timerPage.fmtStopwatch(timerPage.elapsed)
                                    color: (timerPage.finished || timerPage.isTimer) ? timerPage.orange : root.textColor
                                    font.pixelSize: 14; font.weight: Font.SemiBold; font.letterSpacing: -0.3; font.family: "monospace"
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                Rectangle {
                                    width: 20; height: 20; radius: 10
                                    color: timerPage.isTimer ? timerPage.orangeDim : root.tc(0.1)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text { anchors.centerIn: parent; text: timerPage.running ? "⏸" : "▶"; color: timerPage.isTimer ? timerPage.orange : root.tc(0.75); font.pixelSize: 10; font.family: root.fontFamily; Behavior on color { ColorAnimation { duration: 150 } } }
                                    MouseArea { anchors.fill: parent; onClicked: { if (timerPage.finished) { timerPage.finished = false; timerPage.elapsed = 0; timeDisplay.opacity = 1 } if (!timerPage.finished) timerPage.running = !timerPage.running } }
                                }
                                Rectangle {
                                    width: 20; height: 20; radius: 10; color: timerPage.orangeDim
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text { anchors.centerIn: parent; text: "+"; color: timerPage.orange; font.pixelSize: 14; font.family: root.fontFamily; font.weight: Font.Medium }
                                    MouseArea { anchors.fill: parent; onClicked: { if (timerPage.running) return; timerPage.finished = false; timerPage.elapsed = 0; timerPage.preset += 5000 } }
                                }
                            }
                        }

                        Item {
                            id: pageStrip
                            width:  parent.width * defaultView.pageCount
                            height: parent.height
                            x:     -defaultView.page * defaultView.width
                            Behavior on x { SmoothedAnimation { duration: 260; easing.type: Easing.OutCubic } }

                            Repeater {
                                model: root.notchLayout

                                Item {
                                    required property var  modelData
                                    required property int  index
                                    x:      index * defaultView.width
                                    width:  defaultView.width
                                    height: parent.height

                                    // Page-level helpers so per-widget items can see the full widget list.
                                    readonly property var  pageWidgets:      modelData
                                    readonly property bool leftEdgeIsCava:   pageWidgets.length > 0 && pageWidgets[0] === "Cava"
                                    readonly property bool rightEdgeIsCava:  pageWidgets.length > 0 && pageWidgets[pageWidgets.length - 1] === "Cava"

                                    RowLayout {
                                        id: notchRowLayout
                                        anchors.fill:           parent
                                        anchors.leftMargin:     14
                                        anchors.rightMargin:    14
                                        anchors.topMargin:      0
                                        anchors.bottomMargin:   0
                                        spacing: 8

                                        Repeater {
                                            model: modelData

                                            Item {
                                                required property string modelData
                                                required property int    index
                                                Layout.fillWidth:  true
                                                Layout.fillHeight: true

                                                readonly property var  pageWidgets: parent.parent.pageWidgets || []
                                                readonly property bool isCava:      modelData === "Cava"

                                                Layout.leftMargin:  0
                                                Layout.rightMargin: 0

                                                Text {
                                                    visible: parent.modelData === "Date"
                                                    anchors.centerIn: parent
                                                    text:  root.currentDate
                                                    color: root.tc(0.55)
                                                    font.pixelSize: 11; font.family: root.fontFamily
                                                    font.weight:    Font.Medium
                                                }

                                                Text {
                                                    visible: parent.modelData === "Time"
                                                    anchors.centerIn: parent
                                                    text:  root.currentTime
                                                    color: root.textColor
                                                    font.pixelSize:     20; font.family: root.fontFamily
                                                    font.weight:        Font.SemiBold
                                                    font.letterSpacing: -0.5
                                                }

                                                Canvas {
                                                    visible: parent.modelData === "Cava"
                                                    anchors.fill: parent
                                                    readonly property real maxBarH: 26
                                                    property var bars: root.cavaBars

                                                    onBarsChanged: requestPaint()
                                                    onWidthChanged: requestPaint()
                                                    onHeightChanged: requestPaint()
                                                    onPaint: {
                                                        var ctx = getContext("2d")
                                                        ctx.clearRect(0, 0, width, height)
                                                        var n  = 10
                                                        var sp = 2
                                                        var bw = (width - sp * (n - 1)) / n
                                                        for (var i = 0; i < n; i++) {
                                                            var v = bars[i] || 0
                                                            var h = Math.max(3, (v / 9) * maxBarH)
                                                            var x = i * (bw + sp)
                                                            var y = (height - h) / 2
                                                            ctx.fillStyle = root.tc(0.85)
                                                            root.drawBar(ctx, x, y, bw, h, Math.min(3, bw / 2, h / 2))
                                                        }
                                                    }
                                                }

                                                // ── System Overview widget ──────────────────
                                                // CPU: big icon (left) | % label above bar (right half)
                                                // RAM: % label above bar (left half) | big icon (right)  ← mirrored
                                                // All sizes multiplied by pillWrapper.uiScale so the widget
                                                // looks identical relative to screen height on 1080p / 1440p / 4K.
                                                Item {
                                                    visible: parent.modelData === "SysOverview"
                                                    anchors.fill: parent

                                                    // Convenience alias so children don't need to traverse far
                                                    readonly property real sc: root.uiScale

                                                    // ── CPU side (icon left, bar+label right) ──
                                                    Item {
                                                        id: cpuSide
                                                        anchors.left:   parent.left
                                                        anchors.top:    parent.top
                                                        anchors.bottom: parent.bottom
                                                        anchors.right:  parent.horizontalCenter
                                                        anchors.rightMargin: Math.round(3 * parent.sc)

                                                        // Big CPU icon, vertically centred on left edge
                                                        Text {
                                                            id: cpuIcon
                                                            anchors.left:           parent.left
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text:  "󰍛"
                                                            color: Qt.color(root.arcColor(root.sysCpuPct))
                                                            font.pixelSize: Math.round(18 * cpuSide.parent.sc)
                                                            font.family:    root.fontFamily
                                                            Behavior on color { ColorAnimation { duration: 300 } }
                                                        }

                                                        // Bar + label stacked, to the right of the icon
                                                        Item {
                                                            anchors.left:           cpuIcon.right
                                                            anchors.leftMargin:     Math.round(4 * cpuSide.parent.sc)
                                                            anchors.right:          parent.right
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            height: Math.round(20 * cpuSide.parent.sc)

                                                            // % number above bar
                                                            Text {
                                                                id: cpuLabel
                                                                anchors.bottom:       cpuTrack.top
                                                                anchors.bottomMargin: Math.round(2 * cpuSide.parent.sc)
                                                                anchors.left:         parent.left
                                                                text:  root.sysCpuPct + "%"
                                                                color: Qt.color(root.arcColor(root.sysCpuPct))
                                                                font.pixelSize: Math.round(8 * cpuSide.parent.sc)
                                                                font.family:    root.fontFamily
                                                                font.weight:    Font.Medium
                                                                Behavior on color { ColorAnimation { duration: 300 } }
                                                            }

                                                            // Track
                                                            Rectangle {
                                                                id: cpuTrack
                                                                anchors.left:   parent.left
                                                                anchors.right:  parent.right
                                                                anchors.bottom: parent.bottom
                                                                height: Math.max(1, Math.round(3 * cpuSide.parent.sc))
                                                                radius: height / 2
                                                                color:  Qt.rgba(
                                                                    Qt.color(root.arcColor(root.sysCpuPct)).r,
                                                                    Qt.color(root.arcColor(root.sysCpuPct)).g,
                                                                    Qt.color(root.arcColor(root.sysCpuPct)).b,
                                                                    0.18)

                                                                Rectangle {
                                                                    anchors.left:   parent.left
                                                                    anchors.top:    parent.top
                                                                    anchors.bottom: parent.bottom
                                                                    width:  Math.max(radius * 2, parent.width * (root.sysCpuPct / 100))
                                                                    radius: parent.radius
                                                                    color:  Qt.color(root.arcColor(root.sysCpuPct))
                                                                    Behavior on width { SmoothedAnimation { duration: 400; velocity: -1 } }
                                                                    Behavior on color { ColorAnimation    { duration: 300 } }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // ── RAM side (bar+label left, icon right) ── mirrored
                                                    Item {
                                                        id: ramSide
                                                        anchors.right:  parent.right
                                                        anchors.top:    parent.top
                                                        anchors.bottom: parent.bottom
                                                        anchors.left:   parent.horizontalCenter
                                                        anchors.leftMargin: Math.round(3 * parent.sc)

                                                        // Big RAM icon, vertically centred on right edge
                                                        Text {
                                                            id: ramIcon
                                                            anchors.right:          parent.right
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text:  "󰑭"
                                                            color: Qt.color(root.arcColor(root.sysRamPct))
                                                            font.pixelSize: Math.round(18 * ramSide.parent.sc)
                                                            font.family:    root.fontFamily
                                                            Behavior on color { ColorAnimation { duration: 300 } }
                                                        }

                                                        // Bar + label stacked, to the left of the icon
                                                        Item {
                                                            anchors.right:          ramIcon.left
                                                            anchors.rightMargin:    Math.round(4 * ramSide.parent.sc)
                                                            anchors.left:           parent.left
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            height: Math.round(20 * ramSide.parent.sc)

                                                            // % number above bar, right-aligned to mirror CPU
                                                            Text {
                                                                id: ramLabel
                                                                anchors.bottom:       ramTrack.top
                                                                anchors.bottomMargin: Math.round(2 * ramSide.parent.sc)
                                                                anchors.right:        parent.right
                                                                text:  root.sysRamPct + "%"
                                                                color: Qt.color(root.arcColor(root.sysRamPct))
                                                                font.pixelSize: Math.round(8 * ramSide.parent.sc)
                                                                font.family:    root.fontFamily
                                                                font.weight:    Font.Medium
                                                                Behavior on color { ColorAnimation { duration: 300 } }
                                                            }

                                                            // Track
                                                            Rectangle {
                                                                id: ramTrack
                                                                anchors.left:   parent.left
                                                                anchors.right:  parent.right
                                                                anchors.bottom: parent.bottom
                                                                height: Math.max(1, Math.round(3 * ramSide.parent.sc))
                                                                radius: height / 2
                                                                color:  Qt.rgba(
                                                                    Qt.color(root.arcColor(root.sysRamPct)).r,
                                                                    Qt.color(root.arcColor(root.sysRamPct)).g,
                                                                    Qt.color(root.arcColor(root.sysRamPct)).b,
                                                                    0.18)

                                                                // Fill grows from right to left to mirror CPU
                                                                Rectangle {
                                                                    anchors.right:  parent.right
                                                                    anchors.top:    parent.top
                                                                    anchors.bottom: parent.bottom
                                                                    width:  Math.max(radius * 2, parent.width * (root.sysRamPct / 100))
                                                                    radius: parent.radius
                                                                    color:  Qt.color(root.arcColor(root.sysRamPct))
                                                                    Behavior on width { SmoothedAnimation { duration: 400; velocity: -1 } }
                                                                    Behavior on color { ColorAnimation    { duration: 300 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                Row {
                                                    visible: parent.modelData === "Workspaces"
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Repeater {
                                                        model: Hyprland.workspaces.values.filter(function(ws) { return ws.id > 0 })
                                                        delegate: Rectangle {
                                                            required property var modelData
                                                            property bool isFocused:   modelData.focused
                                                            property int  windowCount: modelData.lastIpcObject ? (modelData.lastIpcObject.windows || 0) : 0
                                                            width:  isFocused ? 28 : 20
                                                            height: isFocused ? 20 : 14
                                                            radius: height / 2
                                                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                                            color: isFocused ? root.textColor : windowCount > 0 ? root.tc(0.35) : root.tc(0.12)
                                                            Behavior on width  { SmoothedAnimation { duration: 180 } }
                                                            Behavior on height { SmoothedAnimation { duration: 180 } }
                                                            Behavior on color  { ColorAnimation    { duration: 150 } }
                                                            Text { anchors.centerIn: parent; text: parent.modelData.name; color: "#000000"; font.pixelSize: 9; font.family: root.fontFamily; font.weight: Font.Bold; visible: parent.isFocused }
                                                            MouseArea { anchors.fill: parent; onClicked: parent.modelData.activate() }
                                                        }
                                                    }
                                                }

                                                Item {
                                                    visible: parent.modelData === "Timer"
                                                    anchors.fill: parent
                                                    Component.onCompleted: {
                                                        if (parent.modelData === "Timer") {
                                                            timerPage.parent  = this
                                                            timerPage.visible = true
                                                            timerPage.anchors.centerIn = this
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottomMargin: 3
                            spacing: 4
                            Repeater {
                                model: defaultView.pageCount
                                delegate: Rectangle {
                                    width:  defaultView.page === index ? 10 : 4
                                    height: 4; radius: 2
                                    color: defaultView.page === index ? root.tc(0.7) : root.tc(0.2)
                                    Behavior on width { SmoothedAnimation { duration: 180 } }
                                    Behavior on color { ColorAnimation    { duration: 150 } }
                                }
                            }
                        }

                        DragHandler {
                            id: swipeDrag
                            target: null
                            xAxis.enabled: true
                            yAxis.enabled: false
                            dragThreshold: 12
                            onActiveChanged: {
                                if (!active) {
                                    var dx = centroid.position.x - centroid.pressPosition.x
                                    if (dx < -30 && defaultView.page < defaultView.pageCount - 1)
                                        defaultView.page++
                                    else if (dx > 30 && defaultView.page > 0)
                                        defaultView.page--
                                }
                            }
                        }

                        DragHandler {
                            id: pullDownDrag
                            target: null
                            xAxis.enabled: false
                            yAxis.enabled: true
                            yAxis.minimum: 0
                            dragThreshold: 16
                            onActiveChanged: {
                                if (!active) {
                                    var dy = centroid.position.y - centroid.pressPosition.y
                                    if (dy > 40) {
                                        var isRightHalf = centroid.pressPosition.x > (defaultView.width / 2)
                                        root.doClickAction(isRightHalf ? root.dragDownRight : root.dragDown)
                                    }
                                }
                            }
                        }

                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: root.doClickAction(root.clickLeft)
                        }

                    }

                    Item {
                        anchors.fill: parent
                        opacity: root.islandState === "music" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        TapHandler {
                            onTapped: root.islandState = "default"
                        }

                        RowLayout {
                            anchors.fill:         parent
                            anchors.leftMargin:   12
                            anchors.rightMargin:  12
                            anchors.topMargin:    12
                            anchors.bottomMargin: 12
                            spacing: 10

                            Rectangle {
                                width: 58; height: 58
                                radius: 10
                                color: "#1c1c1c"
                                Layout.alignment: Qt.AlignVCenter
                                clip: true
                                layer.enabled: true

                                Image {
                                    anchors.fill: parent
                                    source:   root.albumArt
                                    fillMode: Image.PreserveAspectCrop
                                    smooth:   true
                                    visible:  root.albumArt !== ""
                                    cache:    false
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text:    "♪"
                                    color:   Qt.rgba(1, 1, 1, 0.25)
                                    font.pixelSize: 24; font.family: root.fontFamily
                                    visible: root.albumArt === ""
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth:  true
                                Layout.fillHeight: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            id: songTitleText
                                            text: root.songTitle || "Nothing playing"
                                            color: root.textColor
                                            font.pixelSize: 12; font.family: root.fontFamily
                                            font.weight:    Font.Bold
                                            elide:          Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            id: songArtistText
                                            text:    root.songArtist
                                            color:   Qt.rgba(1, 1, 1, 0.45)
                                            font.pixelSize: 10; font.family: root.fontFamily
                                            elide:   Text.ElideRight
                                            Layout.fillWidth: true
                                            visible: root.songArtist !== ""
                                        }
                                    }

                                    RowLayout {
                                        spacing: 2
                                        Layout.alignment: Qt.AlignVCenter

                                        Rectangle {
                                            width: 26; height: 26; radius: 13
                                            color: prevArea.containsMouse ? root.tc(0.12) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            Text { anchors.centerIn: parent; text: "⏮"; color: root.textColor; font.pixelSize: 11; font.family: root.fontFamily }
                                            MouseArea { id: prevArea; anchors.fill: parent; hoverEnabled: true; onClicked: mpcPrev.running = true }
                                        }

                                        Rectangle {
                                            width: 28; height: 28; radius: 14
                                            color: playArea.containsMouse ? root.tc(0.18) : root.tc(0.08)
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            Text { anchors.centerIn: parent; text: root.isPlaying ? "⏸" : "▶"; color: root.textColor; font.pixelSize: root.isPlaying ? 11 : 10 }
                                            MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; onClicked: mpcToggle.running = true }
                                        }

                                        Rectangle {
                                            width: 26; height: 26; radius: 13
                                            color: nextArea.containsMouse ? root.tc(0.12) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            Text { anchors.centerIn: parent; text: "⏭"; color: root.textColor; font.pixelSize: 11; font.family: root.fontFamily }
                                            MouseArea { id: nextArea; anchors.fill: parent; hoverEnabled: true; onClicked: mpcNext.running = true }
                                        }
                                    }
                                }

                                Canvas {
                                    id: musicCanvas
                                    Layout.fillWidth: true
                                    height: 18
                                    property var bars: root.cavaBars
                                    onBarsChanged: if (root.islandState === "music") requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        var n = 10, sp = 2
                                        var bw = (width - sp * (n - 1)) / n
                                        for (var i = 0; i < n; i++) {
                                            var v = (i < bars.length) ? bars[i] : 0
                                            var h = Math.max(2, (v / 9) * height)
                                            var x = i * (bw + sp)
                                            var y = height - h
                                            ctx.fillStyle = root.tc(0.6)
                                            root.drawBar(ctx, x, y, bw, h, 1)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: root.islandState === "notification" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        TapHandler {
                            onTapped: {
                                root.launchNotifApp(root.notifDesktopEntry, root.notifAppName, root.notifUrl)
                                notifDismissTimer.stop()
                                root.notifVisible = false
                                root.islandState  = "default"
                            }
                        }

                        RowLayout {
                            anchors.fill:        parent
                            anchors.leftMargin:  12
                            anchors.rightMargin: 12
                            anchors.topMargin:   10
                            anchors.bottomMargin: 14
                            spacing: 10

                            Item {
                                id: notifIconItem
                                width: 38; height: 38
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 11
                                    color: {
                                        var a = root.notifAppName.toLowerCase()
                                        if (a.indexOf("discord")     >= 0) return "#5865F2"
                                        if (a.indexOf("spotify")     >= 0) return "#1DB954"
                                        if (a.indexOf("firefox")     >= 0) return "#FF6611"
                                        if (a.indexOf("chrome")      >= 0) return "#4285F4"
                                        if (a.indexOf("telegram")    >= 0) return "#2AABEE"
                                        if (a.indexOf("slack")       >= 0) return "#4A154B"
                                        if (a.indexOf("signal")      >= 0) return "#3A76F0"
                                        if (a.indexOf("teams")       >= 0) return "#6264A7"
                                        if (a.indexOf("thunderbird") >= 0) return "#0A84FF"
                                        if (a.indexOf("code")        >= 0) return "#007ACC"
                                        if (a.indexOf("steam")       >= 0) return "#1B2838"
                                        return Qt.rgba(1, 1, 1, 0.12)
                                    }

                                    Image {
                                        id: notifAppIcon
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        source: {
                                            var p = root.notifIconPath
                                            if (p === "") return ""
                                            if (p.startsWith("/"))
                                                return "file://" + p

                                            if (p.indexOf("/") < 0 && p.indexOf(".") < 0)
                                                return "image://theme/" + p
                                            return p
                                        }
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                        visible: root.notifIconPath !== "" && status === Image.Ready
                                        cache: false
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.notifAppName.length > 0
                                              ? root.notifAppName[0].toUpperCase() : "?"
                                        color: root.textColor
                                        font.pixelSize: 17; font.family: root.fontFamily
                                        font.weight: Font.Bold
                                        visible: !notifAppIcon.visible
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: root.notifAppName
                                    color: Qt.rgba(1, 1, 1, 0.45)
                                    font.pixelSize: 10; font.family: root.fontFamily
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    visible: root.notifAppName !== ""
                                }

                                Text {
                                    id: notifSummaryText
                                    Layout.fillWidth: true
                                    text: root.notifSummary
                                    color: root.textColor
                                    font.pixelSize: 12; font.family: root.fontFamily
                                    font.weight: Font.SemiBold
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    visible: root.notifSummary !== ""
                                }

                                Text {
                                    id: notifBodyText
                                    Layout.fillWidth: true
                                    text: root.notifBody
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font.pixelSize: 11; font.family: root.fontFamily
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    wrapMode: Text.NoWrap
                                    visible: root.notifBody !== ""
                                }
                            }

                            Text {
                                text: "×"
                                color: Qt.rgba(1, 1, 1, 0.35)
                                font.pixelSize: 18; font.family: root.fontFamily
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        notifDismissTimer.stop()
                                        root.notifVisible = false
                                        root.islandState  = "default"
                                    }
                                }
                            }
                        }

                        Item {
                            anchors.bottom: parent.bottom
                            anchors.left:   parent.left
                            anchors.right:  parent.right
                            anchors.leftMargin:  30
                            anchors.rightMargin: 30
                            anchors.bottomMargin: 5
                            height: 3

                            Rectangle {
                                anchors.fill: parent
                                radius: 1.5
                                color: Qt.rgba(1, 1, 1, 0.1)
                            }

                            Rectangle {
                                id: notifProgressBar
                                anchors.left:   parent.left
                                anchors.top:    parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width
                                radius: 1.5
                                color: Qt.rgba(1, 1, 1, 0.45)

                                NumberAnimation on width {
                                    id: notifProgressAnim
                                    running: root.islandState === "notification"
                                    from:    notifProgressBar.parent.width
                                    to:      0
                                    duration: 5000
                                    onStarted: notifProgressBar.width = notifProgressBar.parent.width
                                }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: root.islandState === "notifHistory" ? 1 : 0
                        visible: opacity > 0
                        clip: true
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        TapHandler { onTapped: root.islandState = "default" }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 0
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                Layout.leftMargin: 14
                                Layout.rightMargin: 8

                                Text {
                                    text: "Notifications"
                                    color: root.textColor
                                    font.pixelSize: 13; font.family: root.fontFamily
                                    font.weight: Font.SemiBold
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    width: 58; height: 24
                                    radius: 12
                                    color: root.tc(0.08)
                                    visible: notifHistory.count > 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Clear"
                                        color: root.tc(0.55)
                                        font.pixelSize: 11; font.family: root.fontFamily
                                        font.weight: Font.Medium
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.historyCleared = true
                                            notifHistory.clear()
                                            root.saveHistory()
                                            root.islandState = "default"
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: root.tc(0.07)
                                visible: notifHistory.count > 0
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: notifHistory.count === 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "No notifications"
                                    color: root.tc(0.3)
                                    font.pixelSize: 12; font.family: root.fontFamily
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: notifHistory.count > 0

                                ListView {
                                    id: notifHistoryList
                                    anchors.fill: parent
                                    model: notifHistory
                                    clip: true
                                    spacing: 0
                                    boundsBehavior: Flickable.StopAtBounds

                                delegate: Item {
                                    id: delegateRoot
                                    width: notifHistoryList.width
                                    height: 68

                                    HoverHandler { id: delegateHover }

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        radius: 10
                                        color: root.tc(delegateHover.containsMouse ? 0.07 : 0)
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.rightMargin: 36
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.launchNotifApp(model.hDesktop || "", model.hApp || "", model.hUrl || "")
                                            root.islandState = "default"
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 10
                                        anchors.bottomMargin: 10
                                        spacing: 10

                                        Item {
                                            width: 36; height: 36
                                            Layout.alignment: Qt.AlignVCenter

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 10
                                                color: {
                                                    var a = (model.hApp || "").toLowerCase()
                                                    if (a.indexOf("discord")     >= 0) return "#5865F2"
                                                    if (a.indexOf("spotify")     >= 0) return "#1DB954"
                                                    if (a.indexOf("firefox")     >= 0) return "#FF6611"
                                                    if (a.indexOf("chrome")      >= 0) return "#4285F4"
                                                    if (a.indexOf("telegram")    >= 0) return "#2AABEE"
                                                    if (a.indexOf("slack")       >= 0) return "#4A154B"
                                                    if (a.indexOf("signal")      >= 0) return "#3A76F0"
                                                    if (a.indexOf("teams")       >= 0) return "#6264A7"
                                                    if (a.indexOf("thunderbird") >= 0) return "#0A84FF"
                                                    if (a.indexOf("code")        >= 0) return "#007ACC"
                                                    if (a.indexOf("steam")       >= 0) return "#1B2838"
                                                    return root.tc(0.10)
                                                }

                                                Image {
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    source: {
                                                        var p = model.hIcon || ""
                                                        if (p === "") return ""
                                                        if (p.startsWith("/")) return "file://" + p
                                                        if (p.indexOf("/") < 0 && p.indexOf(".") < 0)
                                                            return "image://theme/" + p
                                                        return p
                                                    }
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true; mipmap: true
                                                    visible: (model.hIcon || "") !== "" && status === Image.Ready
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (model.hApp || "?")[0].toUpperCase()
                                                    color: root.textColor
                                                    font.pixelSize: 15; font.family: root.fontFamily
                                                    font.weight: Font.Bold
                                                    visible: (model.hIcon || "") === ""
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 1

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 0

                                                Text {
                                                    text: model.hApp || ""
                                                    color: root.tc(0.42)
                                                    font.pixelSize: 10; font.family: root.fontFamily
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                    maximumLineCount: 1
                                                    visible: (model.hApp || "") !== ""
                                                }

                                                Text {
                                                    text: model.hTime || ""
                                                    color: root.tc(0.28)
                                                    font.pixelSize: 10; font.family: root.fontFamily
                                                    Layout.alignment: Qt.AlignRight
                                                }
                                            }

                                            Text {
                                                text: model.hSummary || ""
                                                color: root.textColor
                                                font.pixelSize: 12; font.family: root.fontFamily
                                                font.weight: Font.SemiBold
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                maximumLineCount: 1
                                                visible: (model.hSummary || "") !== ""
                                            }

                                            Text {
                                                text: model.hBody || ""
                                                color: root.tc(0.55)
                                                font.pixelSize: 11; font.family: root.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                maximumLineCount: 1
                                                visible: (model.hBody || "") !== ""
                                            }
                                        }

                                        Text {
                                            text: "×"
                                            color: root.tc(delegateHover.containsMouse ? 0.55 : 0)
                                            font.pixelSize: 18; font.family: root.fontFamily
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.preferredWidth: 24
                                            horizontalAlignment: Text.AlignHCenter
                                            Behavior on color { ColorAnimation { duration: 100 } }

                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    notifHistory.remove(index)
                                                    root.saveHistory()
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        height: 1
                                        color: root.tc(0.05)
                                        visible: index < notifHistory.count - 1
                                    }
                                }
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 3
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 3
                                    radius: 1.5
                                    color: root.tc(0.18)
                                    visible: notifHistoryList.contentHeight > notifHistoryList.height
                                    opacity: notifHistoryList.moving ? 1 : 0.5
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Rectangle {
                                        width: parent.width
                                        radius: parent.radius
                                        color: root.tc(0.7)
                                        height: notifHistoryList.height > 0
                                            ? Math.max(24, notifHistoryList.height
                                                * notifHistoryList.height / Math.max(1, notifHistoryList.contentHeight))
                                            : 0
                                        y: notifHistoryList.contentHeight > notifHistoryList.height
                                            ? notifHistoryList.contentY
                                                * (notifHistoryList.height - height)
                                                / (notifHistoryList.contentHeight - notifHistoryList.height)
                                            : 0
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: root.islandState === "controlPanel" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        TapHandler {
                            onTapped: root.islandState = "default"
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            anchors.topMargin: 16
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                                                Layout.fillWidth: true
                                                                height: 52
                                                                radius: 14
                                                                color: root.tc(0.07)

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    onClicked: {
                                                                        root.wifiNetworksOpen = !root.wifiNetworksOpen
                                                                        if (root.wifiNetworksOpen && root.wifiEnabled) {
                                                                            wifiNetworkModel.clear()
                                                                            wifiScanProc.running = false
                                                                            wifiScanProc.running = true
                                                                        }
                                                                    }
                                                                }

                                                                RowLayout {
                                                                    anchors.fill: parent
                                                                    anchors.leftMargin: 12
                                                                    anchors.rightMargin: 12
                                                                    spacing: 10

                                                                    Rectangle {
                                                                        width: 44; height: 26; radius: 13
                                                                        color: root.wifiEnabled ? root.tc(0.85) : root.tc(0.15)
                                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                                        Rectangle {
                                                                            width: 20; height: 20; radius: 10
                                                                            anchors.verticalCenter: parent.verticalCenter
                                                                            x: root.wifiEnabled ? parent.width - width - 3 : 3
                                                                            color: root.wifiEnabled ? root.pillColor : root.tc(0.6)
                                                                            Behavior on x { SmoothedAnimation { duration: 150 } }
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        MouseArea {
                                                                            anchors.fill: parent
                                                                            onClicked: {
                                                                                root.wifiEnabled = !root.wifiEnabled
                                                                                wifiToggleProc.enabling = root.wifiEnabled
                                                                                wifiToggleProc.running = false
                                                                                wifiToggleProc.running = true
                                                                                if (!root.wifiEnabled) root.wifiNetworksOpen = false
                                                                            }
                                                                        }
                                                                    }

                                                                    ColumnLayout {
                                                                        Layout.fillWidth: true
                                                                        spacing: 1
                                                                        Text {
                                                                            text: "Wi-Fi"
                                                                            color: root.wifiEnabled ? root.textColor : root.tc(0.45)
                                                                            font.pixelSize: 12; font.family: root.fontFamily
                                                                            font.weight: Font.Medium
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        Text {
                                                                            text: root.wifiEnabled
                                                                                  ? (root.wifiConnectedSsid !== "" ? root.wifiConnectedSsid : "On")
                                                                                  : root.wifiStatus
                                                                            color: root.wifiEnabled ? root.tc(0.6) : root.tc(0.28)
                                                                            font.pixelSize: 10; font.family: root.fontFamily
                                                                            elide: Text.ElideRight
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                Rectangle {
                                                                Layout.fillWidth: true
                                                                height: 52
                                                                radius: 14
                                                                color: root.tc(0.07)

                                                                RowLayout {
                                                                    anchors.fill: parent
                                                                    anchors.leftMargin: 12
                                                                    anchors.rightMargin: 12
                                                                    spacing: 10

                                                                    Rectangle {
                                                                        width: 44; height: 26; radius: 13
                                                                        color: root.bluetoothEnabled ? root.tc(0.85) : root.tc(0.15)
                                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                                        Rectangle {
                                                                            width: 20; height: 20; radius: 10
                                                                            anchors.verticalCenter: parent.verticalCenter
                                                                            x: root.bluetoothEnabled ? parent.width - width - 3 : 3
                                                                            color: root.bluetoothEnabled ? root.pillColor : root.tc(0.6)
                                                                            Behavior on x { SmoothedAnimation { duration: 150 } }
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        MouseArea {
                                                                            anchors.fill: parent
                                                                            onClicked: {
                                                                                root.bluetoothEnabled = !root.bluetoothEnabled
                                                                                btToggleProc.enabling = root.bluetoothEnabled
                                                                                btToggleProc.running = false
                                                                                btToggleProc.running = true
                                                                            }
                                                                        }
                                                                    }

                                                                    ColumnLayout {
                                                                        Layout.fillWidth: true
                                                                        spacing: 1
                                                                        Text {
                                                                            text: "Bluetooth"
                                                                            color: root.bluetoothEnabled ? root.textColor : root.tc(0.45)
                                                                            font.pixelSize: 12; font.family: root.fontFamily
                                                                            font.weight: Font.Medium
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                        Text {
                                                                            text: root.bluetoothEnabled ? "On" : root.bluetoothStatus
                                                                            color: root.bluetoothEnabled ? root.tc(0.6) : root.tc(0.28)
                                                                            font.pixelSize: 10; font.family: root.fontFamily
                                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                                        }
                                                                    }
                                                                }
                                                            }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 52
                                radius: 14
                                color: root.soundAppsOpen ? root.tc(0.12) : root.tc(0.07)
                                Behavior on color { ColorAnimation { duration: 150 } }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.soundAppsOpen = !root.soundAppsOpen
                                        if (root.soundAppsOpen) {
                                            appVolumeModel.clear()
                                            appVolumePoller.running = false
                                            appVolumePoller.running = true
                                        }
                                    }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 4

                                    Text {
                                        text: "Sound"
                                        color: root.textColor
                                        font.pixelSize: 11; font.family: root.fontFamily
                                        font.weight: Font.Medium
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        height: 18
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width; height: 8; radius: 4
                                            color: root.tc(0.12)
                                            Rectangle { width: parent.width * root.volume; height: parent.height; radius: parent.radius; color: root.textColor }
                                            Rectangle {
                                                x: (parent.width * root.volume) - width / 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 18; height: 18; radius: 9; color: root.textColor
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: mouse => {
                                                var v = Math.max(0, Math.min(1, mouse.x / width))
                                                root.volume = v; volumeSetter.targetVol = v
                                                volumeSetter.running = false; volumeSetter.running = true
                                            }
                                            onPositionChanged: mouse => {
                                                if (pressed) {
                                                    var v = Math.max(0, Math.min(1, mouse.x / width))
                                                    root.volume = v; volumeSetter.targetVol = v
                                                    volumeSetter.running = false; volumeSetter.running = true
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 52
                                radius: 14
                                color: root.tc(0.07)

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 4
                                    Text {
                                        text: "Display"
                                        color: root.textColor
                                        font.pixelSize: 11; font.family: root.fontFamily
                                        font.weight: Font.Medium
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        height: 18
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width; height: 8; radius: 4
                                            color: root.tc(0.12)
                                            Rectangle {
                                                width: parent.width * root.brightness
                                                height: parent.height; radius: parent.radius
                                                color: root.textColor
                                                Behavior on width { SmoothedAnimation { duration: 80 } }
                                            }
                                            Rectangle {
                                                x: (parent.width * root.brightness) - width / 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 18; height: 18; radius: 9; color: root.textColor
                                                Behavior on x { SmoothedAnimation { duration: 80 } }
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: mouse => {
                                                var v = Math.max(0.05, Math.min(1.0, mouse.x / width))
                                                root.brightness = v
                                                brightnessSetter.targetBright = v
                                                brightnessSetter.running = false
                                                brightnessSetter.running = true
                                            }
                                            onPositionChanged: mouse => {
                                                if (pressed) {
                                                    var v = Math.max(0.05, Math.min(1.0, mouse.x / width))
                                                    root.brightness = v
                                                    brightnessSetter.targetBright = v
                                                    brightnessSetter.running = false
                                                    brightnessSetter.running = true
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 52
                                    radius: 14
                                    color: root.tc(0.07)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        Text {
                                            text: "󰹑"
                                            color: root.textColor
                                            font.pixelSize: 18; font.family: root.fontFamily
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                text: "Screenshot"
                                                color: root.textColor
                                                font.pixelSize: 12; font.family: root.fontFamily
                                                font.weight: Font.Medium
                                            }
                                            Text {
                                                text: "slurp + grim"
                                                color: root.tc(0.4)
                                                font.pixelSize: 10; font.family: root.fontFamily
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.controlPanelOpen = false
                                            root.islandState = "default"
                                            screenshotDelayTimer.restart()
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 52
                                    radius: 14
                                    color: root.obsRecording ? Qt.rgba(1,0.15,0.15,0.25) : root.tc(0.07)
                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        Rectangle {
                                            width: 10; height: 10; radius: 5
                                            color: root.obsRecording ? "#ff4444" : root.tc(0.4)
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                text: root.obsRecording ? "Recording" : "Record"
                                                color: root.obsRecording ? "#ff8888" : root.textColor
                                                font.pixelSize: 12; font.family: root.fontFamily
                                                font.weight: Font.Medium
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                            Text {
                                                text: "OBS"
                                                color: root.tc(0.4)
                                                font.pixelSize: 10; font.family: root.fontFamily
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.obsRecording) {
                                                obsStopProc.running = false
                                                obsStopProc.running = true
                                                root.obsRecording = false
                                            } else {
                                                obsStartProc.running = false
                                                obsStartProc.running = true
                                                root.obsRecording = true
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 52
                                    radius: 14
                                    color: root.tc(0.07)

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 3

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "󰌾"
                                            color: root.tc(0.8)
                                            font.pixelSize: 18; font.family: root.fontFamily
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "Lock"
                                            color: root.tc(0.5)
                                            font.pixelSize: 10; font.family: root.fontFamily
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.islandState = "default"
                                            lockProc.running = false
                                            lockProc.running = true
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 52
                                    radius: 14
                                    color: root.tc(0.07)

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 3

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "󰒲"
                                            color: root.tc(0.8)
                                            font.pixelSize: 18; font.family: root.fontFamily
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "Sleep"
                                            color: root.tc(0.5)
                                            font.pixelSize: 10; font.family: root.fontFamily
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.islandState = "default"
                                            sleepProc.running = false
                                            sleepProc.running = true
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 52
                                    radius: 14
                                    color: root.tc(0.07)

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 3

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "󰜉"
                                            color: Qt.rgba(1,0.7,0.3,0.9)
                                            font.pixelSize: 18; font.family: root.fontFamily
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "Reboot"
                                            color: root.tc(0.5)
                                            font.pixelSize: 10; font.family: root.fontFamily
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.islandState = "default"
                                            rebootProc.running = false
                                            rebootProc.running = true
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 52
                                    radius: 14
                                    color: root.tc(0.07)

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 3

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "󰐥"
                                            color: Qt.rgba(1,0.35,0.35,0.9)
                                            font.pixelSize: 18; font.family: root.fontFamily
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "Shutdown"
                                            color: root.tc(0.5)
                                            font.pixelSize: 10; font.family: root.fontFamily
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.islandState = "default"
                                            shutdownProc.running = false
                                            shutdownProc.running = true
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                height: 14

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 44; height: 4; radius: 2
                                    color: pillWrapper.silenceHandleOpen
                                           ? root.tc(0.4)
                                           : root.tc(0.18)
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -10
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pillWrapper.silenceHandleOpen = !pillWrapper.silenceHandleOpen
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: pillWrapper.silenceHandleOpen || silenceHideTimer.running
                                opacity: pillWrapper.silenceHandleOpen ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200 } }

                                Timer {
                                    id: silenceHideTimer
                                    interval: 220
                                    repeat: false
                                }
                                onVisibleChanged: {
                                    if (!pillWrapper.silenceHandleOpen) silenceHideTimer.start()
                                }

                                // Silence + VPN side by side
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 52
                                        radius: 14
                                        color: root.silenced
                                               ? Qt.rgba(1, 0.55, 0.26, 0.22)
                                               : root.tc(0.07)
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 10

                                            Text {
                                                text: root.silenced ? "󰂛" : "󰂜"
                                                color: root.silenced ? "#FF8C42" : root.tc(0.75)
                                                font.pixelSize: 18; font.family: root.fontFamily
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: root.silenced ? "Silenced" : "Silence"
                                                    color: root.silenced ? "#FF8C42" : root.textColor
                                                    font.pixelSize: 12; font.family: root.fontFamily
                                                    font.weight: Font.Medium
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                                Text {
                                                    text: root.silenced ? "Suppressed" : "Notifications"
                                                    color: root.tc(0.38)
                                                    font.pixelSize: 10; font.family: root.fontFamily
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.silenced = !root.silenced
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 52
                                        radius: 14
                                        color: root.vpnLocationsOpen
                                               ? root.tc(0.14)
                                               : root.vpnConnected
                                                 ? Qt.rgba(0.18, 0.78, 0.45, 0.22)
                                                 : root.tc(0.07)
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 10

                                            Text {
                                                text: root.vpnConnected ? "󰦝" : "󰦞"
                                                color: root.vpnConnected ? "#2EC86E" : root.tc(0.75)
                                                font.pixelSize: 18; font.family: root.fontFamily
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: root.vpnConnected ? "Connected" : "Mullvad"
                                                    color: root.vpnConnected ? "#2EC86E" : root.textColor
                                                    font.pixelSize: 12; font.family: root.fontFamily
                                                    font.weight: Font.Medium
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                                Text {
                                                    text: root.vpnConnected
                                                          ? (root.vpnLocation !== "" ? root.vpnLocation : "VPN on")
                                                          : "Hold to pick location"
                                                    color: root.tc(0.38)
                                                    font.pixelSize: 10; font.family: root.fontFamily
                                                }
                                            }

                                            // Arrow indicating panel is openable
                                            Text {
                                                text: "›"
                                                color: root.vpnLocationsOpen ? root.tc(0.7) : root.tc(0.25)
                                                font.pixelSize: 16; font.family: root.fontFamily
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                        }

                                        // Single handler: short press = connect/disconnect, long press = location picker
                                        MouseArea {
                                            anchors.fill: parent

                                            Timer {
                                                id: vpnLongPressTimer
                                                interval: 500
                                                repeat: false
                                                onTriggered: {
                                                    root.vpnLongDidFire = true
                                                    if (!root.vpnLocationsOpen) {
                                                        vpnLocationModel.clear()
                                                        vpnLocationLoader.running = false
                                                        vpnLocationLoader.running = true
                                                    }
                                                    root.vpnLocationsOpen = !root.vpnLocationsOpen
                                                }
                                            }

                                            onPressed:  { root.vpnLongDidFire = false; vpnLongPressTimer.restart() }
                                            onReleased: {
                                                vpnLongPressTimer.stop()
                                                if (!root.vpnLongDidFire) {
                                                    if (root.vpnConnected) {
                                                        vpnDisconnectProc.running = false
                                                        vpnDisconnectProc.running = true
                                                        root.vpnConnected = false
                                                        root.vpnLocation  = ""
                                                    } else {
                                                        vpnConnectProc.running = false
                                                        vpnConnectProc.running = true
                                                        root.vpnConnected = true
                                                    }
                                                }
                                            }
                                            onCanceled: vpnLongPressTimer.stop()
                                        }
                                    }
                                }

                                // ── Settings button — full width, below Silence + VPN ──
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 52
                                    radius: 14
                                    color: root.islandState === "settings" ? root.tc(0.14) : root.tc(0.07)
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 10

                                        Text {
                                            text: "⚙"
                                            color: root.tc(0.75)
                                            font.pixelSize: 17; font.family: root.fontFamily
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                text: "Settings"
                                                color: root.textColor
                                                font.pixelSize: 12; font.family: root.fontFamily
                                                font.weight: Font.Medium
                                            }
                                            Text {
                                                text: "Appearance & bindings"
                                                color: root.tc(0.38)
                                                font.pixelSize: 10; font.family: root.fontFamily
                                            }
                                        }

                                        Text {
                                            text: "›"
                                            color: root.tc(0.35)
                                            font.pixelSize: 18; font.family: root.fontFamily
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.islandState = "settings"
                                    }
                                }
                            }

                        }
                    }
                }

                    Item {
                        anchors.fill: parent
                        opacity: root.islandState === "appLauncher" ? 1 : 0
                        visible: opacity > 0
                        clip: true
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        TapHandler {
                            onTapped: {
                                root.islandState = "default"
                                root.appLauncherQuery = ""
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.topMargin: 0
                            anchors.leftMargin: 0
                            anchors.rightMargin: 0
                            anchors.bottomMargin: 10
                            spacing: 0

                            Item {
                                Layout.fillWidth: true
                                height: 52

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 36; height: 4; radius: 2
                                    color: root.tc(0.25)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.topMargin: 16
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 10
                                    anchors.bottomMargin: 6
                                    spacing: 8

                                    Text {
                                        text: "󰍉"
                                        color: root.tc(0.45)
                                        font.pixelSize: 15; font.family: root.fontFamily
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        height: appSearchInput.implicitHeight

                                        TextInput {
                                            id: appSearchInput
                                            anchors.fill: parent
                                            color: root.textColor
                                            font.pixelSize: 14; font.family: root.fontFamily
                                            font.weight: Font.Medium
                                            selectedTextColor: "#000000"
                                            selectionColor: root.tc(0.6)
                                            text: root.appLauncherQuery
                                            onTextChanged: root.appLauncherQuery = text

                                            onVisibleChanged: if (visible) forceActiveFocus()
                                            verticalAlignment: TextInput.AlignVCenter
                                        }

                                        Text {
                                            anchors.fill: parent
                                            text: "Search apps…"
                                            color: root.tc(0.3)
                                            font.pixelSize: 14; font.family: root.fontFamily
                                            font.weight: Font.Medium
                                            verticalAlignment: Text.AlignVCenter
                                            visible: appSearchInput.text.length === 0
                                            enabled: false
                                        }
                                    }

                                    Text {
                                        text: "×"
                                        color: root.appLauncherQuery !== "" ? root.tc(0.45) : "transparent"
                                        font.pixelSize: 18; font.family: root.fontFamily
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            onClicked: {
                                                root.appLauncherQuery = ""
                                                appSearchInput.text = ""
                                                appSearchInput.forceActiveFocus()
                                            }
                                        }
                                    }

                                    Text {
                                        text: "↑"
                                        color: root.tc(0.35)
                                        font.pixelSize: 14; font.family: root.fontFamily
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            onClicked: {
                                                root.islandState = "default"
                                                root.appLauncherQuery = ""
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: root.tc(0.07)
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: appLauncherModel.count === 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "Loading apps…"
                                    color: root.tc(0.3)
                                    font.pixelSize: 12; font.family: root.fontFamily
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: appLauncherModel.count > 0

                                property var filteredApps: root.appLauncherFiltered()

                                Connections {
                                    target: root
                                    function onAppLauncherQueryChanged() { launcherGrid.filteredApps = root.appLauncherFiltered() }
                                    function onAppFavouritesChanged()    { launcherGrid.filteredApps = root.appLauncherFiltered() }
                                }
                                Connections {
                                    target: appLauncherModel
                                    function onCountChanged() { launcherGrid.filteredApps = root.appLauncherFiltered() }
                                }

                                GridView {
                                    id: launcherGrid
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    property var filteredApps: root.appLauncherFiltered()

                                    cellWidth:  Math.floor(width / 4)
                                    cellHeight: 96

                                    model: filteredApps

                                    delegate: Item {
                                        width:  launcherGrid.cellWidth
                                        height: launcherGrid.cellHeight

                                        required property var modelData
                                        property bool isFav: root.appFavourites.indexOf(modelData.desktopId) >= 0

                                        HoverHandler { id: cellHover }

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            radius: 14
                                            color: cellHover.containsMouse ? root.tc(0.10) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 80 } }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 4

                                            Item {
                                                Layout.alignment: Qt.AlignHCenter
                                                width: 44; height: 44

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 12
                                                    color: root.tc(0.08)
                                                }

                                                Image {
                                                    id: appIcon
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    source: {
                                                        var ic = modelData.icon
                                                        if (!ic || ic === "") return ""

                                                        if (ic.startsWith("/")) return "file://" + ic

                                                        if (ic.startsWith("file://")) return ic

                                                        return "image://theme/" + ic
                                                    }
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                    mipmap: true
                                                    cache: false
                                                    visible: source !== "" && status === Image.Ready
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.name.length > 0 ? modelData.name[0].toUpperCase() : "?"
                                                    color: root.textColor
                                                    font.pixelSize: 18; font.family: root.fontFamily
                                                    font.weight: Font.Bold
                                                    visible: !appIcon.visible
                                                }

                                                Rectangle {
                                                    visible: isFav
                                                    anchors.top: parent.top
                                                    anchors.right: parent.right
                                                    anchors.topMargin: -2
                                                    anchors.rightMargin: -2
                                                    width: 14; height: 14; radius: 7
                                                    color: "#FFD700"

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "★"
                                                        color: "#000000"
                                                        font.pixelSize: 8; font.family: root.fontFamily
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.name
                                                color: root.textColor
                                                font.pixelSize: 10; font.family: root.fontFamily
                                                font.weight: Font.Medium
                                                horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideRight
                                                maximumLineCount: 2
                                                wrapMode: Text.WordWrap
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) {
                                                    root.toggleFavourite(modelData.desktopId)
                                                } else {
                                                    root.launchApp(modelData.desktopId, modelData.exec)
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 2
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 3; radius: 1.5
                                    color: root.tc(0.15)
                                    visible: launcherGrid.contentHeight > launcherGrid.height
                                    opacity: launcherGrid.moving ? 1 : 0.5
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Rectangle {
                                        width: parent.width; radius: parent.radius
                                        color: root.tc(0.65)
                                        height: launcherGrid.height > 0
                                            ? Math.max(20, launcherGrid.height * launcherGrid.height / Math.max(1, launcherGrid.contentHeight))
                                            : 0
                                        y: launcherGrid.contentHeight > launcherGrid.height
                                            ? launcherGrid.contentY * (launcherGrid.height - height) / (launcherGrid.contentHeight - launcherGrid.height)
                                            : 0
                                    }
                                }
                            }
                        }
                    }

                    // ── Screen Time Panel ─────────────────────────────────────────
                    Item {
                        anchors.fill: parent
                        opacity: root.islandState === "screenTime" ? 1 : 0
                        visible: opacity > 0
                        clip: true
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        onVisibleChanged: {
                            if (visible) root.refreshPlaytimeModel()
                        }

                        TapHandler {
                            onTapped: {
                                root.saveScreentimeData()
                                root.islandState = "default"
                                root.screenTimeOpen = false
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.topMargin: 0
                            anchors.leftMargin: 0
                            anchors.rightMargin: 0
                            anchors.bottomMargin: 10
                            spacing: 0

                            // ── Header ─────────────────────────────────────────────
                            Item {
                                Layout.fillWidth: true
                                height: 52

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 36; height: 4; radius: 2
                                    color: root.tc(0.25)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.topMargin: 16
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 12
                                    anchors.bottomMargin: 6
                                    spacing: 8

                                    Text {
                                        text: "⏱"
                                        color: root.tc(0.55)
                                        font.pixelSize: 14; font.family: root.fontFamily
                                    }

                                    Text {
                                        text: "Screen Time"
                                        color: root.textColor
                                        font.pixelSize: 14; font.family: root.fontFamily
                                        font.weight: Font.SemiBold
                                        Layout.fillWidth: true
                                    }

                                    // Sort toggle
                                    Rectangle {
                                        width: 68; height: 24; radius: 12
                                        color: root.tc(0.1)
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            spacing: 0
                                            Rectangle {
                                                Layout.fillWidth: true; height: parent.height
                                                radius: 10
                                                color: root.screenTimeSort === "session" ? root.tc(0.25) : "transparent"
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Now"
                                                    color: root.screenTimeSort === "session" ? root.textColor : root.tc(0.45)
                                                    font.pixelSize: 9; font.family: root.fontFamily
                                                    font.weight: Font.Medium
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        root.screenTimeSort = "session"
                                                        root.refreshPlaytimeModel()
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true; height: parent.height
                                                radius: 10
                                                color: root.screenTimeSort === "total" ? root.tc(0.25) : "transparent"
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "All"
                                                    color: root.screenTimeSort === "total" ? root.textColor : root.tc(0.45)
                                                    font.pixelSize: 9; font.family: root.fontFamily
                                                    font.weight: Font.Medium
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        root.screenTimeSort = "total"
                                                        root.refreshPlaytimeModel()
                                                        root.saveScreentimeData()
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        text: "↑"
                                        color: root.tc(0.35)
                                        font.pixelSize: 14; font.family: root.fontFamily
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            onClicked: {
                                                root.saveScreentimeData()
                                                root.islandState = "default"
                                                root.screenTimeOpen = false
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: root.tc(0.07)
                            }

                            // ── Uptime strip ───────────────────────────────────────
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                Layout.leftMargin: 14
                                Layout.rightMargin: 14
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        text: "PC uptime"
                                        color: root.tc(0.4)
                                        font.pixelSize: 9; font.family: root.fontFamily
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        text: root.systemUptimeStr
                                        color: root.textColor
                                        font.pixelSize: 13; font.family: root.fontFamily
                                        font.weight: Font.SemiBold
                                    }
                                }

                                Rectangle {
                                    visible: root.screenTimeSort === "total"
                                    width: 1; height: 28
                                    color: root.tc(0.1)
                                }

                                ColumnLayout {
                                    visible: root.screenTimeSort === "total"
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        text: "Total ever"
                                        color: root.tc(0.4)
                                        font.pixelSize: 9; font.family: root.fontFamily
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        text: root.totalPcUptimeStr
                                        color: root.textColor
                                        font.pixelSize: 13; font.family: root.fontFamily
                                        font.weight: Font.SemiBold
                                    }
                                }

                                Rectangle {
                                    width: 1; height: 28
                                    color: root.tc(0.1)
                                }

                                // Refresh button
                                Rectangle {
                                    width: 28; height: 28; radius: 14
                                    color: refreshStHover.containsMouse ? root.tc(0.12) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    HoverHandler { id: refreshStHover }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "↺"
                                        color: root.tc(0.5)
                                        font.pixelSize: 14; font.family: root.fontFamily
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.refreshPlaytimeModel()
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: root.tc(0.07)
                            }

                            // ── App list ───────────────────────────────────────────
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: playtimeModel.count === 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "No app usage recorded yet"
                                    color: root.tc(0.3)
                                    font.pixelSize: 12; font.family: root.fontFamily
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: playtimeModel.count > 0

                                // find max value for bar scaling
                                property real maxMs: {
                                    var mx = 1
                                    for (var i = 0; i < playtimeModel.count; i++) {
                                        var e = playtimeModel.get(i)
                                        var v = root.screenTimeSort === "session" ? e.sessionMs : e.totalMs
                                        if (v > mx) mx = v
                                    }
                                    return mx
                                }

                                ListView {
                                    id: playtimeList
                                    anchors.fill: parent
                                    model: playtimeModel
                                    clip: true
                                    spacing: 0
                                    boundsBehavior: Flickable.StopAtBounds

                                    delegate: Item {
                                        width: playtimeList.width
                                        height: 56

                                        required property string appClass
                                        required property string displayName
                                        required property real   totalMs
                                        required property real   sessionMs
                                        required property string icon
                                        required property int    index

                                        property real primaryMs:   root.screenTimeSort === "session" ? sessionMs   : totalMs
                                        property real secondaryMs: root.screenTimeSort === "session" ? totalMs     : sessionMs
                                        property real barFraction: primaryMs / Math.max(1, playtimeList.parent.maxMs)

                                        HoverHandler { id: ptHover }

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 3
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            radius: 10
                                            color: root.tc(ptHover.containsMouse ? 0.07 : 0)
                                            Behavior on color { ColorAnimation { duration: 80 } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 8
                                            anchors.bottomMargin: 8
                                            spacing: 10

                                            // App icon
                                            Item {
                                                width: 32; height: 32
                                                Layout.alignment: Qt.AlignVCenter

                                                Rectangle {
                                                    anchors.fill: parent; radius: 8
                                                    color: root.tc(0.08)
                                                }

                                                Image {
                                                    id: appIcon
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    source: {
                                                        var ic = icon
                                                        if (!ic || ic === "") return ""
                                                        if (ic.startsWith("/")) return "file://" + ic
                                                        if (ic.startsWith("file://")) return ic
                                                        return "image://theme/" + ic
                                                    }
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true; mipmap: true; cache: false
                                                    visible: source !== "" && status === Image.Ready
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: appClass.length > 0 ? appClass[0].toUpperCase() : "?"
                                                    color: root.textColor
                                                    font.pixelSize: 14; font.family: root.fontFamily
                                                    font.weight: Font.Bold
                                                    visible: icon === "" || appIcon.status !== Image.Ready
                                                }
                                            }

                                            // Name + bar
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 4

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 4

                                                    Text {
                                                        text: displayName
                                                        color: root.textColor
                                                        font.pixelSize: 11; font.family: root.fontFamily
                                                        font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }

                                                    Text {
                                                        text: root.fmtDuration(primaryMs)
                                                        color: root.textColor
                                                        font.pixelSize: 12; font.family: root.fontFamily
                                                        font.weight: Font.SemiBold
                                                    }
                                                }

                                                // Bar
                                                Item {
                                                    Layout.fillWidth: true
                                                    height: 5

                                                    Rectangle {
                                                        anchors.fill: parent; radius: 3
                                                        color: root.tc(0.1)
                                                    }
                                                    Rectangle {
                                                        width: parent.width * barFraction
                                                        height: parent.height; radius: 3
                                                        color: root.accentColor
                                                        Behavior on width { SmoothedAnimation { duration: 200 } }
                                                    }
                                                }

                                                // Secondary label
                                                Text {
                                                    text: root.screenTimeSort === "session"
                                                          ? ("Total: " + root.fmtDuration(secondaryMs))
                                                          : ("Session: " + root.fmtDuration(secondaryMs))
                                                    color: root.tc(0.35)
                                                    font.pixelSize: 9; font.family: root.fontFamily
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 12; anchors.rightMargin: 12
                                            height: 1; color: root.tc(0.05)
                                            visible: index < playtimeModel.count - 1
                                        }
                                    }
                                }

                                // Scrollbar
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 3
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 3; radius: 1.5
                                    color: root.tc(0.18)
                                    visible: playtimeList.contentHeight > playtimeList.height
                                    opacity: playtimeList.moving ? 1 : 0.5
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Rectangle {
                                        width: parent.width; radius: parent.radius
                                        color: root.tc(0.7)
                                        height: playtimeList.height > 0
                                            ? Math.max(20, playtimeList.height * playtimeList.height / Math.max(1, playtimeList.contentHeight))
                                            : 0
                                        y: playtimeList.contentHeight > playtimeList.height
                                            ? playtimeList.contentY * (playtimeList.height - height) / (playtimeList.contentHeight - playtimeList.height)
                                            : 0
                                    }
                                }
                            }
                        }
                    }
                    // ── Settings Panel ─────────────────────────────────────────────
                    Item {
                        anchors.fill: parent
                        opacity: root.islandState === "settings" ? 1 : 0
                        visible: opacity > 0
                        clip: true
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        TapHandler {
                            onTapped: root.islandState = "controlPanel"
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.topMargin: 0
                            anchors.leftMargin: 0
                            anchors.rightMargin: 0
                            anchors.bottomMargin: 10
                            spacing: 0

                            // Header
                            Item {
                                Layout.fillWidth: true
                                height: 52

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 36; height: 4; radius: 2
                                    color: root.tc(0.25)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.topMargin: 16
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 10
                                    anchors.bottomMargin: 6

                                    Text {
                                        text: "Settings"
                                        color: root.textColor
                                        font.pixelSize: 15; font.weight: Font.SemiBold
                                        font.family: root.fontFamily
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        width: 32; height: 32; radius: 10
                                        color: root.tc(0.07)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "\u00d7"
                                            color: root.tc(0.5)
                                            font.pixelSize: 16; font.family: root.fontFamily
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.islandState = "controlPanel"
                                        }
                                    }
                                }
                            }

                            // Scrollable content
                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                contentHeight: settingsCol.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                ColumnLayout {
                                    id: settingsCol
                                    width: parent.width
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    // ── Theme ──────────────────────────────────────
                                    Text {
                                        Layout.topMargin: 4
                                        text: "THEME"
                                        color: root.tc(0.38)
                                        font.pixelSize: 10; font.weight: Font.Medium
                                        font.family: root.fontFamily
                                        font.letterSpacing: 1.0
                                    }

                                    // Pill colour
                                    Rectangle {
                                        Layout.fillWidth: true; height: 44; radius: 14
                                        color: root.tc(0.07)
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                                            Text { text: "Pill colour"; color: root.textColor; font.pixelSize: 12; font.weight: Font.Medium; font.family: root.fontFamily; Layout.fillWidth: true }
                                            Rectangle {
                                                width: 28; height: 28; radius: 8
                                                color: root.pillColor; border.color: root.tc(0.25); border.width: 1
                                                MouseArea { anchors.fill: parent; onClicked: { root.colorWheelTarget = "pill"; root.colorWheelOpen = true } }
                                            }
                                        }
                                    }

                                    // Accent colour
                                    Rectangle {
                                        Layout.fillWidth: true; height: 44; radius: 14
                                        color: root.tc(0.07)
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                                            Text { text: "Accent colour"; color: root.textColor; font.pixelSize: 12; font.weight: Font.Medium; font.family: root.fontFamily; Layout.fillWidth: true }
                                            Rectangle {
                                                width: 28; height: 28; radius: 8
                                                color: root.accentColor; border.color: root.tc(0.25); border.width: 1
                                                MouseArea { anchors.fill: parent; onClicked: { root.colorWheelTarget = "accent"; root.colorWheelOpen = true } }
                                            }
                                        }
                                    }

                                    // Text colour
                                    Rectangle {
                                        Layout.fillWidth: true; height: 44; radius: 14
                                        color: root.tc(0.07)
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                                            Text { text: "Text colour"; color: root.textColor; font.pixelSize: 12; font.weight: Font.Medium; font.family: root.fontFamily; Layout.fillWidth: true }
                                            Rectangle {
                                                width: 28; height: 28; radius: 8
                                                color: root.textColor; border.color: root.tc(0.25); border.width: 1
                                                MouseArea { anchors.fill: parent; onClicked: { root.colorWheelTarget = "text"; root.colorWheelOpen = true } }
                                            }
                                        }
                                    }

                                    // Pill opacity
                                    Rectangle {
                                        Layout.fillWidth: true; height: 52; radius: 14
                                        color: root.tc(0.07)

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14; anchors.rightMargin: 14
                                            anchors.topMargin: 8; anchors.bottomMargin: 8
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { text: "Opacity"; color: root.textColor; font.pixelSize: 12; font.weight: Font.Medium; font.family: root.fontFamily; Layout.fillWidth: true }
                                                Text { text: Math.round(root.pillOpacity * 100) + "%"; color: root.tc(0.4); font.pixelSize: 11; font.family: root.fontFamily }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true; height: 6; radius: 3
                                                color: root.tc(0.15)
                                                Rectangle {
                                                    width: parent.width * root.pillOpacity
                                                    height: parent.height; radius: parent.radius
                                                    color: root.accentColor
                                                    Behavior on width { NumberAnimation { duration: 80 } }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -8
                                                    onPositionChanged: (mouse) => {
                                                        if (pressed) {
                                                            var v = Math.max(0.1, Math.min(1.0, mouse.x / width))
                                                            root.pillOpacity = Math.round(v * 10) / 10
                                                        }
                                                    }
                                                    onReleased: root.saveConfig()
                                                    onClicked: (mouse) => {
                                                        var v = Math.max(0.1, Math.min(1.0, mouse.x / width))
                                                        root.pillOpacity = Math.round(v * 10) / 10
                                                        root.saveConfig()
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Font family
                                    Rectangle {
                                        Layout.fillWidth: true; height: 52; radius: 14
                                        color: root.tc(0.07)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14; anchors.rightMargin: 14
                                            spacing: 10

                                            Text { text: ""; color: root.tc(0.65); font.pixelSize: 16; font.family: root.fontFamily }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 1
                                                Text { text: "Font family"; color: root.textColor; font.pixelSize: 12; font.weight: Font.Medium; font.family: root.fontFamily }
                                                Text { text: "Leave blank for system default"; color: root.tc(0.35); font.pixelSize: 10; font.family: root.fontFamily }
                                            }
                                            Rectangle {
                                                width: 110; height: 30; radius: 9
                                                color: root.tc(0.12)
                                                TextInput {
                                                    id: fontFamilyInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    text: root.fontFamily
                                                    color: root.textColor
                                                    font.pixelSize: 11
                                                    selectByMouse: true
                                                    onEditingFinished: {
                                                        root.fontFamily = text.trim()
                                                        root.saveConfig()
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ── Notch Layout ───────────────────────────────
                                    Text {
                                        Layout.topMargin: 8
                                        text: "NOTCH LAYOUT"
                                        color: root.tc(0.38)
                                        font.pixelSize: 10; font.weight: Font.Medium
                                        font.family: root.fontFamily
                                        font.letterSpacing: 1.0
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: notchLayoutEdit.implicitHeight + 24
                                        radius: 14
                                        color: root.tc(0.07)

                                        TextEdit {
                                            id: notchLayoutEdit
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 12
                                            color: root.textColor
                                            font.pixelSize: 11; font.family: "monospace"
                                            wrapMode: TextEdit.Wrap
                                            selectByMouse: true
                                            selectedTextColor: "#000000"
                                            selectionColor: root.tc(0.5)

                                            text: root.notchLayoutRaw

                                            onEditingFinished: {
                                                var raw = text
                                                var layout = []
                                                var ls = raw.split("\n")
                                                for (var i = 0; i < ls.length; i++) {
                                                    var line = ls[i].trim()
                                                    if (line === "" || line[0] === "#") continue
                                                    var m = line.match(/\[([^\]]*)\]/)
                                                    if (!m) continue
                                                    var widgets = m[1].split(",").map(function(s) { return s.trim() }).filter(function(s) { return s !== "" })
                                                    if (widgets.length > 0) layout.push(widgets)
                                                }
                                                if (layout.length > 0) {
                                                    root.notchLayoutRaw = raw
                                                    root.notchLayout = layout
                                                    root.saveNotchLayout(raw)
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Widgets: Date, Time, Cava, Workspaces, Timer, SysOverview — one line per notch page"
                                        color: root.tc(0.28)
                                        font.pixelSize: 9; font.family: root.fontFamily
                                        wrapMode: Text.WordWrap
                                    }

                                    // ── Interactions ───────────────────────────────
                                    Text {
                                        Layout.topMargin: 8
                                        text: "INTERACTIONS"
                                        color: root.tc(0.38)
                                        font.pixelSize: 10; font.weight: Font.Medium
                                        font.family: root.fontFamily
                                        font.letterSpacing: 1.0
                                    }

                                    Repeater {
                                        model: [
                                            { label: "clickLeft",     sub: "Left-click on island"   },
                                            { label: "clickRight",    sub: "Right-click on island"  },
                                            { label: "clickMiddle",   sub: "Middle-click on island" },
                                            { label: "dragDown",      sub: "Drag down from island"  },
                                            { label: "dragDownRight", sub: "Drag down-right"        },
                                        ]
                                        delegate: Rectangle {
                                            id: bRow
                                            required property var modelData
                                            Layout.fillWidth: true; height: 52; radius: 14
                                            color: root.tc(0.07)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 14; anchors.rightMargin: 14
                                                spacing: 10

                                                Text {
                                                    text: bRow.modelData.label
                                                    color: root.tc(0.45)
                                                    font.pixelSize: 10; font.family: "monospace"
                                                    Layout.minimumWidth: 110
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 30; radius: 9
                                                    color: root.tc(0.12)

                                                    TextInput {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8; anchors.rightMargin: 8
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        color: root.textColor
                                                        font.pixelSize: 11; font.family: "monospace"
                                                        selectByMouse: true
                                                        selectedTextColor: "#000000"
                                                        selectionColor: root.tc(0.5)

                                                        text: {
                                                            var p = bRow.modelData.label
                                                            if      (p === "clickLeft")     return root.clickLeft
                                                            else if (p === "clickRight")    return root.clickRight
                                                            else if (p === "clickMiddle")   return root.clickMiddle
                                                            else if (p === "dragDown")      return root.dragDown
                                                            else                            return root.dragDownRight
                                                        }

                                                        onEditingFinished: {
                                                            var v = text.trim()
                                                            var p = bRow.modelData.label
                                                            if      (p === "clickLeft")     root.clickLeft     = v
                                                            else if (p === "clickRight")    root.clickRight    = v
                                                            else if (p === "clickMiddle")   root.clickMiddle   = v
                                                            else if (p === "dragDown")      root.dragDown      = v
                                                            else                            root.dragDownRight = v
                                                            root.saveConfig()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Item { height: 8 }
                                }
                            }
                        }
                    }

                    // ── End Screen Time Panel ──────────────────────────────────────

                Item {
                    id: wifiSidePanel
                    visible: root.islandState === "controlPanel"
                    width: 204
                    height: pillWrapper.controlPanelHeight

                    x: root.wifiNetworksOpen
                        ? -(width + 8)
                        : 0
                    y: 0
                    opacity: root.wifiNetworksOpen ? 1 : 0

                    Behavior on x       { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        color: root.pillColor
                        opacity: root.pillOpacity
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Wi-Fi"
                                color: root.textColor
                                font.pixelSize: 12; font.family: root.fontFamily
                                font.weight: Font.SemiBold
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: wifiScanProc.running ? "…" : "↺"
                                color: root.tc(0.5)
                                font.pixelSize: 11; font.family: root.fontFamily
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    onClicked: {
                                        wifiNetworkModel.clear()
                                        wifiScanProc.running = false
                                        wifiScanProc.running = true
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: root.tc(0.07)
                        }

                        Text {
                            visible: wifiNetworkModel.count === 0
                            text: wifiScanProc.running ? "Scanning…"
                                  : (root.wifiEnabled ? "No networks found" : "Wi-Fi is off")
                            color: root.textColor
                            font.pixelSize: 10; font.family: root.fontFamily
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Item {
                            visible: wifiNetworkModel.count === 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }

                        Flickable {
                            visible: wifiNetworkModel.count > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentHeight: wifiListColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: wifiListColumn
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: wifiNetworkModel
                                    delegate: Item {
                                        required property string ssid
                                        required property string service
                                        required property int    strength
                                        required property string security
                                        required property bool   connected

                                        width: wifiListColumn.width
                                        height: 42

                                        HoverHandler { id: netHover }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 8
                                            color: root.tc(netHover.containsMouse ? 0.07 : 0)
                                            Behavior on color { ColorAnimation { duration: 80 } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 8

                                            Item {
                                                width: 16; height: 14
                                                Layout.alignment: Qt.AlignVCenter

                                                Rectangle { x: 0;  y: 10; width: 3; height: 4;  radius: 1; color: root.tc(strength >= 20 ? 0.75 : 0.2) }
                                                Rectangle { x: 4;  y: 7;  width: 3; height: 7;  radius: 1; color: root.tc(strength >= 40 ? 0.75 : 0.2) }
                                                Rectangle { x: 8;  y: 4;  width: 3; height: 10; radius: 1; color: root.tc(strength >= 60 ? 0.75 : 0.2) }
                                                Rectangle { x: 12; y: 0;  width: 3; height: 14; radius: 1; color: root.tc(strength >= 80 ? 0.75 : 0.2) }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1

                                                Text {
                                                    text: ssid
                                                    color: connected ? root.textColor : root.tc(0.8)
                                                    font.pixelSize: 11; font.family: root.fontFamily
                                                    font.weight: connected ? Font.SemiBold : Font.Normal
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                }
                                                Text {
                                                    text: connected
                                                          ? "Connected"
                                                          : (root.wifiConnectingTo === ssid
                                                             ? "Connecting…"
                                                             : (security !== "none" ? "🔒 " + security : "Open"))
                                                    color: connected ? root.tc(0.65) : root.tc(0.35)
                                                    font.pixelSize: 9; font.family: root.fontFamily
                                                }
                                            }

                                            Rectangle {
                                                width: connected ? 26 : 0
                                                height: 26; radius: 13
                                                color: root.tc(0.1)
                                                visible: connected
                                                Behavior on width { SmoothedAnimation { duration: 150 } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✕"
                                                    color: root.tc(0.55)
                                                    font.pixelSize: 10; font.family: root.fontFamily
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        wifiDisconnectProc.targetService = service
                                                        wifiDisconnectProc.running = false
                                                        wifiDisconnectProc.running = true
                                                        root.wifiConnectedSsid = ""

                                                        wifiNetworkModel.clear()
                                                        wifiScanProc.running = false
                                                        wifiScanProc.running = true
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: !connected && root.wifiConnectingTo === ""
                                            onClicked: {
                                                root.wifiConnectingTo = ssid
                                                wifiConnectProc.targetService = service
                                                wifiConnectProc.running = false
                                                wifiConnectProc.running = true
                                            }
                                        }

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 6; anchors.rightMargin: 6
                                            height: 1
                                            color: root.tc(0.05)
                                            visible: index < wifiNetworkModel.count - 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: audioSidePanel
                    visible: root.islandState === "controlPanel"
                    width: 188
                    height: pillWrapper.controlPanelHeight

                    x: root.soundAppsOpen
                        ? pillWrapper.width + 8
                        : pillWrapper.width
                    y: 0
                    opacity: root.soundAppsOpen ? 1 : 0

                    Behavior on x       { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        color: root.pillColor
                        opacity: root.pillOpacity
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "‹"
                                color: root.tc(0.55)
                                font.pixelSize: 16; font.family: root.fontFamily
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.soundAppsOpen = false
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "Apps"
                                color: root.textColor
                                font.pixelSize: 12; font.family: root.fontFamily
                                font.weight: Font.Medium
                            }
                        }

                        Text {
                            visible: appVolumeModel.count === 0
                            text: "No active audio apps"
                            color: root.tc(0.4)
                            font.pixelSize: 10; font.family: root.fontFamily
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Flickable {
                            visible: appVolumeModel.count > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentHeight: appListColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: appListColumn
                                width: parent.width
                                spacing: 10

                                Repeater {
                                    model: appVolumeModel
                                    delegate: ColumnLayout {
                                        required property int nodeId
                                        required property string appName
                                        required property real appVolume
                                        width: appListColumn.width
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: appName
                                                color: root.tc(0.85)
                                                font.pixelSize: 10; font.family: root.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: Math.round(appVolume * 100) + "%"
                                                color: root.tc(0.45)
                                                font.pixelSize: 9; font.family: root.fontFamily
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            height: 18
                                            readonly property real pad: 7
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: parent.pad; width: parent.width - parent.pad * 2
                                                height: 5; radius: 3
                                                color: root.tc(0.11)
                                                Rectangle {
                                                    width: parent.width * appVolume
                                                    height: parent.height
                                                    radius: parent.radius
                                                    color: root.textColor
                                                }
                                            }
                                            Rectangle {
                                                readonly property real pad: parent.pad
                                                readonly property real trackW: parent.width - pad * 2
                                                x: pad + trackW * appVolume - width / 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 14; height: 14; radius: 7
                                                color: root.textColor
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                readonly property real pad: parent.pad
                                                function setVol(v) {
                                                    v = Math.max(0, Math.min(1, v))
                                                    appVolumeSetter.targetNode = nodeId
                                                    appVolumeSetter.targetVol  = v
                                                    appVolumeSetter.running = false
                                                    appVolumeSetter.running = true
                                                    for (var i = 0; i < appVolumeModel.count; ++i) {
                                                        if (appVolumeModel.get(i).nodeId === nodeId) {
                                                            appVolumeModel.setProperty(i, "appVolume", v)
                                                            break
                                                        }
                                                    }
                                                }
                                                onClicked:         mouse => setVol((mouse.x - pad) / (width - pad * 2))
                                                onPositionChanged: mouse => { if (pressed) setVol((mouse.x - pad) / (width - pad * 2)) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── VPN Location side panel ──────────────────────────────
                Item {
                    id: vpnLocationPanel
                    visible: root.islandState === "controlPanel"
                    width: 196
                    height: pillWrapper.controlPanelHeight

                    x: root.vpnLocationsOpen
                        ? pillWrapper.width + 8
                        : pillWrapper.width
                    y: 0
                    opacity: root.vpnLocationsOpen ? 1 : 0

                    Behavior on x       { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    onVisibleChanged: { if (!visible) root.vpnLocationsOpen = false }

                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        color: root.pillColor
                        opacity: root.pillOpacity
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 6

                        // Header
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "‹"
                                color: root.tc(0.55)
                                font.pixelSize: 16; font.family: root.fontFamily
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.vpnLocationsOpen = false
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "Location"
                                color: root.textColor
                                font.pixelSize: 12; font.family: root.fontFamily
                                font.weight: Font.Medium
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: root.tc(0.07)
                        }

                        Text {
                            visible: vpnLocationModel.count === 0
                            text: vpnLocationLoader.running ? "Loading…" : "No locations"
                            color: root.tc(0.4)
                            font.pixelSize: 10; font.family: root.fontFamily
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Flickable {
                            visible: vpnLocationModel.count > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentHeight: vpnLocColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: vpnLocColumn
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: vpnLocationModel
                                    delegate: Item {
                                        required property string locCountry
                                        required property string locCountryCode
                                        required property string locCity
                                        required property string locCityCode

                                        width: vpnLocColumn.width
                                        height: 44

                                        property bool isCurrent: {
                                            var loc = root.vpnLocation.toLowerCase()
                                            return loc.indexOf(locCity.toLowerCase()) >= 0
                                                || loc.indexOf(locCountry.toLowerCase()) >= 0
                                        }

                                        HoverHandler { id: locHover }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 8
                                            color: isCurrent
                                                ? Qt.rgba(0.18, 0.78, 0.45, 0.15)
                                                : root.tc(locHover.containsMouse ? 0.07 : 0)
                                            Behavior on color { ColorAnimation { duration: 80 } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 6

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: locCity
                                                    color: isCurrent ? "#2EC86E" : root.textColor
                                                    font.pixelSize: 11; font.family: root.fontFamily
                                                    font.weight: isCurrent ? Font.SemiBold : Font.Normal
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                }
                                                Text {
                                                    text: locCountry
                                                    color: root.tc(0.38)
                                                    font.pixelSize: 9; font.family: root.fontFamily
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            // Active indicator dot
                                            Rectangle {
                                                width: 6; height: 6; radius: 3
                                                color: "#2EC86E"
                                                visible: isCurrent
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                vpnLocationSetProc.countryCode = locCountryCode
                                                vpnLocationSetProc.cityCode    = locCityCode
                                                vpnLocationSetProc.running = false
                                                vpnLocationSetProc.running = true
                                                root.vpnLocationsOpen = false
                                                // Optimistically update location label
                                                root.vpnLocation = locCity + ", " + locCountry
                                            }
                                        }

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 6; anchors.rightMargin: 6
                                            height: 1
                                            color: root.tc(0.05)
                                            visible: index < vpnLocationModel.count - 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Colour wheel side panel ──────────────────────────────
                Item {
                    id: colorWheelPanel
                    visible: root.islandState === "settings"
                    width: 240
                    height: 300

                    x: root.colorWheelOpen
                        ? pillWrapper.width + 8
                        : pillWrapper.width
                    y: 0
                    opacity: root.colorWheelOpen ? 1 : 0

                    Behavior on x       { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    // Background pill (matches other panels)
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        color: root.pillColor
                        opacity: root.pillOpacity
                    }

                    // HSV state
                    QtObject {
                        id: cw
                        property real hue: 0
                        property real sat: 0
                        property real val: 1

                        function load() {
                            var hex = root.colorWheelTarget === "pill"   ? root.pillColor
                                    : root.colorWheelTarget === "accent" ? root.accentColor
                                    : root.textColor
                            var r = parseInt(hex.slice(1,3),16)/255
                            var g = parseInt(hex.slice(3,5),16)/255
                            var b = parseInt(hex.slice(5,7),16)/255
                            var mx = Math.max(r,g,b), mn = Math.min(r,g,b), d = mx-mn
                            var h = 0
                            if (d > 0) {
                                if      (mx===r) h=((g-b)/d+6)%6
                                else if (mx===g) h=(b-r)/d+2
                                else             h=(r-g)/d+4
                                h/=6
                            }
                            hue = h; sat = mx>0?d/mx:0; val = mx
                        }

                        function toHex() {
                            var h=hue,s=sat,v=val
                            var i=Math.floor(h*6),f=h*6-i
                            var p=v*(1-s),q=v*(1-f*s),t=v*(1-(1-f)*s)
                            var r,g,b
                            switch(i%6){case 0:r=v;g=t;b=p;break;case 1:r=q;g=v;b=p;break;
                                        case 2:r=p;g=v;b=t;break;case 3:r=p;g=q;b=v;break;
                                        case 4:r=t;g=p;b=v;break;default:r=v;g=p;b=q;break}
                            function h2(n){var x=Math.round(n*255).toString(16);return x.length<2?"0"+x:x}
                            return "#"+h2(r)+h2(g)+h2(b)
                        }

                        function apply() {
                            var hex = toHex()
                            if      (root.colorWheelTarget==="pill")   root.pillColor   = hex
                            else if (root.colorWheelTarget==="accent") root.accentColor = hex
                            else                                       root.textColor   = hex
                            root.saveConfig()
                        }
                    }

                    // Reload HSV whenever the panel opens or target changes
                    onVisibleChanged: if (visible && root.colorWheelOpen) cw.load()
                    Connections {
                        target: root
                        function onColorWheelOpenChanged() { if (root.colorWheelOpen) cw.load() }
                        function onColorWheelTargetChanged() { if (root.colorWheelOpen) cw.load() }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        // Header row
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "‹"
                                color: root.tc(0.55)
                                font.pixelSize: 16; font.family: root.fontFamily
                                MouseArea { anchors.fill: parent; onClicked: root.colorWheelOpen = false }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.colorWheelTarget === "pill"   ? "Pill colour"
                                    : root.colorWheelTarget === "accent" ? "Accent colour"
                                    : "Text colour"
                                color: root.textColor
                                font.pixelSize: 12; font.family: root.fontFamily
                                font.weight: Font.Medium
                            }
                        }

                        // Hue wheel + SV square
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            width: 170; height: 170

                            // Hue ring
                            Repeater {
                                model: 360
                                delegate: Rectangle {
                                    required property int index
                                    x: 85 - width/2  + 72 * Math.cos((index - 90) * Math.PI / 180)
                                    y: 85 - height/2 + 72 * Math.sin((index - 90) * Math.PI / 180)
                                    width: 8; height: 8; radius: 4
                                    color: Qt.hsva(index / 360, 1, 1, 1)
                                }
                            }

                            // Hue ring mouse — z:0, only acts outside the SV square (dist > 44)
                            MouseArea {
                                anchors.fill: parent
                                z: 0
                                function pickHue(mx, my) {
                                    var dx = mx - 85, dy = my - 85
                                    var dist = Math.sqrt(dx*dx + dy*dy)
                                    if (dist > 44) {
                                        var angle = Math.atan2(dy, dx) / (2 * Math.PI) + 0.25
                                        cw.hue = (angle + 1) % 1
                                        cw.apply()
                                    }
                                }
                                onClicked:         mouse => pickHue(mouse.x, mouse.y)
                                onPositionChanged: mouse => { if (pressed) pickHue(mouse.x, mouse.y) }
                            }

                            // Hue handle (above ring mouse, below SV)
                            Rectangle {
                                x: 85 - 6 + 72 * Math.cos((cw.hue * 360 - 90) * Math.PI / 180)
                                y: 85 - 6 + 72 * Math.sin((cw.hue * 360 - 90) * Math.PI / 180)
                                width: 12; height: 12; radius: 6
                                color: Qt.hsva(cw.hue, 1, 1, 1)
                                border.color: "white"; border.width: 2
                                z: 1
                            }

                            // SV square — z:2 so its MouseArea wins over the hue ring
                            Item {
                                x: 85 - 44; y: 85 - 44; width: 88; height: 88
                                z: 2

                                Rectangle { anchors.fill: parent; color: Qt.hsva(cw.hue, 0, 0, 1) }
                                Rectangle {
                                    anchors.fill: parent
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Qt.rgba(1,1,1,1) }
                                        GradientStop { position: 1.0; color: Qt.hsva(cw.hue,1,1,1) }
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Qt.rgba(0,0,0,0) }
                                        GradientStop { position: 1.0; color: Qt.rgba(0,0,0,1) }
                                    }
                                }
                                // Crosshair
                                Rectangle {
                                    x: cw.sat * parent.width - 5
                                    y: (1 - cw.val) * parent.height - 5
                                    width: 10; height: 10; radius: 5
                                    color: "transparent"
                                    border.color: "white"; border.width: 2
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    z: 3
                                    function pick(mx, my) {
                                        cw.sat = Math.max(0, Math.min(1, mx / width))
                                        cw.val = Math.max(0, Math.min(1, 1 - my / height))
                                        cw.apply()
                                    }
                                    onClicked:         mouse => pick(mouse.x, mouse.y)
                                    onPositionChanged: mouse => { if (pressed) pick(mouse.x, mouse.y) }
                                }
                            }
                        }

                        // Hex input row
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8

                            Rectangle {
                                width: 24; height: 24; radius: 7
                                color: cw.toHex()
                                border.color: root.tc(0.25); border.width: 1
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: 28; radius: 8
                                color: root.tc(0.12)
                                TextInput {
                                    id: cwHexInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: cw.toHex()
                                    color: root.textColor
                                    font.pixelSize: 11; font.family: "monospace"
                                    selectByMouse: true
                                    onEditingFinished: {
                                        var v = text.trim()
                                        if (/^#[0-9a-fA-F]{6}$/.test(v)) {
                                            var r=parseInt(v.slice(1,3),16)/255
                                            var g=parseInt(v.slice(3,5),16)/255
                                            var b=parseInt(v.slice(5,7),16)/255
                                            var mx=Math.max(r,g,b),mn=Math.min(r,g,b),d=mx-mn
                                            var h=0
                                            if(d>0){if(mx===r)h=((g-b)/d+6)%6;else if(mx===g)h=(b-r)/d+2;else h=(r-g)/d+4;h/=6}
                                            cw.hue=h; cw.sat=mx>0?d/mx:0; cw.val=mx
                                            cw.apply()
                                        } else {
                                            text = cw.toHex()
                                        }
                                    }
                                }
                            }
                        }

                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: 0
                    hoverEnabled: true
                    acceptedButtons: Qt.RightButton | Qt.MiddleButton
                    onContainsMouseChanged: {}
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            root.doClickAction(root.clickRight)
                        else if (mouse.button === Qt.MiddleButton)
                            root.doClickAction(root.clickMiddle)
                    }
                }
            }
            }
        }

    }
}
