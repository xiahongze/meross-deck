import QtQuick
import "../../contents/ui/meross.js" as Meross

// Stands in for the Python helper: answers `state` from a fixture and applies
// `set` requests to it, asynchronously like the real one.
QtObject {
    id: fake
    property var state: ({ ok: true, devices: [] })
    property string failKind: ""
    property string failSet: ""
    property bool holdSets: false
    property var sent: []
    property var _held: []
    readonly property var run: function(args, done) { fake._run(args, done); }

    function load(text) {
        state = JSON.parse(text);
        sent = [];
        _held = [];
        failKind = "";
        failSet = "";
        holdSets = false;
    }

    function device(uuid) {
        return state.devices.find(d => d.uuid === uuid);
    }

    function _run(args, done) {
        let reply;
        if (args[0] === "state") {
            reply = failKind !== "" ? { ok: false, kind: failKind, error: failKind + " failure" } : state;
        } else if (args[0] === "set") {
            const request = JSON.parse(Meross.unbase64(args[args.length - 1]));
            sent = sent.concat([request]);
            if (failSet !== "") {
                reply = { ok: false, kind: "device", error: failSet };
            } else {
                _apply(request);
                reply = { ok: true, uuid: request.uuid, route: "lan" };
            }
            if (holdSets) {
                _held.push(function() { done(0, JSON.stringify(reply)); });
                return;
            }
        } else {
            reply = { ok: true };
        }
        const text = JSON.stringify(reply);
        Qt.callLater(function() { done(0, text); });
    }

    function release() {
        const held = _held;
        _held = [];
        for (const f of held)
            f();
    }

    function _apply(r) {
        const d = device(r.uuid);
        const ch = d.channels.find(c => c.channel === r.channel);
        if (r.kind === "door")
            ch.open = r.value;
        else if (r.kind === "switch")
            ch.on = r.value;
        else {
            ch[r.kind] = r.value;
            ch.on = true;
        }
    }
}
