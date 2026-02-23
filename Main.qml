import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var pluginApi: null
    property bool running: false
    property string status: "stopped"
    property bool pendingRestart: false

    property string _currentLang: ""
    property int translationVersion: 0
    readonly property string language: pluginApi?.pluginSettings?.language ?? "auto"

    onLanguageChanged: _loadTranslations()
    onPluginApiChanged: { if (pluginApi) _loadTranslations(); }

    readonly property var _enStrings: ({
        "panel": {
            "title": "Column Layout",
            "single": "Single",
            "columns": "%1 Columns",
            "status-active": "Active — %1 columns",
            "status-starting": "Starting...",
            "status-disabled": "Disabled"
        },
        "bar": {
            "running": "Auto-Tile: running (%1 cols)",
            "starting": "Auto-Tile: starting...",
            "disabled": "Auto-Tile: disabled",
            "enable": "Enable Auto-Tile",
            "disable": "Disable Auto-Tile",
            "settings": "Settings"
        },
        "settings": {
            "enabled": "Enable Auto-Tile",
            "enabled-desc": "Automatically redistribute column widths when windows open or close",
            "per-workspace": "Per workspace",
            "per-workspace-desc": "Each workspace has its own column count setting",
            "max-visible": "Max visible columns",
            "max-visible-desc": "Maximum number of columns visible on screen at once",
            "debounce": "Debounce delay",
            "debounce-desc": "Delay before redistribution to coalesce rapid events",
            "rate-limit": "Rate limit",
            "rate-limit-desc": "Maximum events processed per second",
            "status-running": "Daemon running",
            "status-error": "Daemon error — restarting...",
            "status-stopped": "Daemon stopped",
            "about-title": "About",
            "about-credit": "Developed by Pir0c0pter0 using Claude",
            "about-date": "Date",
            "language": "Language",
            "language-desc": "Plugin display language",
            "lang-auto": "Auto",
            "lang-en": "English",
            "lang-pt": "Portuguese"
        }
    })

    readonly property var _ptStrings: ({
        "panel": {
            "title": "Layout de Colunas",
            "single": "Unica",
            "columns": "%1 Colunas",
            "status-active": "Ativo — %1 colunas",
            "status-starting": "Iniciando...",
            "status-disabled": "Desativado"
        },
        "bar": {
            "running": "Auto-Tile: executando (%1 colunas)",
            "starting": "Auto-Tile: iniciando...",
            "disabled": "Auto-Tile: desativado",
            "enable": "Ativar Auto-Tile",
            "disable": "Desativar Auto-Tile",
            "settings": "Configuracoes"
        },
        "settings": {
            "enabled": "Ativar Auto-Tile",
            "enabled-desc": "Redistribuir automaticamente as larguras das colunas ao abrir ou fechar janelas",
            "per-workspace": "Por workspace",
            "per-workspace-desc": "Cada workspace tem sua propria configuracao de colunas",
            "max-visible": "Colunas visiveis",
            "max-visible-desc": "Numero maximo de colunas visiveis na tela simultaneamente",
            "debounce": "Atraso de debounce",
            "debounce-desc": "Atraso antes da redistribuicao para agrupar eventos rapidos",
            "rate-limit": "Limite de eventos",
            "rate-limit-desc": "Maximo de eventos processados por segundo",
            "status-running": "Daemon em execucao",
            "status-error": "Erro no daemon — reiniciando...",
            "status-stopped": "Daemon parado",
            "about-title": "Sobre",
            "about-credit": "Desenvolvido por Pir0c0pter0 usando Claude",
            "about-date": "Data",
            "language": "Idioma",
            "language-desc": "Idioma de exibicao do plugin",
            "lang-auto": "Auto",
            "lang-en": "Ingles",
            "lang-pt": "Portugues"
        }
    })

    property var _translations: _enStrings

    readonly property bool enabled: pluginApi?.pluginSettings?.enabled ?? true
    readonly property int maxVisible: pluginApi?.pluginSettings?.maxVisible ?? 4
    readonly property bool perWorkspace: pluginApi?.pluginSettings?.perWorkspace ?? false
    readonly property var workspaceMaxVisible: pluginApi?.pluginSettings?.workspaceMaxVisible ?? ({})
    readonly property int debounceMs: pluginApi?.pluginSettings?.debounceMs ?? 300
    readonly property int maxEventsPerSecond: pluginApi?.pluginSettings?.maxEventsPerSecond ?? 20

    readonly property string scriptPath: (pluginApi?.pluginDir ?? "") + "/auto-tile.py"

    // Serialize workspace config as JSON string for CLI
    function workspaceConfigJson() {
        const cfg = workspaceMaxVisible;
        if (!cfg || typeof cfg !== "object") return "{}";
        return JSON.stringify(cfg);
    }

    function _resolveLanguage() {
        if (language !== "auto") return language;
        const locale = Qt.locale().name;
        if (locale.startsWith("pt")) return "pt";
        return "en";
    }

    function _loadTranslations() {
        const lang = _resolveLanguage();
        if (lang === _currentLang) return;
        _translations = (lang === "pt") ? _ptStrings : _enStrings;
        _currentLang = lang;
        translationVersion++;
    }

    function reloadLanguage(langCode) {
        let resolved = langCode;
        if (langCode === "auto") {
            const locale = Qt.locale().name;
            resolved = locale.startsWith("pt") ? "pt" : "en";
        }
        if (resolved === _currentLang) return;
        _translations = (resolved === "pt") ? _ptStrings : _enStrings;
        _currentLang = resolved;
        translationVersion++;
    }

    function translate(key) {
        const parts = key.split(".");
        let obj = _translations;
        for (let i = 0; i < parts.length; i++) {
            if (obj && typeof obj === "object" && parts[i] in obj) {
                obj = obj[parts[i]];
            } else {
                return undefined;
            }
        }
        return typeof obj === "string" ? obj : undefined;
    }

    onEnabledChanged: {
        if (enabled) {
            startDaemon();
        } else {
            pendingRestart = false;
            stopDaemon();
        }
    }

    onMaxVisibleChanged: {
        if (running) restartDaemon();
    }

    onPerWorkspaceChanged: {
        if (running) restartDaemon();
    }

    Component.onCompleted: {
        _loadTranslations();
        if (enabled) startDaemon();
    }

    Component.onDestruction: {
        pendingRestart = false;
        stopDaemon();
    }

    function startDaemon() {
        if (running) return;
        daemonProcess.running = true;
    }

    function stopDaemon() {
        if (!running) return;
        daemonProcess.signal(15); // SIGTERM
    }

    function restartDaemon() {
        pendingRestart = true;
        stopDaemon();
    }

    function setMaxVisible(count) {
        if (count < 1 || count > 8) return;
        if (!pluginApi?.pluginSettings) return;
        pluginApi.pluginSettings.maxVisible = count;
        pluginApi.saveSettings();
    }

    function setWorkspaceMaxVisible(wsId, count) {
        if (count < 1 || count > 8) return;
        if (!pluginApi?.pluginSettings) return;
        let cfg = pluginApi.pluginSettings.workspaceMaxVisible;
        if (!cfg || typeof cfg !== "object") cfg = {};
        // Create new object (immutable pattern)
        const updated = Object.assign({}, cfg);
        updated[String(wsId)] = count;
        pluginApi.pluginSettings.workspaceMaxVisible = updated;
        pluginApi.saveSettings();
        if (running) restartDaemon();
    }

    function setPerWorkspace(value) {
        if (!pluginApi?.pluginSettings) return;
        pluginApi.pluginSettings.perWorkspace = value;
        pluginApi.saveSettings();
    }

    function getMaxVisibleForWorkspace(wsId) {
        if (perWorkspace) {
            const cfg = workspaceMaxVisible;
            if (cfg && typeof cfg === "object" && String(wsId) in cfg) {
                return cfg[String(wsId)];
            }
        }
        return maxVisible;
    }

    readonly property Process daemonProcess: Process {
        command: {
            const args = [
                "python3", root.scriptPath,
                "--max-visible", String(root.maxVisible),
                "--debounce", String(root.debounceMs / 1000.0),
                "--max-events", String(root.maxEventsPerSecond)
            ];
            if (root.perWorkspace) {
                args.push("--per-workspace");
                args.push("--workspace-config");
                args.push(root.workspaceConfigJson());
            }
            return args;
        }

        running: false

        onStarted: {
            root.running = true;
            root.status = "running";
        }

        onExited: (exitCode, exitStatus) => {
            root.running = false;

            if (root.pendingRestart) {
                root.pendingRestart = false;
                root.status = "starting";
                root.startDaemon();
                return;
            }

            if (exitCode === 0 || exitStatus === Process.CrashExit) {
                root.status = "stopped";
            } else {
                root.status = "error";
                if (root.enabled) {
                    restartTimer.start();
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const msg = text.trim();
                if (msg) {
                    console.warn("[auto-tile]", msg);
                }
            }
        }
    }

    readonly property Timer restartTimer: Timer {
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.enabled && !root.running) {
                root.startDaemon();
            }
        }
    }

    IpcHandler {
        target: "plugin:niri-auto-tile"

        function toggle() {
            const newState = !root.enabled;
            if (pluginApi?.pluginSettings) {
                pluginApi.pluginSettings.enabled = newState;
                pluginApi.saveSettings();
            }
        }

        function setColumns(count: int) {
            root.setMaxVisible(count);
        }

        function status() {
            return {
                running: root.running,
                enabled: root.enabled,
                status: root.status,
                maxVisible: root.maxVisible,
                perWorkspace: root.perWorkspace
            };
        }
    }
}
