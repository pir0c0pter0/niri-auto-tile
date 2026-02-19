import QtQuick
import QtQuick.Layouts
import qs.Widgets

NButton {
    id: barButton

    property var pluginApi: null

    readonly property var mainInstance: pluginApi?.mainInstance ?? null
    readonly property bool isRunning: mainInstance?.running ?? false
    readonly property bool isEnabled: mainInstance?.enabled ?? false
    readonly property int maxVisible: mainInstance?.maxVisible ?? 4

    tooltip: isEnabled
        ? (isRunning ? qsTr("Auto-Tile: running (%1 cols)").arg(maxVisible) : qsTr("Auto-Tile: starting..."))
        : qsTr("Auto-Tile: disabled")

    contentItem: RowLayout {
        spacing: 4

        NIcon {
            name: "view-grid-symbolic"
            size: 16
            opacity: isEnabled ? 1.0 : 0.4
        }

        NText {
            text: String(maxVisible)
            opacity: isEnabled ? 1.0 : 0.4
            visible: barButton.width > 36
        }
    }

    onClicked: {
        if (mainInstance) {
            const newState = !isEnabled;
            if (pluginApi?.pluginSettings) {
                pluginApi.pluginSettings.enabled = newState;
                pluginApi.saveSettings();
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.6
        height: 2
        radius: 1
        color: isRunning ? "#4caf50" : (isEnabled ? "#ff9800" : "transparent")
    }
}
