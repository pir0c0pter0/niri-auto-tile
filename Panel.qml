import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    readonly property var geometryPlaceholder: panelContainer
    property real contentPreferredWidth: 300 * Style.uiScaleRatio
    property real contentPreferredHeight: 260 * Style.uiScaleRatio
    readonly property bool allowAttach: true

    anchors.fill: parent

    readonly property var mainInstance: pluginApi?.mainInstance
    readonly property bool isRunning: mainInstance?.running ?? false
    readonly property bool isEnabled: mainInstance?.enabled ?? false
    readonly property int currentMaxVisible: mainInstance?.maxVisible ?? 4

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            anchors {
                fill: parent
                margins: Style.marginM
            }
            spacing: Style.marginL

            NBox {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginL
                    clip: true

                    // ─── Header ───
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        NIcon {
                            icon: "view-split-left-right"
                            pointSize: Style.fontSizeL
                            color: Color.mPrimary
                        }

                        NText {
                            text: pluginApi?.tr("panel.title") ?? "Column Layout"
                            pointSize: Style.fontSizeL
                            font.weight: Style.fontWeightBold
                            color: Color.mOnSurface
                            Layout.fillWidth: true
                        }

                        // Enable/disable toggle
                        NToggle {
                            checked: root.isEnabled
                            onCheckedChanged: {
                                if (pluginApi?.pluginSettings && pluginApi.pluginSettings.enabled !== checked) {
                                    pluginApi.pluginSettings.enabled = checked;
                                    pluginApi.saveSettings();
                                }
                            }
                        }
                    }

                    // ─── Layout Options Grid ───
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 2
                        rowSpacing: Style.marginM
                        columnSpacing: Style.marginM

                        Repeater {
                            model: [1, 2, 3, 4]

                            delegate: Rectangle {
                                id: layoutOption

                                required property int modelData
                                readonly property int columnCount: modelData
                                readonly property bool isSelected: columnCount === root.currentMaxVisible

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 60

                                radius: Style.iRadiusM
                                color: isSelected ? Qt.alpha(Color.mPrimary, 0.15) : Color.mSurfaceVariant
                                border.color: isSelected ? Color.mPrimary : (optionMouse.containsMouse ? Color.mOutline : "transparent")
                                border.width: isSelected ? 2 : 1

                                Behavior on color { ColorAnimation { duration: Style.animationFast } }
                                Behavior on border.color { ColorAnimation { duration: Style.animationFast } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Style.marginS
                                    spacing: Style.marginS

                                    // ─── Visual column representation ───
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 3

                                            Repeater {
                                                model: layoutOption.columnCount

                                                Rectangle {
                                                    width: {
                                                        const available = layoutOption.width - Style.marginS * 2 - (layoutOption.columnCount - 1) * 3;
                                                        return Math.max(8, available / layoutOption.columnCount);
                                                    }
                                                    height: layoutOption.height * 0.45
                                                    radius: 3
                                                    color: layoutOption.isSelected
                                                        ? Color.mPrimary
                                                        : (optionMouse.containsMouse ? Qt.alpha(Color.mOnSurface, 0.4) : Qt.alpha(Color.mOnSurface, 0.25))

                                                    Behavior on color { ColorAnimation { duration: Style.animationFast } }
                                                }
                                            }
                                        }
                                    }

                                    // ─── Label ───
                                    NText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: layoutOption.columnCount === 1
                                            ? (pluginApi?.tr("panel.single") ?? "Single")
                                            : (pluginApi?.tr("panel.columns") ?? "%1 Columns").arg(layoutOption.columnCount)
                                        pointSize: Style.fontSizeS
                                        font.weight: layoutOption.isSelected ? Style.fontWeightBold : Style.fontWeightNormal
                                        color: layoutOption.isSelected ? Color.mPrimary : Color.mOnSurface
                                    }
                                }

                                MouseArea {
                                    id: optionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: {
                                        if (root.mainInstance) {
                                            root.mainInstance.setMaxVisible(layoutOption.columnCount);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ─── Status bar ───
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: {
                                if (!root.isEnabled) return Color.mOutline;
                                if (root.isRunning) return "#4caf50";
                                return "#ff9800";
                            }
                        }

                        NText {
                            text: {
                                if (!root.isEnabled) return pluginApi?.tr("panel.status-disabled") ?? "Disabled";
                                if (root.isRunning) return (pluginApi?.tr("panel.status-active") ?? "Active — %1 columns").arg(root.currentMaxVisible);
                                return pluginApi?.tr("panel.status-starting") ?? "Starting...";
                            }
                            pointSize: Style.fontSizeS
                            color: Qt.alpha(Color.mOnSurface, 0.6)
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }
}
