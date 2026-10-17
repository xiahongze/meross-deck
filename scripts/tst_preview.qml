import QtQuick
import QtTest
import "../contents/ui" as Deck
import "../tests/qml" as Fixtures

// `make screenshots`: renders the widget over a stand-in wallpaper so the
// translucent card is visible, from the redacted fixture.
TestCase {
    id: preview
    name: "Screenshots"
    width: 500
    height: 620
    visible: true
    when: windowShown
    property string fixture: ""
    property double fakeNow: Date.UTC(2026, 9, 17, 8, 30)

    function i18n(text) {
        for (let i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(singular, plural, n) {
        let text = n === 1 ? singular : plural;
        for (let i = 2; i < arguments.length; i++)
            text = text.replace("%" + (i - 1), arguments[i]);
        return text;
    }

    Item {
        id: stage
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: wallpaper.dark ? "#1b2a4a" : "#9cc3e8" }
                GradientStop { position: 0.55; color: wallpaper.dark ? "#3b2f5c" : "#e9c7d9" }
                GradientStop { position: 1; color: wallpaper.dark ? "#0e3b3f" : "#f3e1b8" }
            }
            QtObject { id: wallpaper; property bool dark: deck.themeMode === "dark" }
        }
        Repeater {
            model: 3
            Rectangle {
                required property int index
                x: [-60, 300, 100][index]; y: [60, 340, 560][index]
                width: [280, 240, 200][index]; height: width; radius: width / 2
                color: wallpaper.dark ? ["#4f7cff", "#ff7b54", "#2fd3a8"][index] : ["#ffffff", "#ff9e7a", "#7fd6ff"][index]
                opacity: 0.35
            }
        }
        Deck.DeckView {
            id: deck
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 32
            height: implicitHeight
            client: client
        }
    }

    Fixtures.FakeHelper { id: helper }
    Deck.Client {
        id: client
        active: false
        runner: helper.run
        clock: function() { return preview.fakeNow; }
    }

    function initTestCase() {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() { if (xhr.readyState === XMLHttpRequest.DONE) preview.fixture = xhr.responseText; };
        xhr.open("GET", Qt.resolvedUrl("../tests/fixtures/state.json"));
        xhr.send();
        tryVerify(() => fixture.length > 0);
        helper.load(fixture);
        refresh();
    }

    function refresh() {
        client.poll();
        tryVerify(() => !client.busy);
        client.now = preview.fakeNow + 8000;
    }

    function test_capture() {
        for (const theme of ["dark", "light"]) {
            deck.themeMode = theme;
            save("meross-deck-" + theme);
        }

        // An evening: the left door left open, the floor lamp on low and warm,
        // and one plug back online.
        const devices = helper.state.devices;
        const doors = devices.filter(d => d.kind === "garage");
        doors[0].channels[0].open = true;
        doors[0].channels[0].lmTime = Math.round(preview.fakeNow / 1000) - 23 * 60;
        doors[1].channels[0].lmTime = Math.round(preview.fakeNow / 1000) - 3 * 3600;
        const lamp = devices.find(d => d.kind === "light").channels[0];
        lamp.on = true;
        lamp.luminance = 55;
        lamp.temperature = 18;
        const plug = devices.find(d => d.kind === "plug");
        plug.online = true;
        plug.stale = false;
        plug.route = "lan";
        plug.name = "Desk Plug";
        plug.channels = [{ channel: 0, kind: "switch", name: "Desk Plug", on: true }];
        client.motion = {};
        refresh();
        client.motion = {};
        deck.themeMode = "dark";
        save("meross-deck-evening");

        // Asking before the right door moves.
        const right = findChild(deck, "door-" + doors[1].uuid);
        right.confirmMs = 60000;
        right.confirming = true;
        save("meross-deck-confirm");
        right.confirming = false;

        // The right door on its way up.
        client.moveDoor(doors[1].uuid, 0, true);
        preview.fakeNow += 5000;
        client.now = preview.fakeNow;
        save("meross-deck-opening");
    }

    function save(name) {
        wait(1200);
        grabImage(stage).save(Qt.resolvedUrl("../docs/screenshots/" + name + ".png").toString().replace("file://", ""));
    }
}
