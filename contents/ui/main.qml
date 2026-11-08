pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "meross.js" as Meross

PlasmoidItem {
    id: root
    readonly property bool isDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
    readonly property var hidden: Plasmoid.configuration.hiddenDevices
    readonly property var doors: Meross.doors(deckClient.devices, hidden)
    readonly property int openDoors: doors.filter(d => d.channel && d.channel.open).length
    readonly property int lightsOn: Meross.switches(deckClient.devices, hidden, true).filter(d => d.channel.on).length
    readonly property int offlineDevices: deckClient.devices.filter(d => hidden.indexOf(d.uuid) < 0 && !d.online).length


    Plasmoid.icon: Qt.resolvedUrl("../icons/meross-deck.svg")
    Plasmoid.title: i18n("Meross Deck")
    Plasmoid.backgroundHints: isDesktop ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground
    preferredRepresentation: isDesktop ? fullRepresentation : compactRepresentation
    switchWidth: 0
    switchHeight: 0
    toolTipMainText: i18n("Meross Deck")
    toolTipSubText: {
        if (deckClient.signedOut)
            return i18n("Sign in from the widget to see your devices");
        if (!deckClient.lastUpdated)
            return deckClient.lastError || i18n("Connecting to devices…");
        const lines = [];
        if (deckClient.stale || !deckClient.online)
            lines.push(i18n("Last known state · %1", deckClient.online ? i18n("retrying") : i18n("offline")));
        if (deckClient.moving)
            lines.push(i18n("Garage door moving…"));
        if (doors.length)
            lines.push(openDoors > 0 ? i18np("%1 garage door open", "%1 garage doors open", openDoors) : i18n("Garage closed"));
        lines.push(i18np("%1 light or plug on", "%1 lights or plugs on", lightsOn));
        if (offlineDevices)
            lines.push(i18np("%1 device offline", "%1 devices offline", offlineDevices));
        return lines.join("\n");
    }

    HelperRunner { id: helper }

    Client {
        id: deckClient
        runner: helper.run
        transport: Plasmoid.configuration.transport
        pollSeconds: Plasmoid.configuration.pollSeconds
        cloudPollSeconds: Plasmoid.configuration.cloudPollSeconds
    }

    function signIn() {
        helper.runInTerminal(["login"], function(exitCode) {
            if (exitCode === 127)
                Plasmoid.internalAction("configure").trigger();
            deckClient.poll(true);
        });
    }

    // A transparent mask follows the panel palette, independent of the deck theme.
    compactRepresentation: Item {
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium
        Layout.minimumWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: Math.max(implicitWidth, height)
        Accessible.name: root.toolTipMainText + ": " + root.toolTipSubText
        Accessible.role: Accessible.Button
        activeFocusOnTab: true
        Keys.onSpacePressed: root.expanded = !root.expanded
        Keys.onReturnPressed: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            source: Qt.resolvedUrl("../icons/garage.svg")
            isMask: true
            color: root.openDoors > 0 || deckClient.moving ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            opacity: deckClient.stale || !deckClient.online ? 0.6 : 1
        }
        MouseArea { anchors.fill: parent; onClicked: root.expanded = !root.expanded }
    }
    fullRepresentation: DeckView {
        client: deckClient
        desktop: root.isDesktop
        themeMode: Plasmoid.configuration.themeMode
        desktopOpacity: Plasmoid.configuration.desktopOpacity
        hiddenDevices: root.hidden
        title: Plasmoid.configuration.title
        onConfigureRequested: Plasmoid.internalAction("configure").trigger()
        onSignInRequested: root.signIn()
    }
}
