pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "meross.js" as Meross

Item {
    id: root
    required property Client client
    property bool desktop: true
    property string themeMode: "system"
    property int desktopOpacity: 70
    property var hiddenDevices: []
    property string title: ""
    signal configureRequested()
    signal signInRequested()

    readonly property var doors: Meross.doors(client.devices, hiddenDevices)
    readonly property var lights: Meross.switches(client.devices, hiddenDevices, true)
    readonly property var offline: Meross.switches(client.devices, hiddenDevices, false)
    readonly property bool canControl: client.online
    // Repeaters key on these strings, which only change when the set of
    // channels does, so a poll never rebuilds a card mid-drag or mid-hold.
    readonly property string doorKeys: doors.map(d => d.device.uuid + ":" + (d.channel ? d.channel.channel : -1)).join("|")
    readonly property string lightKeys: lights.map(l => l.device.uuid + ":" + l.channel.channel).join("|")

    function entry(list, key) {
        return list.find(e => e.device.uuid + ":" + (e.channel ? e.channel.channel : -1) === key) || null;
    }
    readonly property int openDoors: doors.filter(d => d.channel && d.channel.open).length
    readonly property int lightsOn: lights.filter(l => l.channel.on).length

    readonly property bool forcedDark: themeMode === "dark"
    readonly property bool forcedLight: themeMode === "light"
    readonly property color themeBg: Kirigami.Theme.backgroundColor
    readonly property bool dark: forcedDark || (!forcedLight && (0.299 * themeBg.r + 0.587 * themeBg.g + 0.114 * themeBg.b) < 0.5)
    readonly property var colors: ({
        surface: forcedDark ? "#141922" : forcedLight ? "#ffffff" : Kirigami.Theme.backgroundColor,
        ink: forcedDark ? "#eef2f6" : forcedLight ? "#1f242b" : Kirigami.Theme.textColor,
        muted: forcedDark ? "#8f99a5" : forcedLight ? "#69737e" : Qt.alpha(Kirigami.Theme.textColor, 0.6),
        neutral: dark ? "#8a96a3" : "#6b7682",
        accent: dark ? "#5aaaf5" : "#2a76c6",
        warn: dark ? "#f2b84b" : "#b7791f",
        bad: dark ? "#f2706a" : "#c43d36",
        good: dark ? "#6fcf8b" : "#2f9e57",
        // Text on a filled accent button.
        onTone: dark ? "#14161a" : "#ffffff"
    })

    function ago(ms) {
        if (!ms)
            return "";
        const s = Math.max(0, Math.round((client.now - ms) / 1000));
        if (s < 5)
            return i18n("just now");
        if (s < 60)
            return i18n("%1 s ago", s);
        if (s < 3600)
            return i18n("%1 min ago", Math.round(s / 60));
        return i18n("%1 h ago", Math.round(s / 3600));
    }

    // lmTime is in seconds. Recent changes read as a duration, older as a time.
    function since(seconds) {
        const ms = seconds * 1000;
        const mins = Math.round((client.now - ms) / 60000);
        if (mins < 1)
            return i18n("just now");
        if (mins < 60)
            return i18n("for %1 min", mins);
        if (mins < 24 * 60)
            return i18n("since %1", Qt.formatTime(new Date(ms), Qt.locale().timeFormat(Locale.ShortFormat)));
        return i18n("since %1", Qt.formatDate(new Date(ms), "d MMM"));
    }

    function notify(message, isError) {
        toast.message = message;
        toast.isError = isError;
        toastTimer.restart();
    }

    Connections {
        target: root.client
        function onCommandFailed(reason) { root.notify(i18n("Didn't go through: %1", reason), true); }
    }

    implicitWidth: Kirigami.Units.gridUnit * 21
    implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 4
    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.minimumHeight: Kirigami.Units.gridUnit * 10
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    Rectangle {
        anchors.fill: parent
        visible: root.desktop
        radius: Kirigami.Units.cornerRadius * 3
        color: Qt.alpha(root.colors.surface, root.desktopOpacity / 100)
        border.color: Qt.alpha(root.colors.ink, 0.08)
    }
    // A warm wash while any door stands open, so it reads from across the room.
    Rectangle {
        anchors.fill: parent
        visible: root.desktop
        radius: Kirigami.Units.cornerRadius * 3
        opacity: root.openDoors > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.veryLongDuration } }
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(root.colors.warn, 0.13) }
            GradientStop { position: 0.5; color: "transparent" }
        }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing * 2
        spacing: Kirigami.Units.largeSpacing

        // Header: title, link status, refresh.
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Controls.Label {
                text: (root.title || i18n("Home")).toUpperCase()
                color: root.colors.muted
                font.pixelSize: Kirigami.Units.gridUnit * 0.6
                font.weight: Font.DemiBold
                font.letterSpacing: 1.4
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Rectangle {
                id: statusPill
                objectName: "statusPill"
                readonly property color tone: root.client.signedOut ? root.colors.neutral
                    : root.client.online ? (root.client.stale ? root.colors.warn : root.colors.good) : root.client.lastUpdated > 0 ? root.colors.bad : root.colors.neutral
                readonly property string label: root.client.signedOut ? i18n("SIGN IN")
                    : root.client.online ? (root.client.stale ? i18n("RETRYING") : root.client.route === "cloud" ? i18n("CLOUD") : root.client.route === "lan" ? i18n("LOCAL") : i18n("LIVE"))
                    : root.client.lastUpdated > 0 ? i18n("OFFLINE") : i18n("CONNECTING")
                implicitWidth: statusRow.implicitWidth + 12
                implicitHeight: statusRow.implicitHeight + 4
                radius: height / 2
                color: Qt.alpha(tone, 0.14)
                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 5
                    Rectangle { implicitWidth: 6; implicitHeight: 6; radius: 3; color: statusPill.tone }
                    Controls.Label {
                        text: statusPill.label
                        color: statusPill.tone
                        font.pixelSize: Kirigami.Units.gridUnit * 0.5
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                    }
                }
                Controls.ToolTip.visible: statusHover.hovered
                Controls.ToolTip.text: root.client.lastError !== "" ? root.client.lastError
                    : root.client.route === "cloud" ? i18n("Through the Meross cloud")
                    : root.client.route === "lan" ? i18n("Straight to the devices on this network")
                    : root.client.route === "mixed" ? i18n("Some devices locally, some through the cloud") : ""
                HoverHandler { id: statusHover }
            }
            Controls.ToolButton {
                icon.name: "view-refresh"
                implicitWidth: Kirigami.Units.iconSizes.small + 8
                implicitHeight: implicitWidth
                enabled: !root.client.busy && !root.client.signedOut
                opacity: hovered ? 1 : 0.6
                onClicked: root.client.poll(true)
                Controls.ToolTip.visible: hovered
                Controls.ToolTip.text: i18n("Refresh now")
            }
        }

        // Signed out: say so plainly and offer the way in.
        ColumnLayout {
            visible: root.client.signedOut
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit
            Layout.bottomMargin: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.largeSpacing
            Controls.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: root.colors.ink
                text: root.client.errorKind === "setup" ? i18n("Python 3 is needed to talk to Meross devices.")
                    : root.client.account !== "" ? i18n("The Meross session for %1 has ended. Sign in again to continue.", root.client.account)
                    : i18n("Sign in with your Meross account to see your garage doors, lights and plugs.")
            }
            Controls.Button {
                visible: root.client.errorKind !== "setup"
                Layout.alignment: Qt.AlignHCenter
                icon.name: "im-user-online"
                text: i18n("Sign in…")
                onClicked: root.signInRequested()
            }
        }

        Controls.Label {
            visible: !root.client.signedOut && root.client.lastUpdated === 0
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit
            Layout.bottomMargin: Kirigami.Units.gridUnit
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: root.colors.muted
            text: root.client.failures > 0 ? i18n("Can't reach Meross. %1", root.client.lastError) : i18n("Looking for your devices…")
        }

        // Everything below dims rather than blanks when the link drops.
        ColumnLayout {
            visible: !root.client.signedOut && root.client.lastUpdated > 0
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            opacity: root.client.online ? 1 : 0.55
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }

            SectionLabel {
                visible: root.doors.length > 0
                text: root.openDoors > 0 ? i18np("Garage · %1 open", "Garage · %1 open", root.openDoors) : i18n("Garage")
                tone: root.openDoors > 0 ? root.colors.warn : root.colors.muted
            }
            RowLayout {
                visible: root.doors.length > 0
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Repeater {
                    model: root.doorKeys === "" ? [] : root.doorKeys.split("|")
                    delegate: DoorCard {
                        id: door
                        required property string modelData
                        readonly property var item: root.entry(root.doors, modelData)
                        readonly property var device: item ? item.device : ({})
                        readonly property var ch: item ? item.channel : null
                        readonly property var travel: ch ? root.client.doorPhase(device.uuid, ch.channel) : ({ phase: "unknown", progress: 0, remaining: 0 })
                        objectName: "door-" + device.uuid
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        name: ch ? ch.name : device.name || ""
                        phase: travel.phase
                        progress: travel.progress
                        remaining: travel.remaining
                        lmTime: ch ? ch.lmTime : 0
                        obstruction: ch ? ch.obstruction : false
                        stale: !!device.stale && root.client.online
                        interactive: root.canControl && ch !== null && !!device.online && !device.stale
                        colors: root.colors
                        formatSince: root.since
                        onActivated: function(open) { root.client.moveDoor(device.uuid, ch.channel, open); }
                    }
                }
            }

            SectionLabel {
                visible: root.lights.length > 0
                Layout.topMargin: root.doors.length > 0 ? Kirigami.Units.smallSpacing : 0
                text: root.lightsOn > 0 ? i18n("Lights & plugs · %1 on", root.lightsOn) : i18n("Lights & plugs")
                tone: root.colors.muted
            }
            Repeater {
                model: root.lightKeys === "" ? [] : root.lightKeys.split("|")
                delegate: DeviceRow {
                    id: lightRow
                    required property string modelData
                    readonly property var item: root.entry(root.lights, modelData)
                    objectName: "row-" + modelData.replace(":", "-")
                    Layout.fillWidth: true
                    device: item ? item.device : ({})
                    channel: item ? item.channel : ({})
                    colors: root.colors
                    interactive: root.canControl && !!item && !item.device.stale
                    onToggled: function(on) { root.client.setSwitch(lightRow.device.uuid, lightRow.channel.channel, on); }
                    onLevelChanged: function(field, value) { root.client.setLevel(lightRow.device.uuid, lightRow.channel.channel, field, value); }
                }
            }

            // Offline devices are one quiet line, not a list of dead switches.
            Controls.Label {
                visible: root.offline.length > 0
                objectName: "offlineLine"
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                wrapMode: Text.Wrap
                color: root.colors.muted
                font.pixelSize: Kirigami.Units.gridUnit * 0.52
                text: i18np("Offline: %2", "%1 offline: %2", root.offline.length, root.offline.map(o => o.device.name).join(", "))
            }
        }

        Item { Layout.fillHeight: true }

        // Footer: freshness, or a short message.
        Item {
            visible: !root.client.signedOut
            Layout.fillWidth: true
            implicitHeight: footer.implicitHeight
            Controls.Label {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                opacity: toast.visible ? 0 : 1
                color: root.colors.muted
                font.pixelSize: Kirigami.Units.gridUnit * 0.5
                elide: Text.ElideRight
                text: root.client.lastUpdated > 0 ? i18n("Updated %1", root.ago(root.client.lastUpdated)) + (root.client.account ? " · " + root.client.account : "") : ""
            }
            Controls.Label {
                id: toast
                property string message: ""
                property bool isError: false
                anchors.left: parent.left
                anchors.right: parent.right
                visible: toastTimer.running
                text: message
                color: isError ? root.colors.bad : root.colors.ink
                font.pixelSize: Kirigami.Units.gridUnit * 0.5
                elide: Text.ElideRight
            }
            Timer { id: toastTimer; interval: 5000 }
        }
    }

    component SectionLabel: Controls.Label {
        property color tone
        Layout.fillWidth: true
        color: tone
        font.pixelSize: Kirigami.Units.gridUnit * 0.52
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
    }
}
