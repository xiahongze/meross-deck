pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root
    readonly property bool isDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
    readonly property var hidden: Plasmoid.configuration.hiddenDevices
    readonly property int openDoors: deckClient.devices.filter(d => d.kind === "garage" && hidden.indexOf(d.uuid) < 0)
        .reduce((n, d) => n + d.channels.filter(c => c.open).length, 0)

    Plasmoid.icon: Qt.resolvedUrl("../icons/meross-deck.svg")
    Plasmoid.title: i18n("Meross Deck")
    Plasmoid.backgroundHints: isDesktop ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground
    preferredRepresentation: isDesktop ? fullRepresentation : null
    switchWidth: isDesktop ? -1 : Kirigami.Units.gridUnit * 16
    switchHeight: isDesktop ? -1 : Kirigami.Units.gridUnit * 14
    toolTipMainText: i18n("Meross Deck")
    toolTipSubText: deckClient.signedOut ? i18n("Not signed in")
        : openDoors > 0 ? i18np("%1 garage door open", "%1 garage doors open", openDoors) : i18n("Garage closed")

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
            deckClient.poll();
        });
    }

    // Panels get the garage at a glance; the widget is designed for the desktop.
    compactRepresentation: Item {
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium
        Kirigami.Icon {
            anchors.fill: parent
            source: Qt.resolvedUrl("../icons/garage.svg")
            isMask: true
            color: root.openDoors > 0 ? (Kirigami.Theme.neutralTextColor) : Kirigami.Theme.textColor
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
