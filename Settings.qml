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
    property int valueMaxVisible: settings.maxVisible ?? defaults.maxVisible ?? 4
    property int valueDebounceMs: settings.debounceMs ?? defaults.debounceMs ?? 300
    property int valueMaxEventsPerSecond: settings.maxEventsPerSecond ?? defaults.maxEventsPerSecond ?? 20
    property string valueLanguage: settings.language ?? defaults.language ?? "auto"

    property int _langVersion: 0

    Connections {
        target: pluginApi?.mainInstance ?? null
        function onTranslationVersionChanged() {
            root._langVersion++;
        }
    }

    function t(key) {
        if (_langVersion < 0) return undefined;
        return pluginApi?.mainInstance?.translate(key);
    }

    spacing: Style.marginM

    function saveSettings() {
        if (!pluginApi) return;
        pluginApi.pluginSettings.enabled = root.valueEnabled;
        pluginApi.pluginSettings.perWorkspace = root.valuePerWorkspace;
        pluginApi.pluginSettings.maxVisible = root.valueMaxVisible;
        pluginApi.pluginSettings.debounceMs = root.valueDebounceMs;
        pluginApi.pluginSettings.maxEventsPerSecond = root.valueMaxEventsPerSecond;
        pluginApi.pluginSettings.language = root.valueLanguage;
        pluginApi.saveSettings();
    }

    // ─── Language ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NLabel {
            label: root.t("settings.language")
            description: root.t("settings.language-desc")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            Repeater {
                model: ["auto", "en", "pt"]

                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    readonly property string langCode: modelData
                    readonly property bool isSelected: root.valueLanguage === langCode
                    readonly property string langLabel: {
                        if (langCode === "auto") return root.t("settings.lang-auto");
                        if (langCode === "en") return root.t("settings.lang-en");
                        return root.t("settings.lang-pt");
                    }

                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Style.iRadiusM
                    color: isSelected ? Qt.alpha(Color.mPrimary, 0.15) : Color.mSurfaceVariant
                    border.color: isSelected ? Color.mPrimary : (langMouse.containsMouse ? Color.mOutline : "transparent")
                    border.width: isSelected ? 2 : 1

                    Behavior on color { ColorAnimation { duration: Style.animationFast } }
                    Behavior on border.color { ColorAnimation { duration: Style.animationFast } }

                    NText {
                        anchors.centerIn: parent
                        text: parent.langLabel
                        font.bold: parent.isSelected
                        color: parent.isSelected ? Color.mPrimary : Color.mOnSurface
                    }

                    MouseArea {
                        id: langMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.valueLanguage = langCode;
                            root.saveSettings();
                            pluginApi?.mainInstance?.reloadLanguage(langCode);
                            root._langVersion++;
                        }
                    }
                }
            }
        }
    }

    // ─── Enable / Disable ───
    NToggle {
        Layout.fillWidth: true
        label: root.t("settings.enabled")
        description: root.t("settings.enabled-desc")
        checked: root.valueEnabled
        onToggled: checked => {
            root.valueEnabled = checked;
            root.saveSettings();
        }
    }

    // ─── Per Workspace ───
    NToggle {
        Layout.fillWidth: true
        label: root.t("settings.per-workspace")
        description: root.t("settings.per-workspace-desc")
        checked: root.valuePerWorkspace
        onToggled: checked => {
            root.valuePerWorkspace = checked;
            root.saveSettings();
            pluginApi?.mainInstance?.restartDaemon();
        }
    }

    // ─── Max Visible Columns ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NLabel {
            label: root.t("settings.max-visible") + ": " + root.valueMaxVisible
            description: root.t("settings.max-visible-desc")
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
                pluginApi?.mainInstance?.restartDaemon();
            }
        }
    }

    // ─── Debounce ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NLabel {
            label: root.t("settings.debounce") + ": " + root.valueDebounceMs + "ms"
            description: root.t("settings.debounce-desc")
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
                pluginApi?.mainInstance?.restartDaemon();
            }
        }
    }

    // ─── Rate Limit ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NLabel {
            label: root.t("settings.rate-limit") + ": " + root.valueMaxEventsPerSecond + "/s"
            description: root.t("settings.rate-limit-desc")
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
                pluginApi?.mainInstance?.restartDaemon();
            }
        }
    }

    // ─── Status ───
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: 8

        Rectangle {
            width: 8
            height: 8
            radius: 4
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
                if (status === "running") return root.t("settings.status-running");
                if (status === "error") return root.t("settings.status-error");
                return root.t("settings.status-stopped");
            }
            Layout.fillWidth: true
        }
    }

    // ─── About ───
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: 4

        NText {
            text: root.t("settings.about-title")
            font.bold: true
        }

        NText {
            text: root.t("settings.about-credit")
            opacity: 0.7
            font.pixelSize: 12
        }

        NText {
            text: root.t("settings.about-date") + ": 2026-02-19"
            opacity: 0.5
            font.pixelSize: 11
        }

        NText {
            text: "v" + (pluginApi?.manifest?.version ?? "1.1.0")
            opacity: 0.5
            font.pixelSize: 11
        }
    }
}
