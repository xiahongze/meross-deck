import QtQuick
import "meross.js" as Meross

// Owns the device state. Polls the helper, sends commands, and keeps a pending
// overlay so a control doesn't snap back while a slow poll is still in flight.
// Garage doors report only open or closed, so travel is timed here from the
// door's configured duration.
Item {
    id: client
    visible: false

    // function(args, done(exitCode, stdout)); tests replace it.
    property var runner: null
    property string transport: "auto"
    property int pollSeconds: 10
    property int cloudPollSeconds: 60
    property bool active: true
    property int offlineAfter: 3
    property int pendingMs: 15000
    property int debounceMs: 450
    property var clock: function() { return Date.now(); }

    property var devices: []
    property string account: ""
    property double lastUpdated: 0
    property int failures: 0
    property string lastError: ""
    property string errorKind: ""
    property bool busy: false
    // {key: {open, started, until}} for doors in travel.
    property var motion: ({})
    property double now: clock()

    readonly property bool signedOut: errorKind === "auth" || errorKind === "setup"
    readonly property bool online: lastUpdated > 0 && failures < offlineAfter && !signedOut
    readonly property bool stale: lastUpdated > 0 && failures > 0
    // "lan", "cloud" or "mixed", from the last successful poll.
    readonly property string route: {
        const routes = {};
        for (const d of _raw)
            if (d.route && !d.stale)
                routes[d.route] = true;
        const names = Object.keys(routes);
        return names.length === 1 ? names[0] : names.length > 1 ? "mixed" : "";
    }
    readonly property bool moving: Object.keys(motion).length > 0

    signal commandFailed(string reason)
    signal refreshed()

    property var _raw: []
    // {key: time} our own door travel ended; the poll that follows is expected.
    property var _settled: ({})
    property var _pending: ({})
    property var _staged: ({})

    // Timed polls let the helper reuse a cloud reading younger than the cloud
    // rate, so only LAN devices are read every few seconds. `fresh` polls,
    // after a command or a click on refresh, always read.
    function poll(fresh) {
        if (busy || !runner)
            return;
        busy = true;
        const args = Meross.helperArgs("state", transport);
        if (!fresh)
            args.push("--cloud-max-age", String(Math.max(0, cloudPollSeconds - 2)));
        runner(args, _onPoll);
    }

    function _onPoll(exitCode, stdout) {
        busy = false;
        const result = Meross.parseResult(exitCode, stdout);
        if (!result.ok) {
            failures++;
            lastError = result.reason;
            errorKind = result.kind;
            return;
        }
        const t = clock();
        const before = _raw;
        _raw = result.data.devices || [];
        account = result.data.account || "";
        _noticeDoors(before, _raw, t);
        // Pending edits the device now agrees with are done.
        for (const k in _pending) {
            const parts = k.split(":");
            const ch = Meross.findChannel(_raw, parts[0], parseInt(parts[1]));
            if (_pending[k].until < t || (ch && Meross.pendingSettled(ch, _pending[k])))
                delete _pending[k];
        }
        failures = 0;
        lastError = "";
        errorKind = "";
        lastUpdated = t;
        _publish();
        refreshed();
    }

    // A door seen to open without our command (wall button, remote, app) is
    // shown as opening for its travel time. Closing is reported at the end.
    function _noticeDoors(before, after, t) {
        if (before.length === 0)
            return;
        let changed = false;
        const m = Object.assign({}, motion);
        for (const d of after) {
            if (d.kind !== "garage" || d.stale)
                continue;
            for (const ch of d.channels) {
                const k = Meross.key(d.uuid, ch.channel);
                const old = Meross.findChannel(before, d.uuid, ch.channel);
                const ours = _settled[k] && t - _settled[k] < 60000;
                if (old && !old.open && ch.open && !m[k] && !ours) {
                    m[k] = { open: true, started: t, until: t + ch.openMs };
                    changed = true;
                }
            }
        }
        if (changed)
            motion = m;
    }

    function _publish() {
        devices = Meross.withPending(_raw, _pending, clock());
    }

    function _send(request, onDone) {
        runner(Meross.helperArgs("set", transport).concat([Meross.encodeRequest(request)]), function(exitCode, stdout) {
            const result = Meross.parseResult(exitCode, stdout);
            onDone(result);
        });
    }

    function _stage(uuid, channel, values) {
        const k = Meross.key(uuid, channel);
        const merged = Object.assign({}, _pending[k] ? _pending[k].values : {}, values);
        _pending[k] = { values: merged, until: clock() + pendingMs };
        _publish();
    }

    function _revert(uuid, channel, reason) {
        delete _pending[Meross.key(uuid, channel)];
        _publish();
        commandFailed(reason);
    }

    function setSwitch(uuid, channel, on) {
        _stage(uuid, channel, { on: on });
        _send({ uuid: uuid, kind: "switch", channel: channel, value: on }, function(result) {
            if (!result.ok)
                client._revert(uuid, channel, result.reason);
            else
                confirmTimer.restart();
        });
    }

    // Slider drags send the last value once the hand rests.
    function setLevel(uuid, channel, field, value) {
        const values = {};
        values[field] = value;
        values.on = true;
        _stage(uuid, channel, values);
        _staged[Meross.key(uuid, channel) + ":" + field] = { uuid: uuid, channel: channel, kind: field, value: value };
        levelTimer.restart();
    }

    function _flushLevels() {
        const staged = _staged;
        _staged = {};
        for (const k in staged) {
            const r = staged[k];
            _send(r, function(result) {
                if (!result.ok)
                    client._revert(r.uuid, r.channel, result.reason);
                else
                    confirmTimer.restart();
            });
        }
    }

    function moveDoor(uuid, channel, open) {
        const ch = Meross.findChannel(_raw, uuid, channel);
        const span = ch ? (open ? ch.openMs : ch.closeMs) : 15000;
        const t = clock();
        const k = Meross.key(uuid, channel);
        const m = Object.assign({}, motion);
        m[k] = { open: open, started: t, until: t + span };
        motion = m;
        _send({ uuid: uuid, kind: "door", channel: channel, value: open }, function(result) {
            if (!result.ok) {
                const n = Object.assign({}, client.motion);
                delete n[k];
                client.motion = n;
                client.commandFailed(result.reason);
            }
        });
    }

    function doorPhase(uuid, channel) {
        const ch = Meross.findChannel(devices, uuid, channel);
        if (!ch)
            return { phase: "unknown", progress: 0, remaining: 0 };
        return Meross.doorPhase(ch, motion[Meross.key(uuid, channel)], now);
    }

    function _tick() {
        now = clock();
        let ended = false;
        const m = {};
        for (const k in motion) {
            if (motion[k].until > now) {
                m[k] = motion[k];
            } else {
                ended = true;
                _settled[k] = now;
            }
        }
        if (ended) {
            motion = m;
            poll(true);
        }
    }

    Timer {
        id: pollTimer
        // A rejected session stops polling; signing in or refresh starts it again.
        running: client.active && client.runner !== null && !client.signedOut
        repeat: true
        triggeredOnStart: true
        interval: (client.route === "cloud" ? client.cloudPollSeconds : client.pollSeconds) * 1000
        onTriggered: client.poll()
    }
    Timer { interval: 250; running: client.moving; repeat: true; onTriggered: client._tick() }
    Timer { interval: 5000; running: client.active && !client.moving; repeat: true; onTriggered: client.now = client.clock() }
    Timer { id: levelTimer; interval: client.debounceMs; onTriggered: client._flushLevels() }
    // Re-read shortly after a command so the confirmed state lands quickly.
    Timer { id: confirmTimer; interval: 1500; onTriggered: client.poll(true) }
}
