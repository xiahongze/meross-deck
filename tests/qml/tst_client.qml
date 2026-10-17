import QtQuick
import QtTest
import "../../contents/ui" as Deck
import "../../contents/ui/meross.js" as Meross

TestCase {
    id: suite
    name: "Client"
    property string fixture: ""
    property double fakeNow: 1792199000000
    readonly property var parsed: fixture ? JSON.parse(fixture) : null
    readonly property string garage: parsed ? parsed.devices.find(d => d.kind === "garage").uuid : ""
    readonly property string lamp: parsed ? parsed.devices.find(d => d.kind === "light").uuid : ""

    FakeHelper { id: helper }
    Deck.Client {
        id: client
        active: false
        runner: helper.run
        clock: function() { return suite.fakeNow; }
    }
    SignalSpy { id: failures; target: client; signalName: "commandFailed" }

    function initTestCase() {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() { if (xhr.readyState === XMLHttpRequest.DONE) suite.fixture = xhr.responseText; };
        xhr.open("GET", Qt.resolvedUrl("../fixtures/state.json"));
        xhr.send();
        tryVerify(() => fixture.length > 0);
    }

    function init() {
        helper.load(fixture);
        client.devices = [];
        client._raw = [];
        client._pending = {};
        client.motion = {};
        client.lastUpdated = 0;
        client.failures = 0;
        client.errorKind = "";
        failures.clear();
        client.poll();
        tryVerify(() => client.lastUpdated > 0);
    }

    function test_poll_reads_devices() {
        compare(client.devices.length, 7);
        verify(client.online);
        compare(client.route, "lan");
        compare(client.devices[0].kind, "garage");
        compare(client.doorPhase(garage, 0).phase, "closed");
    }

    function test_signed_out() {
        helper.failKind = "auth";
        client.lastUpdated = 0;
        client.poll();
        tryVerify(() => client.signedOut);
        verify(!client.online);
    }

    function test_repeated_failures_go_offline() {
        helper.failKind = "network";
        for (let i = 0; i < 3; i++) {
            client.poll();
            tryVerify(() => !client.busy);
        }
        verify(!client.online);
        verify(client.lastUpdated > 0, "the last reading stays");
    }

    function test_switch_shows_at_once_and_settles() {
        helper.holdSets = true;
        client.setSwitch(lamp, 0, true);
        compare(Meross.findChannel(client.devices, lamp, 0).on, true, "optimistic");
        // A poll that still shows the old state must not snap it back.
        const before = JSON.parse(JSON.stringify(helper.state));
        helper.device(lamp).channels[0].on = false;
        client.poll();
        tryVerify(() => !client.busy);
        compare(Meross.findChannel(client.devices, lamp, 0).on, true);
        helper.state = before;
        helper.release();
        client.poll();
        tryVerify(() => !client.busy);
        compare(Meross.findChannel(client.devices, lamp, 0).on, true);
        compare(Object.keys(client._pending).length, 0, "settled");
    }

    function test_failed_command_reverts() {
        helper.failSet = "Device error 5005";
        client.setSwitch(lamp, 0, true);
        tryCompare(failures, "count", 1);
        compare(Meross.findChannel(client.devices, lamp, 0).on, false);
    }

    function test_slider_sends_last_value_once() {
        client.debounceMs = 50;
        client.setLevel(lamp, 0, "luminance", 30);
        client.setLevel(lamp, 0, "luminance", 45);
        client.setLevel(lamp, 0, "luminance", 60);
        compare(Meross.findChannel(client.devices, lamp, 0).luminance, 60);
        tryVerify(() => helper.sent.length === 1);
        wait(120);
        compare(helper.sent.length, 1);
        compare(helper.sent[0].kind, "luminance");
        compare(helper.sent[0].value, 60);
    }

    function test_door_travel_is_timed() {
        client.moveDoor(garage, 0, true);
        compare(helper.sent.length, 1);
        compare(helper.sent[0].kind, "door");
        compare(helper.sent[0].value, true);
        let p = client.doorPhase(garage, 0);
        compare(p.phase, "opening");
        compare(p.remaining, 12);
        suite.fakeNow += 6000;
        client._tick();
        p = client.doorPhase(garage, 0);
        fuzzyCompare(p.progress, 0.5, 0.01);
        suite.fakeNow += 6500;
        client._tick();
        verify(!client.moving);
        tryVerify(() => client.doorPhase(garage, 0).phase === "open");
        suite.fakeNow += 1000;
    }

    function test_door_opened_elsewhere_shows_travel() {
        helper.device(garage).channels[0].open = true;
        client.poll();
        tryVerify(() => !client.busy);
        compare(client.doorPhase(garage, 0).phase, "opening");
        // Closing is only reported at the end, so it lands as closed.
        client.motion = {};
        helper.device(garage).channels[0].open = false;
        client.poll();
        tryVerify(() => !client.busy);
        compare(client.doorPhase(garage, 0).phase, "closed");
    }

    function test_timed_polls_reuse_cloud_readings() {
        let seen = null;
        const real = client.runner;
        client.runner = function(args, done) { seen = args; real(args, done); };
        client.poll();
        tryVerify(() => !client.busy);
        compare(seen.slice(0, 3), ["state", "--cloud-max-age", "58"]);
        client.poll(true);
        tryVerify(() => !client.busy);
        compare(seen, ["state"]);
        client.runner = real;
    }

    function test_signed_out_stops_polling() {
        client.active = true;
        verify(pollTimerRunning());
        helper.failKind = "auth";
        client.poll();
        tryVerify(() => client.signedOut);
        verify(!pollTimerRunning());
        helper.failKind = "";
        client.poll(true);
        tryVerify(() => !client.signedOut);
        verify(pollTimerRunning());
        client.active = false;
    }

    function pollTimerRunning() {
        for (let i = 0; i < client.data.length; i++) {
            const t = client.data[i];
            if (t.triggeredOnStart === true)
                return t.running;
        }
        return false;
    }

    function test_cloud_route_slows_polling() {
        for (const d of helper.state.devices)
            if (d.online)
                d.route = "cloud";
        client.poll();
        tryVerify(() => client.route === "cloud");
    }

    function test_helper_args_are_shell_safe() {
        compare(Meross.shellQuote("it's"), "'it'\\''s'");
        const encoded = Meross.encodeRequest({ uuid: "a", kind: "switch", channel: 0, value: true });
        verify(/^[A-Za-z0-9+\/=]+$/.test(encoded));
        compare(JSON.parse(Meross.unbase64(encoded)).uuid, "a");
        compare(Meross.helperArgs("state", "cloud"), ["state", "--cloud-only"]);
        compare(Meross.parseResult(127, "").kind, "setup");
        compare(Meross.parseResult(0, "{\"ok\":false,\"kind\":\"auth\",\"error\":\"x\"}").kind, "auth");
    }
}
