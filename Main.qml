import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var pluginApi: null
    property bool running: false
    property string status: "stopped"

    readonly property bool enabled: pluginApi?.pluginSettings?.enabled ?? true
    readonly property int maxVisible: pluginApi?.pluginSettings?.maxVisible ?? 4
    readonly property int debounceMs: pluginApi?.pluginSettings?.debounceMs ?? 300
    readonly property int maxEventsPerSecond: pluginApi?.pluginSettings?.maxEventsPerSecond ?? 20

    readonly property string scriptPath: (pluginApi?.pluginDir ?? "") + "/auto-tile.py"

    onEnabledChanged: {
        if (enabled) {
            startDaemon();
        } else {
            stopDaemon();
        }
    }

    onMaxVisibleChanged: {
        if (running) {
            restartDaemon();
        }
    }

    Component.onCompleted: {
        if (enabled) {
            startDaemon();
        }
    }

    Component.onDestruction: {
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
        stopDaemon();
        Qt.callLater(startDaemon);
    }

    function setMaxVisible(count) {
        if (count < 1 || count > 8) return;
        if (pluginApi?.pluginSettings) {
            pluginApi.pluginSettings.maxVisible = count;
            pluginApi.saveSettings();
        }
    }

    readonly property Process daemonProcess: Process {
        command: [
            "python3", root.scriptPath,
            "--max-visible", String(root.maxVisible),
            "--debounce", String(root.debounceMs / 1000.0),
            "--max-events", String(root.maxEventsPerSecond)
        ]

        running: false

        onStarted: {
            root.running = true;
            root.status = "running";
        }

        onExited: (exitCode, exitStatus) => {
            root.running = false;
            if (exitCode === 0 || exitStatus === Process.CrashExit) {
                root.status = "stopped";
            } else {
                root.status = "error";
            }

            // Auto-restart if enabled and not intentionally stopped
            if (root.enabled && exitCode !== 0) {
                restartTimer.start();
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

        function setColumns(count) {
            root.setMaxVisible(count);
        }

        function status() {
            return {
                running: root.running,
                enabled: root.enabled,
                status: root.status,
                maxVisible: root.maxVisible
            };
        }
    }
}
