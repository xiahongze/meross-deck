import QtQuick
import QtTest
import "../../contents/ui" as Deck

TestCase {
    id: suite
    name: "DeckView"
    width: 420
    height: 640
    visible: true
    when: windowShown
    property string fixture: ""
    readonly property var parsed: fixture ? JSON.parse(fixture) : null
    readonly property string garage: parsed ? parsed.devices.find(d => d.kind === "garage").uuid : ""
    readonly property string lamp: parsed ? parsed.devices.find(d => d.kind === "light").uuid : ""

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

    FakeHelper { id: helper }
    Deck.Client { id: client; active: false; runner: helper.run }
    Deck.DeckView { id: deck; anchors.fill: parent; client: client; themeMode: "dark" }
    SignalSpy { id: signIn; target: deck; signalName: "signInRequested" }

    function initTestCase() {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() { if (xhr.readyState === XMLHttpRequest.DONE) suite.fixture = xhr.responseText; };
        xhr.open("GET", Qt.resolvedUrl("../fixtures/state.json"));
        xhr.send();
        tryVerify(() => fixture.length > 0);
    }

    function init() {
        helper.load(fixture);
        client._pending = {};
        client.motion = {};
        client.errorKind = "";
        client.failures = 0;
        deck.hiddenDevices = [];
        client.poll();
        tryVerify(() => client.lastUpdated > 0 && !client.busy);
        waitForRendering(deck);
    }

    function test_sections() {
        compare(deck.doors.length, 2);
        compare(deck.lights.length, 1);
        compare(deck.offline.length, 4);
        const line = findChild(deck, "offlineLine");
        verify(line.text.indexOf("4 offline") === 0);
        compare(findChild(deck, "statusPill").label, "LOCAL");
    }

    function test_hidden_devices_drop_out() {
        deck.hiddenDevices = [garage];
        compare(deck.doors.length, 1);
    }

    function test_door_cards_do_not_overlap() {
        const a = findChild(deck, "door-" + deck.doors[0].device.uuid);
        const b = findChild(deck, "door-" + deck.doors[1].device.uuid);
        const pa = a.mapToItem(deck, 0, 0), pb = b.mapToItem(deck, 0, 0);
        verify(pa.x + a.width <= pb.x || pb.x + b.width <= pa.x, "cards sit side by side");
        compare(a.width, b.width);
    }

    function test_one_click_only_asks() {
        const card = findChild(deck, "door-" + garage);
        mouseClick(findChild(card, "actionButton"));
        verify(card.confirming);
        verify(findChild(card, "confirmRow").visible);
        wait(200);
        compare(helper.sent.length, 0);
        mouseClick(findChild(card, "cancelButton"));
        verify(!card.confirming);
        compare(helper.sent.length, 0);
    }

    function test_unanswered_confirmation_expires() {
        const card = findChild(deck, "door-" + garage);
        card.confirmMs = 150;
        mouseClick(findChild(card, "actionButton"));
        verify(card.confirming);
        tryVerify(() => !card.confirming);
        compare(helper.sent.length, 0);
        card.confirmMs = 6000;
    }

    function test_confirm_moves_only_that_door() {
        const card = findChild(deck, "door-" + garage);
        mouseClick(findChild(card, "actionButton"));
        mouseClick(findChild(card, "confirmButton"));
        tryVerify(() => helper.sent.length === 1);
        wait(100);
        compare(helper.sent.length, 1, "only the confirmed door moves");
        compare(helper.sent[0].uuid, garage);
        compare(helper.sent[0].kind, "door");
        compare(helper.sent[0].value, true);
        compare(card.phase, "opening");
        verify(!card.confirming);
    }

    function test_lamp_toggle_and_sliders() {
        const row = findChild(deck, "row-" + lamp + "-0");
        const brightness = findChild(row, "brightness");
        verify(!brightness.visible, "sliders hide while off");
        mouseClick(findChild(row, "toggle"));
        tryVerify(() => helper.sent.length === 1);
        compare(helper.sent[0].kind, "switch");
        tryVerify(() => brightness.visible);
        compare(brightness.value, 80);
        verify(findChild(deck, "row-" + lamp + "-0") === row, "the row survives the update");
    }

    function test_signed_out_offers_sign_in() {
        helper.failKind = "auth";
        client.poll();
        tryVerify(() => client.signedOut);
        compare(findChild(deck, "statusPill").label, "SIGN IN");
        deck.signInRequested();
        compare(signIn.count, 1);
    }
}
