pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "meross.js" as Meross

Kirigami.FormLayout {
    id: page
    property alias cfg_title: titleField.text
    property string cfg_transport
    property alias cfg_pollSeconds: poll.value
    property alias cfg_cloudPollSeconds: cloudPoll.value
    property string cfg_themeMode
    property alias cfg_desktopOpacity: opacitySlider.value
    property var cfg_hiddenDevices: []
    property string cfg_titleDefault: ""
    property string cfg_transportDefault: "auto"
    property int cfg_pollSecondsDefault: 10
    property int cfg_cloudPollSecondsDefault: 60
    property string cfg_themeModeDefault: "system"
    property int cfg_desktopOpacityDefault: 70
    property var cfg_hiddenDevicesDefault: []

    property string account: ""
    property var known: []
    property string accountNote: ""

    // The cached device list and account; no network.
    function reload() {
        helper.run(["cached"], function(exitCode, stdout) {
            const r = Meross.parseResult(exitCode, stdout);
            if (r.ok) {
                page.account = r.data.account || "";
                page.known = r.data.devices || [];
            } else {
                page.accountNote = r.reason;
            }
        });
    }

    function setHidden(uuid, hide) {
        const next = cfg_hiddenDevices.filter(u => u !== uuid);
        if (hide)
            next.push(uuid);
        cfg_hiddenDevices = next;
    }

    Component.onCompleted: reload()
    HelperRunner { id: helper }

    RowLayout {
        Kirigami.FormData.label: i18n("Meross account:")
        Controls.Label {
            text: page.account !== "" ? page.account : i18n("Not signed in")
        }
        Controls.Button {
            text: page.account !== "" ? i18n("Switch account…") : i18n("Sign in…")
            icon.name: "im-user-online"
            onClicked: helper.runInTerminal(["login"], function(code) {
                page.accountNote = code === 127 ? i18n("Konsole wasn't found. Run this in a terminal: python3 %1 login", helper.script) : "";
                page.reload();
            })
        }
        Controls.Button {
            visible: page.account !== ""
            text: i18n("Sign out")
            icon.name: "system-log-out"
            onClicked: helper.run(["logout"], function() { page.reload(); })
        }
    }
    Controls.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.75
        text: page.accountNote !== "" ? page.accountNote
            : i18n("Sign-in opens a terminal so your password never touches Plasma's settings. Only the session token is kept, in ~/.config/meross-deck/session.json.")
    }

    Controls.TextField {
        id: titleField
        Kirigami.FormData.label: i18n("Title:")
        placeholderText: i18n("Home")
        Layout.preferredWidth: Kirigami.Units.gridUnit * 12
    }

    Item { Kirigami.FormData.isSection: true }

    Controls.ComboBox {
        Kirigami.FormData.label: i18n("Connection:")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("Local network first, cloud when away"), value: "auto" },
            { text: i18n("Local network only"), value: "lan" },
            { text: i18n("Cloud only"), value: "cloud" }
        ]
        Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_transport))
        onActivated: page.cfg_transport = currentValue
    }
    Controls.SpinBox {
        id: poll
        Kirigami.FormData.label: i18n("Refresh on the local network:")
        from: 5
        to: 300
        textFromValue: function(v) { return i18n("every %1 s", v); }
        valueFromText: function(t) { return parseInt(t); }
    }
    Controls.SpinBox {
        id: cloudPoll
        Kirigami.FormData.label: i18n("Refresh through the cloud:")
        from: 30
        to: 900
        stepSize: 15
        textFromValue: function(v) { return i18n("every %1 s", v); }
        valueFromText: function(t) { return parseInt(t); }
    }
    Controls.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.75
        text: i18n("The cloud rate is kept slow to stay well clear of Meross's limits. Commands are always sent at once, and the widget re-reads straight after.")
    }

    Item { Kirigami.FormData.isSection: true }

    Controls.ComboBox {
        Kirigami.FormData.label: i18n("Theme:")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("Follow system"), value: "system" },
            { text: i18n("Light"), value: "light" },
            { text: i18n("Dark"), value: "dark" }
        ]
        Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_themeMode))
        onActivated: page.cfg_themeMode = currentValue
    }
    RowLayout {
        Kirigami.FormData.label: i18n("Background opacity:")
        Controls.Slider {
            id: opacitySlider
            from: 0
            to: 100
            stepSize: 5
            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        }
        Controls.Label { text: i18n("%1%", opacitySlider.value) }
    }

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Devices")
        visible: page.known.length > 0
    }
    Repeater {
        model: page.known
        delegate: Controls.CheckBox {
            required property var modelData
            Kirigami.FormData.label: modelData.kind === "garage" ? i18n("Garage") : modelData.kind === "light" ? i18n("Light") : i18n("Plug")
            text: modelData.name
            checked: page.cfg_hiddenDevices.indexOf(modelData.uuid) < 0
            onToggled: page.setHidden(modelData.uuid, !checked)
        }
    }
}
