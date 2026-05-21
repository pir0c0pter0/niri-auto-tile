import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null

    readonly property var settings: pluginApi?.pluginSettings ?? ({})
    readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})

    property bool valueEnabled: settings.enabled ?? defaults.enabled ?? true
    property bool valuePerWorkspace: settings.perWorkspace ?? defaults.perWorkspace ?? false
    property bool valueKeepMaxWidth: settings.keepMaxWidth ?? defaults.keepMaxWidth ?? false
    property int valueMaxVisible: settings.maxVisible ?? defaults.maxVisible ?? 4
    property int valueDebounceMs: settings.debounceMs ?? defaults.debounceMs ?? 300
    property int valueMaxEventsPerSecond: settings.maxEventsPerSecond ?? defaults.maxEventsPerSecond ?? 20

    spacing: Style.marginM

    function saveSettings() {
        if (!pluginApi) return;
        pluginApi.pluginSettings.enabled = root.valueEnabled;
        pluginApi.pluginSettings.perWorkspace = root.valuePerWorkspace;
        pluginApi.pluginSettings.keepMaxWidth = root.valueKeepMaxWidth;
        pluginApi.pluginSettings.maxVisible = root.valueMaxVisible;
        pluginApi.pluginSettings.debounceMs = root.valueDebounceMs;
        pluginApi.pluginSettings.maxEventsPerSecond = root.valueMaxEventsPerSecond;
        pluginApi.saveSettings();
    }

    function runtimeConfig() {
        return {
            maxVisible: root.valueMaxVisible,
            keepMaxWidth: root.valueKeepMaxWidth,
            perWorkspace: root.valuePerWorkspace,
            workspaceMaxVisible: settings.workspaceMaxVisible ?? {},
            debounceMs: root.valueDebounceMs,
            maxEventsPerSecond: root.valueMaxEventsPerSecond
        };
    }

    function applyRuntimeConfig() {
        pluginApi?.mainInstance?.hotReloadConfig(root.runtimeConfig());
    }

    // ─── Enable / Disable ───
    NToggle {
        Layout.fillWidth: true
        label: pluginApi?.tr("settings.enabled")
        description: pluginApi?.tr("settings.enabled-desc")
        checked: root.valueEnabled
        onToggled: checked => {
            root.valueEnabled = checked;
            root.saveSettings();
        }
    }

    // ─── Per Workspace ───
    NToggle {
        Layout.fillWidth: true
        label: pluginApi?.tr("settings.per-workspace")
        description: pluginApi?.tr("settings.per-workspace-desc")
        checked: root.valuePerWorkspace
        onToggled: checked => {
            root.valuePerWorkspace = checked;
            root.saveSettings();
            root.applyRuntimeConfig();
        }
    }

    // ─── Keep Max Width ───
    NToggle {
        Layout.fillWidth: true
        label: pluginApi?.tr("settings.keep-max-width")
        description: pluginApi?.tr("settings.keep-max-width-desc")
        checked: root.valueKeepMaxWidth
        onToggled: checked => {
            root.valueKeepMaxWidth = checked;
            root.saveSettings();
            root.applyRuntimeConfig();
        }
    }

    // ─── Max Visible Columns ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NLabel {
            label: pluginApi?.tr("settings.max-visible", {"value": root.valueMaxVisible})
            description: pluginApi?.tr("settings.max-visible-desc")
        }

        NSlider {
            Layout.fillWidth: true
            from: 1
            to: 8
            value: root.valueMaxVisible
            stepSize: 1
            onMoved: {
                root.valueMaxVisible = Math.round(value);
                root.saveSettings();
                root.applyRuntimeConfig();
            }
        }
    }

    // ─── Debounce ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NLabel {
            label: pluginApi?.tr("settings.debounce", {"value": root.valueDebounceMs})
            description: pluginApi?.tr("settings.debounce-desc")
        }

        NSlider {
            Layout.fillWidth: true
            from: 100
            to: 1000
            value: root.valueDebounceMs
            stepSize: 50
            onMoved: {
                root.valueDebounceMs = Math.round(value);
                root.saveSettings();
                root.applyRuntimeConfig();
            }
        }
    }

    // ─── Rate Limit ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NLabel {
            label: pluginApi?.tr("settings.rate-limit", {"value": root.valueMaxEventsPerSecond})
            description: pluginApi?.tr("settings.rate-limit-desc")
        }

        NSlider {
            Layout.fillWidth: true
            from: 5
            to: 50
            value: root.valueMaxEventsPerSecond
            stepSize: 5
            onMoved: {
                root.valueMaxEventsPerSecond = Math.round(value);
                root.saveSettings();
                root.applyRuntimeConfig();
            }
        }
    }

    // ─── Status ───
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: Style.marginM

        Rectangle {
            width: Math.round(8 * Style.uiScaleRatio)
            height: Math.round(8 * Style.uiScaleRatio)
            radius: Math.round(4 * Style.uiScaleRatio)
            color: {
                const status = pluginApi?.mainInstance?.status ?? "stopped";
                if (status === "running") return Color.mPrimary;
                if (status === "error") return Color.mError;
                return Color.mOutline;
            }
        }

        NText {
            text: {
                const status = pluginApi?.mainInstance?.status ?? "stopped";
                if (status === "running") return pluginApi?.tr("settings.status-running");
                if (status === "error") return pluginApi?.tr("settings.status-error");
                return pluginApi?.tr("settings.status-stopped");
            }
            Layout.fillWidth: true
        }
    }

    // ─── About ───
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: Style.marginXS

        NText {
            text: pluginApi?.tr("settings.about-title")
            font.bold: true
        }

        NText {
            text: pluginApi?.tr("settings.about-credit")
            opacity: 0.7
            pointSize: Style.fontSizeS
        }

        NText {
            text: pluginApi?.tr("settings.about-date", {"date": "2026-02-19"})
            opacity: 0.5
            pointSize: Style.fontSizeXS
        }

        NText {
            text: "v" + (pluginApi?.manifest?.version ?? "1.1.0")
            opacity: 0.5
            pointSize: Style.fontSizeXS
        }
    }
}
