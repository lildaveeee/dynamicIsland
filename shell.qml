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
        property string dragDown:    "appLauncher"

        function doClickAction(action) {
            if (action === "none" || action === "") return
            if (action === "appLauncher") {

                root.appLauncherQuery = ""
                appLauncherModel.clear()
                root.appLauncherOpen = true
                root.islandState = "appLauncher"
                appLauncherLoader.running = false
                appLauncherLoader.running = true
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
            command: ["bash", "-c",
                "FIFO=/tmp/quickshell-notif.fifo; " +
                "rm -f \"$FIFO\"; mkfifo \"$FIFO\"; " +
                "DIR=\"$HOME/.config/dunst\"; mkdir -p \"$DIR\"; " +

                "cat > \"$DIR/notify-hook.sh\" << 'HOOKEOF'\n" +
                "#!/bin/bash\n" +
                "ICON=\"$DUNST_ICON_PATH\"\n" +
                "# Resolve a bare icon name to a real file path.\n" +
                "# Strategy: prefer 48px PNG, then 32px, then any size, then SVG.\n" +
                "resolve_icon() {\n" +
                "  local name=\"$1\"\n" +
                "  local dirs=\"$HOME/.local/share/icons /usr/share/icons /usr/share/pixmaps\"\n" +
                "  # Try preferred sizes first: 48, 32, 64, 256, scalable\n" +
                "  for size in 48 32 64 128 256 22 16 scalable; do\n" +
                "    for base in $dirs; do\n" +
                "      for ext in png svg xpm; do\n" +
                "        local candidate\n" +
                "        # hicolor/<size>x<size>/apps/<name>.<ext>\n" +
                "        candidate=\"$base/hicolor/${size}x${size}/apps/${name}.${ext}\"\n" +
                "        [ -f \"$candidate\" ] && { echo \"$candidate\"; return; }\n" +
                "        # Any theme that has the right size subfolder\n" +
                "        for theme in Papirus Papirus-Dark breeze breeze-dark Adwaita hicolor; do\n" +
                "          candidate=\"$base/$theme/${size}x${size}/apps/${name}.${ext}\"\n" +
                "          [ -f \"$candidate\" ] && { echo \"$candidate\"; return; }\n" +
                "        done\n" +
                "      done\n" +
                "    done\n" +
                "    # scalable folder uses different naming\n" +
                "    for base in $dirs; do\n" +
                "      for theme in hicolor Papirus breeze Adwaita; do\n" +
                "        for ext in svg png; do\n" +
                "          local candidate=\"$base/$theme/scalable/apps/${name}.${ext}\"\n" +
                "          [ -f \"$candidate\" ] && { echo \"$candidate\"; return; }\n" +
                "        done\n" +
                "      done\n" +
                "    done\n" +
                "  done\n" +
                "  # Broad fallback: find anywhere under icon dirs\n" +
                "  find $dirs /usr/share/pixmaps -type f \\\n" +
                "    \\( -name \"${name}.png\" -o -name \"${name}.svg\" \\) \\\n" +
                "    2>/dev/null | head -1\n" +
                "}\n" +
                "if [ -n \"$ICON\" ] && [ \"${ICON#/}\" = \"$ICON\" ]; then\n" +
                "  # Bare icon name — resolve it\n" +
                "  RESOLVED=$(resolve_icon \"$ICON\")\n" +
                "  if [ -z \"$RESOLVED\" ]; then\n" +
                "    # Try lowercase app name as icon name\n" +
                "    ALT=$(echo \"$DUNST_APP_NAME\" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')\n" +
                "    RESOLVED=$(resolve_icon \"$ALT\")\n" +
                "  fi\n" +
                "  [ -n \"$RESOLVED\" ] && ICON=\"$RESOLVED\"\n" +
                "elif [ -z \"$ICON\" ] && [ -n \"$DUNST_APP_NAME\" ]; then\n" +
                "  # No icon at all — try to find one from the app name\n" +
                "  ALT=$(echo \"$DUNST_APP_NAME\" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')\n" +
                "  ICON=$(resolve_icon \"$ALT\")\n" +
                "fi\n" +
                "# Extract a URL from the notification body or summary.\n" +
                "# Priority: <a href=\"URL\">, bare https://, bare http://\n" +
                "extract_url() {\n" +
                "  local text=\"$1\"\n" +
                "  # href attribute in an anchor tag\n" +
                "  local u\n" +
                "  u=$(echo \"$text\" | grep -oP 'href=[\"\\x27]\\K[^\"\\x27]+' | head -1)\n" +
                "  [ -n \"$u\" ] && { echo \"$u\"; return; }\n" +
                "  # bare URL starting with https:// or http://\n" +
                "  u=$(echo \"$text\" | grep -oP 'https?://[^\\s<>\"\\x27]+' | head -1)\n" +
                "  [ -n \"$u\" ] && { echo \"$u\"; return; }\n" +
                "}\n" +
                "NOTIF_URL=$(printf '%s' \"$DUNST_URLS\" | head -1 | tr -d '\\r')\n" +
                "[ -z \"$NOTIF_URL\" ] && NOTIF_URL=$(extract_url \"$DUNST_BODY\")\n" +
                "[ -z \"$NOTIF_URL\" ] && NOTIF_URL=$(extract_url \"$DUNST_SUMMARY\")\n" +
                "printf '%s\\x1f%s\\x1f%s\\x1f%s\\x1f%s\\x1f%s\\n' \"$DUNST_SUMMARY\" \"$DUNST_BODY\" \"$DUNST_APP_NAME\" \"$ICON\" \"$DUNST_DESKTOP_ENTRY\" \"$NOTIF_URL\" > /tmp/quickshell-notif.fifo\n" +
                "HOOKEOF\n" +
                "chmod +x \"$DIR/notify-hook.sh\"; " +

                "RC=\"$HOME/.config/dunst/dunstrc\"; " +
                "mkdir -p \"$(dirname \"$RC\")\"; " +
                "[ ! -f \"$RC\" ] && cp /etc/dunst/dunstrc \"$RC\" 2>/dev/null || touch \"$RC\"; " +
                "if ! grep -q 'notify-hook' \"$RC\"; then " +
                "  sed -i '/^\\[global\\]/a script = ~/.config/dunst/notify-hook.sh' \"$RC\"; " +
                "fi; " +
                "add_or_replace() { " +
                "  local key=\"$1\" val=\"$2\"; " +
                "  if grep -qE \"^\\s*${key}\\s*=\" \"$RC\"; then " +
                "    sed -i \"s|^\\s*${key}\\s*=.*|    ${key} = ${val}|\" \"$RC\"; " +
                "  else " +
                "    sed -i \"/^\\[global\\]/a \\    ${key} = ${val}\" \"$RC\"; " +
                "  fi; " +
                "}; " +
                "add_or_replace offset            '0x-2000'; " +
                "add_or_replace transparency      '100'; " +
                "add_or_replace width             '0'; " +
                "add_or_replace height            '0'; " +
                "add_or_replace always_run_script 'true'; " +
                "dunstctl reload 2>/dev/null || true; " +
                "dunstctl history-clear 2>/dev/null || true; " +
                "exec tail -f \"$FIFO\""
            ]
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

        Process { id: historySaveProcess; command: [] }

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
            historySaveProcess.command = ["bash", "-c",
                "mkdir -p \"$HOME/.local/share/quickshell\" && " +
                "printf '%s' " + JSON.stringify(payload) +
                " > \"$HOME/.local/share/quickshell/notif-history.ndjson\""]
            historySaveProcess.running = true
        }

        Process {
            id: historyLoadProcess
            command: ["bash", "-c",
                "f=\"$HOME/.local/share/quickshell/notif-history.ndjson\"; " +
                "[ -f \"$f\" ] && cat \"$f\" || true"]
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
            command: ["bash", "-c",
                "resolve_icon() {\n" +
                "  local name=\"$1\"\n" +
                "  [ -z \"$name\" ] && return\n" +
                "  if [ \"${name#/}\" != \"$name\" ]; then [ -f \"$name\" ] && echo \"$name\"; return; fi\n" +
                "  local dirs=\"$HOME/.local/share/icons /usr/share/icons /usr/share/pixmaps\"\n" +
                "  for size in 48 32 64 128 256 22 16; do\n" +
                "    for theme in hicolor Papirus Papirus-Dark breeze breeze-dark Adwaita; do\n" +
                "      for base in $dirs; do\n" +
                "        for ext in png svg xpm; do\n" +
                "          local c=\"$base/$theme/${size}x${size}/apps/${name}.${ext}\"\n" +
                "          [ -f \"$c\" ] && { echo \"$c\"; return; }\n" +
                "        done\n" +
                "      done\n" +
                "    done\n" +
                "    for theme in hicolor Papirus breeze Adwaita; do\n" +
                "      for base in $dirs; do\n" +
                "        for ext in svg png; do\n" +
                "          local c=\"$base/$theme/scalable/apps/${name}.${ext}\"\n" +
                "          [ -f \"$c\" ] && { echo \"$c\"; return; }\n" +
                "        done\n" +
                "      done\n" +
                "    done\n" +
                "  done\n" +
                "  for ext in png svg xpm; do\n" +
                "    local c=\"/usr/share/pixmaps/${name}.${ext}\"\n" +
                "    [ -f \"$c\" ] && { echo \"$c\"; return; }\n" +
                "  done\n" +
                "  find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons -type f \\( -name \"${name}.png\" -o -name \"${name}.svg\" \\) 2>/dev/null | head -1\n" +
                "}\n" +
                "find /usr/share/applications ~/.local/share/applications -name '*.desktop' 2>/dev/null | sort -u | " +
                "while IFS= read -r f; do " +
                "  name=$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-); " +
                "  exec=$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2- | sed 's/ *%[uUfFdDnNickvm]//g' | xargs); " +
                "  nodisp=$(grep -m1 '^NoDisplay=' \"$f\" | cut -d= -f2-); " +
                "  hidden=$(grep -m1 '^Hidden=' \"$f\" | cut -d= -f2-); " +
                "  icon=$(grep -m1 '^Icon=' \"$f\" | cut -d= -f2-); " +
                "  [ \"$nodisp\" = 'true' ] && continue; " +
                "  [ \"$hidden\" = 'true' ] && continue; " +
                "  [ -z \"$name\" ] && continue; " +
                "  [ -z \"$exec\" ] && continue; " +
                "  did=$(basename \"$f\" .desktop); " +
                "  resolved=$(resolve_icon \"$icon\"); " +
                "  [ -z \"$resolved\" ] && resolved=\"$icon\"; " +
                "  printf '%s\\x1f%s\\x1f%s\\x1f%s\\n' \"$name\" \"$exec\" \"$did\" \"$resolved\"; " +
                "done | sort -t$'\\x1f' -k1,1 -f"
            ]
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
            appLaunchProc.command = ["bash", "-c",
                "gtk-launch " + desktopId + " 2>/dev/null || " +
                "nohup sh -c " + JSON.stringify(exec) + " &>/dev/null &"
            ]
            appLaunchProc.running = false
            appLaunchProc.running = true
            root.islandState = "default"
            root.appLauncherQuery = ""
        }

        readonly property string favsFile: configDir + "/favourites"

        Process { id: favsSaveProc; running: false; command: [] }
        function saveFavourites() {
            favsSaveProc.command = ["bash", "-c",
                "mkdir -p " + JSON.stringify(root.configDir) + " && " +
                "printf '%s\\n' " + JSON.stringify(appFavourites.join("\n")) +
                " > " + JSON.stringify(root.favsFile)
            ]
            favsSaveProc.running = false
            favsSaveProc.running = true
        }

        Process {
            id: favsLoadProc
            running: true
            command: ["bash", "-c",
                "f=" + JSON.stringify(root.favsFile) + "; [ -f \"$f\" ] && cat \"$f\" || true"
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
        property bool soundAppsOpen: false
        property bool wifiNetworksOpen: false
        property bool silenced: false
        property string wifiConnectingTo: ""
        property string wifiConnectedSsid: ""
        ListModel { id: appVolumeModel }
        ListModel { id: wifiNetworkModel }
        ListModel { id: notifHistory }
        ListModel { id: appLauncherModel }

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
            command: ["bash", "-c",
                "CONFIG=$(mktemp /tmp/cava-XXXXXX.conf); " +
                "printf '[general]\\nbars=10\\nsleep_timer=2\\n" +
                "sensitivity=200\\nnoise_reduction=0.4\\n" +
                "[input]\\nmethod=pulse\\nsource=auto\\n" +
                "[output]\\nmethod=raw\\nraw_target=/dev/stdout\\n" +
                "data_format=ascii\\nascii_max_range=9\\n" +
                "bar_delimiter=59\\nframe_delimiter=10\\n' > \"$CONFIG\"; " +
                "exec cava -p \"$CONFIG\""
            ]
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
            command: ["bash", "-c",
                "for f in ~/.config/mpd/mpd.conf /etc/mpd.conf; do " +
                "  [ -f \"$f\" ] || continue; " +
                "  D=$(grep -Po '(?<=music_directory \")[^\"]+' \"$f\" 2>/dev/null | head -1); " +
                "  [ -z \"$D\" ] && D=$(grep -Po \"(?<=music_directory ')[^']+\" \"$f\" 2>/dev/null | head -1); " +
                "  [ -n \"$D\" ] && eval echo \"$D\" && exit 0; " +
                "done; " +
                "echo \"$HOME/Music\""
            ]
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

        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: statusPoller.running = true
        }
        Process {
            id: statusPoller
            running: false
            command: ["bash", "-c", "mpc status 2>/dev/null | grep -oP '\\[(playing|paused)\\]' | tr -d '[]'"]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var s = data.trim()
                    if (s !== "") root.isPlaying = (s === "playing")
                    statusPoller.running = false
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

        Process { id: mpcPrev;   running: false; command: ["mpc", "prev"] }
        Process { id: mpcToggle; running: false; command: ["mpc", "toggle"] }
        Process { id: mpcNext;   running: false; command: ["mpc", "next"] }

        Process {
            id: volumePoller
            running: true
            command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oP '[0-9]+\\.[0-9]+'"]
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
            command: ["bash", "-c",

                "wpctl status 2>/dev/null | sed -n '/Streams:/,/^[^ ]/p' | " +
                "grep -E '^[[:space:]]+[0-9]+\\.' | " +
                "sed -E 's/^[[:space:]]*([0-9]+)\\. (.*)$/\\1|\\2/' | " +
                "while IFS='|' read -r ID NAME; do " +

                "case \"$NAME\" in " +
                "  *pavucontrol*|*Pavucontrol*|*PulseAudio*|*pulseaudio*) continue;; " +
                "  *capture*|*Capture*|*record*|*Record*|*microphone*|*Microphone*) continue;; " +
                "esac; " +

                "MEDIA_CLASS=$(pw-cli info \"$ID\" 2>/dev/null | grep 'media.class' | grep -o '\"[^\"]*\"' | tail -1 | tr -d '\"'); " +
                "case \"$MEDIA_CLASS\" in " +
                "  Stream/Output/Audio) ;; " +
                "  *) continue;; " +
                "esac; " +
                "V=$(wpctl get-volume \"$ID\" 2>/dev/null | grep -oP '[0-9]+\\.[0-9]+' | head -1); " +
                "[ -n \"$V\" ] && printf '%s|%s|%s\\n' \"$ID\" \"$NAME\" \"$V\"; done"
            ]
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
            command: ["bash", "-c", "wpctl set-volume " + targetNode + " " + Math.round(targetVol * 100) + "%"]
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
            command: ["bash", "-c",
                "obs-cmd -w obsws://localhost:4455 recording status 2>/dev/null | grep -i 'active:' | grep -qi 'true' && echo 'recording' || echo 'stopped'"
            ]
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
            command: ["bash", "-c",
                "B=$(brightnessctl get 2>/dev/null); M=$(brightnessctl max 2>/dev/null); " +
                "[ -n \"$B\" ] && [ -n \"$M\" ] && echo \"scale=4; $B / $M\" | bc || echo '0.5'"
            ]
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
            command: ["bash", "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ " + Math.round(targetVol * 100) + "%"]
        }

        Process {
            id: brightnessSetter
            running: false
            property real targetBright: 0
            command: ["bash", "-c", "brightnessctl set " + Math.round(targetBright * 100) + "%"]
        }

	Process {
    	    id: wifiToggleProc
    	    running: false
    	    property bool enabling: true

    	    command: [
                "bash", "-c",
        	enabling
            	    ? "connmanctl enable wifi && connmanctl enable ethernet"
            	    : "connmanctl disable wifi && connmanctl disable ethernet"
    	    ]
	}

        Process {
            id: btToggleProc
            running: false
            property bool enabling: true
            command: ["bash", "-c", enabling ? "rfkill unblock bluetooth" : "rfkill block bluetooth"]
        }

        Process {
            id: wifiScanProc
            running: false
            command: ["bash", "-c",

                "connmanctl scan wifi 2>/dev/null; sleep 1; " +
                "connmanctl services 2>/dev/null | grep -E '^\\s+[\\*o ]' | " +
                "while read line; do " +
                "  NAME=$(echo \"$line\" | sed 's/^[[:space:]]*[\\*o ]\\?[[:space:]]*//' | sed 's/[[:space:]]*wifi_[a-f0-9_]*$//'); " +
                "  SERVICE=$(echo \"$line\" | grep -oP 'wifi_[a-f0-9_]+'); " +
                "  [ -z \"$SERVICE\" ] && continue; " +
                "  CONNECTED=$(echo \"$line\" | grep -c '^[[:space:]]\\*'); " +
                "  INFO=$(connmanctl services \"$SERVICE\" 2>/dev/null); " +
                "  STRENGTH=$(echo \"$INFO\" | grep -oP 'Strength = \\K[0-9]+' | head -1); " +
                "  SECURITY=$(echo \"$INFO\" | grep -oP 'Security = \\[ \\K[^\\]]+' | head -1); " +
                "  [ -z \"$STRENGTH\" ] && STRENGTH=0; " +
                "  [ -z \"$SECURITY\" ] && SECURITY=none; " +
                "  [ -z \"$NAME\" ] && NAME=\"Hidden network\"; " +
                "  printf '%s\\x1f%s\\x1f%s\\x1f%s\\x1f%s\\n' \"$NAME\" \"$SERVICE\" \"$STRENGTH\" \"$SECURITY\" \"$CONNECTED\"; " +
                "done"
            ]
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
            command: ["bash", "-c", "connmanctl connect \"" + targetService + "\" 2>&1 | tail -1"]
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
            command: ["bash", "-c", "connmanctl disconnect \"" + targetService + "\" 2>/dev/null"]
        }

        Process {
            id: screenshotProc
            running: false
            command: ["bash", "-c",
                "mkdir -p \"$HOME/Pictures/Snips\"; " +
                "ts=$(date +%Y%m%d-%H%M%S); " +
                "grim -g \"$(slurp)\" \"$HOME/Pictures/Snips/snip-$ts.png\" && " +
                "wl-copy < \"$HOME/Pictures/Snips/snip-$ts.png\" && " +
                "notify-send 'Snip saved & copied' \"$HOME/Pictures/Snips/snip-$ts.png\" || " +
                "notify-send 'Snip cancelled'"
            ]
        }

        property bool obsRecording: false
        Process {
            id: obsStartProc
            running: false
            command: ["bash", "-c",
                "pgrep -x obs > /dev/null || obs --minimize-to-tray &>/dev/null & " +
                "for i in $(seq 1 20); do " +
                "  obs-cmd -w obsws://localhost:4455 recording start 2>/dev/null && exit 0; " +
                "  sleep 0.5; " +
                "done"
            ]
        }
        Process {
            id: obsStopProc
            running: false
            command: ["obs-cmd", "-w", "obsws://localhost:4455", "recording", "stop"]
        }

        property bool vpnConnected: false
        Process {
            id: vpnStatusPoller
            running: true
            command: ["bash", "-c",
                "while true; do " +
                "  mullvad status 2>/dev/null | head -1 | grep -qi '^connected' && echo connected || echo disconnected; " +
                "  sleep 3; " +
                "done"
            ]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    root.vpnConnected = data.trim() === "connected"
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
            id: sleepProc
            running: false
            command: ["bash", "-c", "hyprctl dispatch dpms off && loginctl suspend 2>/dev/null || zzz"]
        }
        Process {
            id: rebootProc
            running: false
            command: ["bash", "-c", "loginctl reboot 2>/dev/null || reboot"]
        }
        Process {
            id: shutdownProc
            running: false
            command: ["bash", "-c", "loginctl poweroff 2>/dev/null || poweroff"]
        }
        Process {
            id: lockProc
            running: false
            command: ["bash", "-c", "hyprlock || swaylock -f || loginctl lock-session"]
        }

        property var notchLayout: [["Date", "Cava", "Time"], ["Workspaces"], ["Timer"]]

        readonly property string configDir:  "/home/daveee/.config/quickshell/dynamic-island"
        readonly property string configFile: configDir + "/config"

        property var _configParsed: []

        Process {
            id: configInitProc
            running: true
            command: ["bash", "-c",
                "DIR=\"" + root.configDir + "\"; " +
                "FILE=\"" + root.configFile + "\"; " +
                "mkdir -p \"$DIR\"; " +
                "if [ ! -f \"$FILE\" ]; then " +
                "  cat > \"$FILE\" << 'CFGEOF'\n" +
                "# Dynamic Island notch layout\n" +
                "# Each line defines one swipeable notch page.\n" +
                "# Valid widgets: Date, Time, Cava, Workspaces, Timer\n" +
                "# You can define as many notches as you want.\n" +
                "#\n" +
                "# Examples:\n" +
                "#   firstNotch  = [Date, Cava, Time]\n" +
                "#   secondNotch = [Workspaces]\n" +
                "#   thirdNotch  = [Timer]\n" +
                "\n" +
                "firstNotch  = [Date, Cava, Time]\n" +
                "secondNotch = [Workspaces]\n" +
                "thirdNotch  = [Timer]\n" +
                "\n" +
                "# ── Click bindings ────────────────────────────────\n" +
                "# Valid actions: music, controlPanel, notifHistory, appLauncher, none\n" +
                "\n" +
                "clickLeft   = music\n" +
                "clickRight  = controlPanel\n" +
                "clickMiddle = notifHistory\n" +
                "\n" +
                "# ── Gesture bindings ──────────────────────────────\n" +
                "# Valid actions: music, controlPanel, notifHistory, appLauncher, none\n" +
                "\n" +
                "dragDown    = appLauncher\n" +
                "\n" +
                "# ── Theme ────────────────────────────────────────\n" +
                "# pillColor:   pill background hex colour\n" +
                "# pillOpacity: 0.0 – 1.0 (1.0 = fully opaque)\n" +
                "# accentColor: toggle / active highlight colour\n" +
                "# textColor:   primary text colour\n" +
                "# fontFamily:  font name, or leave blank for system default\n" +
                "\n" +
                "pillColor   = #000000\n" +
                "pillOpacity = 1.0\n" +
                "accentColor = #2196F3\n" +
                "textColor   = #ffffff\n" +
                "fontFamily  =\n" +
                "CFGEOF\n" +
                "fi; " +
                "cat \"$FILE\""
            ]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var line = data.trim()
                    if (line === "" || line.startsWith("#")) return

                    var ma = line.match(/^\w+\s*=\s*\[([^\]]*)\]/)
                    if (ma) {
                        var widgets = ma[1].split(",")
                            .map(function(s) { return s.trim() })
                            .filter(function(s) { return s !== "" })
                        if (widgets.length > 0) {
                            var copy = root._configParsed.slice()
                            copy.push(widgets)
                            root._configParsed = copy
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
                    else if (key === "dragDown")    root.dragDown    = val
                    else if (key === "pillColor")   root.pillColor   = val
                    else if (key === "pillOpacity") root.pillOpacity = parseFloat(val)
                    else if (key === "accentColor") root.accentColor = val
                    else if (key === "textColor")   root.textColor   = val
                    else if (key === "fontFamily")  root.fontFamily  = val
                }
            }
            onRunningChanged: {
                if (!running && root._configParsed.length > 0)
                    root.notchLayout = root._configParsed.slice()
            }
        }

        FileView {
            id: configWatcher
            path:    root.configFile
            watchChanges: true
            onFileChanged: {
                root._configParsed = []
                configReloadProc.running = false
                configReloadProc.running = true
            }
        }

        Process {
            id: configReloadProc
            running: false
            command: ["bash", "-c", "cat \"" + root.configFile + "\""]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    var line = data.trim()
                    if (line === "" || line.startsWith("#")) return
                    var ma = line.match(/^\w+\s*=\s*\[([^\]]*)\]/)
                    if (ma) {
                        var widgets = ma[1].split(",")
                            .map(function(s) { return s.trim() })
                            .filter(function(s) { return s !== "" })
                        if (widgets.length > 0) {
                            var copy = root._configParsed.slice()
                            copy.push(widgets)
                            root._configParsed = copy
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
                    else if (key === "dragDown")    root.dragDown    = val
                    else if (key === "pillColor")   root.pillColor   = val
                    else if (key === "pillOpacity") root.pillOpacity = parseFloat(val)
                    else if (key === "accentColor") root.accentColor = val
                    else if (key === "textColor")   root.textColor   = val
                    else if (key === "fontFamily")  root.fontFamily  = val
                }
            }
            onRunningChanged: {
                if (!running && root._configParsed.length > 0)
                    root.notchLayout = root._configParsed.slice()
            }
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
            implicitHeight: 44
            color: "transparent"
            exclusiveZone: implicitHeight
        }

        PanelWindow {
            visible: root.islandVisible
            anchors.top:   true
            anchors.left:  true
            anchors.right: true
            implicitHeight: 530
            color: "transparent"
            exclusiveZone: -1
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.islandState === "appLauncher" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            mask: Region {
                x:      root.wifiNetworksOpen ? pillWrapper.x - 196 - 8 : pillWrapper.x
                y:      0
                width:  (root.soundAppsOpen    ? pillWrapper.width + 196 + 8 : pillWrapper.width)
                      + (root.wifiNetworksOpen  ? 196 + 8                    : 0)
                height: pillWrapper.height + (root.islandState === "appLauncher" ? 30 : 0)
            }

            Item {
                id: pillWrapper
                anchors.top: parent.top
                x: (parent.width - width) / 2

                property real defaultContentWidth: 260

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
                    + (silenceHandleOpen ? 10 + 52 : 0)
                    + 14

                property real notifHistoryHeight: Math.min(420, 52 + Math.max(1, notifHistory.count) * 68)
                property real appLauncherHeight: 500
                height: root.islandState === "default" ? 44 :
                        root.islandState === "music" ? 90 :
                        root.islandState === "notification" ? 72 :
                        root.islandState === "notifHistory" ? notifHistoryHeight :
                        root.islandState === "appLauncher" ? appLauncherHeight :
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

                                    RowLayout {
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
                                                    width:  parent.width
                                                    height: parent.height
                                                    readonly property real maxBarH: 26
                                                    property var bars: root.cavaBars
                                                    onBarsChanged: if (root.islandState === "default") requestPaint()
                                                    onPaint: {
                                                        var ctx = getContext("2d")
                                                        ctx.clearRect(0, 0, width, height)
                                                        var n = 10, sp = 2
                                                        var bw = (width - sp * (n - 1)) / n
                                                        for (var i = 0; i < n; i++) {
                                                            var v = (i < bars.length) ? bars[i] : 0
                                                            var h = Math.max(3, (v / 9) * maxBarH)
                                                            var x = i * (bw + sp)
                                                            var y = (height - h) / 2
                                                            ctx.fillStyle = root.tc(0.85)
                                                            root.drawBar(ctx, x, y, bw, h, Math.min(3, bw / 2, h / 2))
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
                                    if (dy > 40)
                                        root.doClickAction(root.dragDown)
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
                                            screenshotProc.running = false
                                            screenshotProc.running = true
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

                            RowLayout {
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
                                    color: root.vpnConnected
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
                                                text: root.vpnConnected ? "VPN on" : "VPN off"
                                                color: root.tc(0.38)
                                                font.pixelSize: 10; font.family: root.fontFamily
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.vpnConnected) {
                                                vpnDisconnectProc.running = false
                                                vpnDisconnectProc.running = true
                                                root.vpnConnected = false
                                            } else {
                                                vpnConnectProc.running = false
                                                vpnConnectProc.running = true
                                                root.vpnConnected = true
                                            }
                                        }
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
