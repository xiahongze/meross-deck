import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "meross.js" as Meross

// A light, plug or switch channel: a glowing orb, the name, and a switch.
// Lamps that dim show brightness and warmth sliders while they're on.
Item {
    id: row
    property var device: ({})
    property var channel: ({})
    property var colors: ({})
    property bool interactive: true
    signal toggled(bool on)
    signal levelChanged(string field, int value)

    readonly property bool isLight: channel.kind === "light"
    readonly property bool on: !!channel.on
    readonly property bool dims: isLight && channel.luminance !== undefined
    readonly property bool tunable: isLight && channel.temperature !== undefined
    readonly property color glow: isLight ? (tunable ? Meross.warmth(channel.temperature) : "#ffd28a") : colors.accent
    readonly property string detail: {
        if (!on)
            return i18n("Off");
        const parts = [i18n("On")];
        if (dims)
            parts.push(i18n("%1%", channel.luminance));
        if (tunable)
            parts.push(i18n("%1 K", Meross.kelvin(channel.temperature)));
        return parts.join(" · ");
    }

    implicitHeight: layout.implicitHeight
    implicitWidth: Kirigami.Units.gridUnit * 16

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Item {
                implicitWidth: Kirigami.Units.gridUnit * 1.8
                implicitHeight: implicitWidth
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 1.5
                    height: width
                    radius: width / 2
                    color: row.glow
                    opacity: row.on ? 0.18 : 0
                    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: row.on ? row.glow : Qt.alpha(row.colors.ink, 0.08)
                    Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: parent.width * 0.62
                        height: width
                        source: Qt.resolvedUrl(row.isLight ? "../icons/bulb.svg" : "../icons/plug.svg")
                        isMask: true
                        color: row.on ? "#2a2116" : row.colors.muted
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Controls.Label {
                    Layout.fillWidth: true
                    text: row.channel.name || row.device.name
                    color: row.colors.ink
                    elide: Text.ElideRight
                    font.pixelSize: Kirigami.Units.gridUnit * 0.66
                }
                Controls.Label {
                    Layout.fillWidth: true
                    text: row.detail
                    color: row.colors.muted
                    font.pixelSize: Kirigami.Units.gridUnit * 0.52
                    font.features: { "tnum": 1 }
                }
            }

            Toggle {
                objectName: "toggle"
                on: row.on
                tone: row.isLight ? Qt.darker(row.glow, 1.35) : row.colors.accent
                ink: row.colors.ink
                interactive: row.interactive
                onToggled: function(on) { row.toggled(on); }
            }
        }

        // Dimming, shown while the lamp is on.
        GridLayout {
            visible: row.on && (row.dims || row.tunable)
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 1.8 + Kirigami.Units.largeSpacing
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: 2

            Controls.Label {
                visible: row.dims
                text: i18n("Brightness")
                color: row.colors.muted
                font.pixelSize: Kirigami.Units.gridUnit * 0.5
            }
            LevelSlider {
                objectName: "brightness"
                visible: row.dims
                Layout.fillWidth: true
                value: row.channel.luminance || 1
                tone: Qt.darker(row.glow, 1.2)
                ink: row.colors.ink
                interactive: row.interactive
                onMoved: function(v) { row.levelChanged("luminance", v); }
            }
            Controls.Label {
                visible: row.tunable
                text: i18n("Colour")
                color: row.colors.muted
                font.pixelSize: Kirigami.Units.gridUnit * 0.5
            }
            LevelSlider {
                objectName: "warmth"
                visible: row.tunable
                Layout.fillWidth: true
                value: row.channel.temperature || 50
                ink: row.colors.ink
                interactive: row.interactive
                track: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Meross.warmth(1) }
                    GradientStop { position: 0.5; color: Meross.warmth(50) }
                    GradientStop { position: 1; color: Meross.warmth(100) }
                }
                onMoved: function(v) { row.levelChanged("temperature", v); }
            }
        }
    }
}
