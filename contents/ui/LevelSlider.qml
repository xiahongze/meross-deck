import QtQuick
import org.kde.kirigami as Kirigami

// A thin 1–100 slider. `track` paints the groove (e.g. a warm-to-cool ramp);
// without one, the filled part takes the tone.
Item {
    id: slider
    property real value: 50
    property real from: 1
    property real to: 100
    property color tone: "steelblue"
    property color ink: "white"
    property Gradient track: null
    property bool interactive: true
    signal moved(int value)

    readonly property real fraction: (value - from) / (to - from)
    implicitWidth: Kirigami.Units.gridUnit * 8
    implicitHeight: Kirigami.Units.gridUnit * 0.9
    opacity: interactive ? 1 : 0.45

    Rectangle {
        id: groove
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 5
        radius: 2.5
        color: Qt.alpha(slider.ink, 0.14)
        gradient: slider.track
    }
    Rectangle {
        visible: slider.track === null
        anchors.verticalCenter: parent.verticalCenter
        width: knob.x + knob.width / 2
        height: 5
        radius: 2.5
        color: slider.tone
    }
    Rectangle {
        id: knob
        width: Kirigami.Units.gridUnit * 0.8
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: (slider.width - width) * Math.max(0, Math.min(1, slider.fraction))
        color: "white"
        border.color: Qt.alpha("black", 0.18)
        scale: drag.active || press.pressed ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    function _valueAt(px) {
        const f = Math.max(0, Math.min(1, (px - knob.width / 2) / (width - knob.width)));
        return Math.round(from + f * (to - from));
    }
    function _set(px) {
        const v = _valueAt(px);
        if (v !== Math.round(value)) {
            value = v;
            moved(v);
        }
    }

    HoverHandler { enabled: slider.interactive; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: press; enabled: slider.interactive; onTapped: function(point) { slider._set(point.position.x); } }
    DragHandler {
        id: drag
        enabled: slider.interactive
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        onCentroidChanged: if (active) slider._set(centroid.position.x)
    }
    WheelHandler {
        enabled: slider.interactive
        onWheel: function(event) {
            const v = Math.max(slider.from, Math.min(slider.to, Math.round(slider.value) + (event.angleDelta.y > 0 ? 5 : -5)));
            if (v !== Math.round(slider.value)) {
                slider.value = v;
                slider.moved(v);
            }
        }
    }
}
