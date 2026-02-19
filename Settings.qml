import QtQuick
import QtQuick.Layouts
import qs.Widgets

ColumnLayout {
    id: settingsRoot

    property var pluginApi: null

    readonly property var settings: pluginApi?.pluginSettings ?? ({})
    readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})

    spacing: 16

    // ─── Enable / Disable ───
    NToggle {
        Layout.fillWidth: true
        text: pluginApi?.tr("settings.enabled") ?? "Enable Auto-Tile"
        description: pluginApi?.tr("settings.enabled-desc") ?? "Automatically redistribute column widths when windows open or close"
        checked: settings.enabled ?? defaults.enabled ?? true
        onCheckedChanged: {
            if (settings.enabled !== checked) {
                settings.enabled = checked;
                pluginApi?.saveSettings();
            }
        }
    }

    // ─── Max Visible Columns ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        NText {
            text: (pluginApi?.tr("settings.max-visible") ?? "Max visible columns") + ": " + maxVisibleSlider.value
            font.bold: true
        }

        NText {
            text: pluginApi?.tr("settings.max-visible-desc") ?? "Maximum number of columns visible on screen at once"
            opacity: 0.7
            font.pixelSize: 12
        }

        Slider {
            id: maxVisibleSlider
            Layout.fillWidth: true
            from: 1
            to: 8
            stepSize: 1
            value: settings.maxVisible ?? defaults.maxVisible ?? 4
            onMoved: {
                settings.maxVisible = value;
                pluginApi?.saveSettings();
                pluginApi?.mainInstance?.restartDaemon();
            }
        }
    }

    // ─── Debounce ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        NText {
            text: (pluginApi?.tr("settings.debounce") ?? "Debounce delay") + ": " + debounceSlider.value + "ms"
            font.bold: true
        }

        NText {
            text: pluginApi?.tr("settings.debounce-desc") ?? "Delay before redistribution to coalesce rapid events"
            opacity: 0.7
            font.pixelSize: 12
        }

        Slider {
            id: debounceSlider
            Layout.fillWidth: true
            from: 100
            to: 1000
            stepSize: 50
            value: settings.debounceMs ?? defaults.debounceMs ?? 300
            onMoved: {
                settings.debounceMs = value;
                pluginApi?.saveSettings();
                pluginApi?.mainInstance?.restartDaemon();
            }
        }
    }

    // ─── Rate Limit ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        NText {
            text: (pluginApi?.tr("settings.rate-limit") ?? "Rate limit") + ": " + rateLimitSlider.value + "/s"
            font.bold: true
        }

        NText {
            text: pluginApi?.tr("settings.rate-limit-desc") ?? "Maximum events processed per second"
            opacity: 0.7
            font.pixelSize: 12
        }

        Slider {
            id: rateLimitSlider
            Layout.fillWidth: true
            from: 5
            to: 50
            stepSize: 5
            value: settings.maxEventsPerSecond ?? defaults.maxEventsPerSecond ?? 20
            onMoved: {
                settings.maxEventsPerSecond = value;
                pluginApi?.saveSettings();
                pluginApi?.mainInstance?.restartDaemon();
            }
        }
    }

    // ─── Status ───
    NBox {
        Layout.fillWidth: true
        Layout.topMargin: 8
        padding: 12

        RowLayout {
            anchors.fill: parent
            spacing: 8

            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: {
                    const status = pluginApi?.mainInstance?.status ?? "stopped";
                    if (status === "running") return "#4caf50";
                    if (status === "error") return "#f44336";
                    return "#9e9e9e";
                }
            }

            NText {
                text: {
                    const status = pluginApi?.mainInstance?.status ?? "stopped";
                    if (status === "running") return pluginApi?.tr("settings.status-running") ?? "Daemon running";
                    if (status === "error") return pluginApi?.tr("settings.status-error") ?? "Daemon error — restarting...";
                    return pluginApi?.tr("settings.status-stopped") ?? "Daemon stopped";
                }
                Layout.fillWidth: true
            }
        }
    }
}
