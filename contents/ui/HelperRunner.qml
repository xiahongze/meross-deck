import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "meross.js" as Meross

// Runs the bundled Python helper through Plasma's executable engine. Each run
// gets a unique source name, so a poll and a command can be in flight at once.
Item {
    id: runner
    visible: false

    property string script: Qt.resolvedUrl("../code/meross_deck.py").toString().replace("file://", "")
    property int timeoutMs: 40000
    property int _serial: 0
    property var _waiting: ({})

    // run(["state", "--lan-only"], function(exitCode, stdout) {...})
    function run(args, done) {
        const source = "MEROSS_DECK_RUN=" + (++_serial) + " python3 " + Meross.shellQuote(script) + " " + args.map(Meross.shellQuote).join(" ");
        _waiting[source] = { done: done, started: Date.now() };
        engine.connectSource(source);
        if (!reaper.running)
            reaper.start();
    }

    // Opens a terminal with an arbitrary helper command, e.g. login.
    function runInTerminal(args, done) {
        const inner = "python3 " + Meross.shellQuote(script) + " " + args.map(Meross.shellQuote).join(" ") + "; echo; read -p 'Press Enter to close' _";
        const source = "MEROSS_DECK_RUN=" + (++_serial) + " konsole -e bash -c " + Meross.shellQuote(inner);
        _waiting[source] = { done: done, started: Date.now(), interactive: true };
        engine.connectSource(source);
    }

    Plasma5Support.DataSource {
        id: engine
        engine: "executable"
        interval: 0
        onNewData: function(source, data) {
            const job = runner._waiting[source];
            if (!job || data["exit code"] === undefined)
                return;
            delete runner._waiting[source];
            engine.disconnectSource(source);
            job.done(data["exit code"], data.stdout || "");
        }
    }

    // A helper that never returns shouldn't wedge the widget.
    Timer {
        id: reaper
        interval: 5000
        repeat: true
        onTriggered: {
            const now = Date.now();
            let left = 0;
            for (const source in runner._waiting) {
                const job = runner._waiting[source];
                if (!job.interactive && now - job.started > runner.timeoutMs) {
                    delete runner._waiting[source];
                    engine.disconnectSource(source);
                    job.done(-1, "");
                } else if (!job.interactive) {
                    left++;
                }
            }
            if (left === 0)
                stop();
        }
    }
}
