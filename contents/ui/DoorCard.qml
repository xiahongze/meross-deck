import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// One garage door: a drawn door that rises and falls with the state, and a
// hold-to-act button so a stray click can never move it.
Rectangle {
    id: card
    property string name: ""
    // closed, open, opening, closing or unknown
    property string phase: "unknown"
    property real progress: 0
    property int remaining: 0
    property double lmTime: 0
    property bool obstruction: false
    property bool interactive: true
    property bool stale: false
    property var colors: ({})
    property var formatSince: function(t) { return ""; }
    property int holdMs: 700
    signal activated(bool open)

    readonly property bool moving: phase === "opening" || phase === "closing"
    readonly property color tone: phase === "open" ? colors.warn
        : moving ? colors.accent
        : phase === "closed" ? colors.good : colors.neutral
    readonly property string stateText: ({
        open: i18n("Open"), closed: i18n("Closed"), opening: i18n("Opening…"), closing: i18n("Closing…"), unknown: i18n("Unknown")
    })[phase] || phase

    implicitWidth: Kirigami.Units.gridUnit * 9
    implicitHeight: column.implicitHeight + Kirigami.Units.largeSpacing * 2
    radius: Kirigami.Units.cornerRadius * 2.5
    color: Qt.alpha(colors.ink, 0.045)
    border.color: Qt.alpha(phase === "open" ? colors.warn : colors.ink, phase === "open" ? 0.35 : 0.08)
    Behavior on border.color { ColorAnimation { duration: Kirigami.Units.longDuration } }

    // A wash of the state colour from the bottom while the door is open or moving.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        opacity: card.phase === "open" || card.moving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }
        gradient: Gradient {
            GradientStop { position: 0.35; color: "transparent" }
            GradientStop { position: 1; color: Qt.alpha(card.tone, 0.16) }
        }
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Controls.Label {
                Layout.fillWidth: true
                text: card.name
                color: card.colors.ink
                elide: Text.ElideRight
                font.pixelSize: Kirigami.Units.gridUnit * 0.62
                font.weight: Font.DemiBold
            }
            Rectangle {
                visible: card.stale
                implicitWidth: 6; implicitHeight: 6; radius: 3
                color: card.colors.warn
                Controls.ToolTip.visible: staleHover.hovered
                Controls.ToolTip.text: i18n("Last known state; the door isn't answering")
                HoverHandler { id: staleHover }
            }
        }

        // The door. The opening is the dark interior; the panel slides up into it.
        Item {
            id: art
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4.6
            Layout.topMargin: Kirigami.Units.smallSpacing
            readonly property real openingWidth: Math.min(width * 0.8, height * 1.45)

            // Roof line.
            Canvas {
                id: roof
                anchors.horizontalCenter: parent.horizontalCenter
                width: art.openingWidth + 18
                height: 14
                property color stroke: Qt.alpha(card.colors.ink, 0.35)
                onStrokeChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = stroke;
                    ctx.lineWidth = 1.6;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.moveTo(1, height - 1);
                    ctx.lineTo(width / 2, 1);
                    ctx.lineTo(width - 1, height - 1);
                    ctx.stroke();
                }
            }
            Rectangle {
                id: opening
                anchors.top: roof.bottom
                anchors.topMargin: 3
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: art.openingWidth
                radius: 3
                clip: true
                color: Qt.alpha(card.colors.ink, 0.07)
                border.color: Qt.alpha(card.colors.ink, 0.22)
                border.width: 1.2

                // Light spilling out of an open garage.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    opacity: card.progress
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: Qt.alpha(card.tone, 0.22) }
                    }
                }

                Rectangle {
                    id: panel
                    x: 3
                    width: parent.width - 6
                    y: 3
                    // A sliver of panel stays visible when fully open, as in life.
                    height: Math.max(4, (parent.height - 6) * (1 - card.progress * 0.88))
                    radius: 2
                    color: Qt.alpha(card.tone, 0.2)
                    border.color: Qt.alpha(card.tone, 0.6)
                    border.width: 1.2
                    Behavior on height {
                        enabled: !card.moving
                        NumberAnimation { duration: Kirigami.Units.veryLongDuration; easing.type: Easing.InOutCubic }
                    }
                    Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
                    // Slats are drawn from the bottom edge so they ride with the panel.
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            x: 5
                            width: panel.width - 10
                            height: 1.2
                            y: panel.height - (index + 1) * (opening.height - 6) / 4.6
                            visible: y > 3
                            color: Qt.alpha(card.tone, 0.45)
                        }
                    }
                }
            }
        }

        Controls.Label {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            horizontalAlignment: Text.AlignHCenter
            text: card.moving && card.remaining > 0 ? i18n("%1 %2 s", card.stateText, card.remaining) : card.stateText
            color: card.tone
            font.pixelSize: Kirigami.Units.gridUnit * 0.95
            font.weight: Font.Light
            font.features: { "tnum": 1 }
        }
        Controls.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: card.obstruction ? i18n("Obstruction detected") : card.lmTime > 0 && !card.moving ? card.formatSince(card.lmTime) : " "
            color: card.obstruction ? card.colors.bad : card.colors.muted
            font.pixelSize: Kirigami.Units.gridUnit * 0.52
            elide: Text.ElideRight
        }

        // Press and hold: the fill grows, and the command goes only when it's full.
        Rectangle {
            id: hold
            objectName: "holdButton"
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            implicitHeight: holdLabel.implicitHeight + Kirigami.Units.smallSpacing * 2.6
            radius: height / 2
            readonly property bool enabledNow: card.interactive && !card.moving && card.phase !== "unknown"
            readonly property bool wantsOpen: card.phase !== "open"
            readonly property color actionTone: wantsOpen ? card.colors.warn : card.colors.good
            property real fill: 0
            opacity: enabledNow ? 1 : 0.4
            color: Qt.alpha(card.colors.ink, holdHover.hovered && enabledNow ? 0.09 : 0.06)
            border.color: Qt.alpha(actionTone, holdHover.hovered && enabledNow ? 0.5 : 0.22)
            clip: true

            Rectangle {
                width: parent.width * hold.fill
                height: parent.height
                radius: parent.radius
                color: Qt.alpha(hold.actionTone, 0.35)
            }
            Controls.Label {
                id: holdLabel
                anchors.centerIn: parent
                text: card.moving ? i18n("Moving…") : hold.fill > 0 ? i18n("Keep holding…") : hold.wantsOpen ? i18n("Hold to open") : i18n("Hold to close")
                color: hold.enabledNow ? hold.actionTone : card.colors.muted
                font.pixelSize: Kirigami.Units.gridUnit * 0.56
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
            }
            NumberAnimation {
                id: holdFill
                target: hold
                property: "fill"
                from: 0
                to: 1
                duration: card.holdMs
                onFinished: {
                    if (hold.fill >= 1) {
                        card.activated(hold.wantsOpen);
                        hold.fill = 0;
                    }
                }
            }
            NumberAnimation { id: holdRelease; target: hold; property: "fill"; to: 0; duration: Kirigami.Units.shortDuration }
            HoverHandler { id: holdHover; enabled: hold.enabledNow; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: holdTap
                enabled: hold.enabledNow
                longPressThreshold: 10
                onPressedChanged: {
                    if (pressed) {
                        holdRelease.stop();
                        holdFill.restart();
                    } else if (hold.fill < 1) {
                        holdFill.stop();
                        holdRelease.restart();
                    }
                }
            }
            Controls.ToolTip.visible: holdHover.hovered && hold.enabledNow && hold.fill === 0
            Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
            Controls.ToolTip.text: i18n("Press and hold to %1 the door", hold.wantsOpen ? i18n("open") : i18n("close"))
        }
    }
}
