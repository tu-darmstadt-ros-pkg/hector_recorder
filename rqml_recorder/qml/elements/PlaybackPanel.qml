import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import "../utils.js" as Utils

/**
 * Transport controls and settings panel for bag playback.
 * Binds to a BagPlayerEngine instance via the `engine` property.
 */
Rectangle {
    id: root
    color: palette.window
    radius: 4

    //! The BagPlayerEngine to control
    property var engine: null

    //! Whether the panel is expanded (visible when a bag is loaded/playing)
    property bool expanded: engine && engine.state !== "idle"

    implicitHeight: expanded ? contentLayout.implicitHeight + 16 : 0
    visible: implicitHeight > 0
    clip: true

    Behavior on implicitHeight {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    // ========================================================================
    // Layout
    // ========================================================================

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        // --------------------------------------------------------------------
        // Header: bag name + state + stop
        // --------------------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // State indicator dot
            Rectangle {
                width: 10; height: 10; radius: 5
                color: {
                    if (!engine) return "gray";
                    switch (engine.state) {
                        case "playing": return Material.color(Material.Green);
                        case "paused": return Material.color(Material.Orange);
                        case "finished": return palette.mid;
                        default: return palette.mid;
                    }
                }
            }

            Label {
                text: engine ? engine.state.charAt(0).toUpperCase() + engine.state.slice(1) : ""
                font.bold: true
                font.pixelSize: 12
            }

            Label {
                text: engine ? engine.bagName : ""
                font.pixelSize: 12
                elide: Text.ElideMiddle
                opacity: 0.7
                Layout.fillWidth: true
            }

            Label {
                text: engine ? engine.topicCount + " topics, " + engine.messageCount + " msgs" : ""
                font.pixelSize: 11
                opacity: 0.5
            }

            Button {
                text: "\u23F9 Stop"
                font.pixelSize: 11
                flat: true
                enabled: engine && engine.state !== "idle"
                onClicked: engine.stop()
            }
        }

        // --------------------------------------------------------------------
        // Progress bar + time display
        // --------------------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: engine ? Utils.formatDuration(engine.currentTime) : "0:00:00"
                font.pixelSize: 11
                font.family: "monospace"
                Layout.preferredWidth: 55
            }

            Slider {
                id: progressSlider
                Layout.fillWidth: true
                from: 0; to: 1
                value: engine ? engine.progress : 0
                enabled: engine && (engine.state === "playing" || engine.state === "paused"
                         || engine.state === "loaded" || engine.state === "finished")

                // Avoid binding loop: only update from engine when not dragging
                property bool _userDragging: false

                onPressedChanged: {
                    _userDragging = pressed;
                    if (!pressed && engine) {
                        engine.seek(value * engine.duration);
                    }
                }

                Connections {
                    target: engine
                    function onProgressChanged() {
                        if (!progressSlider._userDragging) {
                            progressSlider.value = engine.progress;
                        }
                    }
                }
            }

            Label {
                text: engine ? Utils.formatDuration(engine.duration) : "0:00:00"
                font.pixelSize: 11
                font.family: "monospace"
                Layout.preferredWidth: 55
            }

            // Rate display
            Label {
                text: engine ? engine.rate.toFixed(2) + "x" : "1.00x"
                font.bold: true
                font.pixelSize: 12
                Layout.preferredWidth: 50
                horizontalAlignment: Text.AlignRight
            }
        }

        // --------------------------------------------------------------------
        // Transport controls
        // --------------------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            // Step backward (seek to start)
            Button {
                text: "\u23EE"
                font.pixelSize: 16
                flat: true
                implicitWidth: 36; implicitHeight: 32
                ToolTip.text: "Seek to start"
                ToolTip.visible: hovered
                enabled: engine && engine.state !== "idle"
                onClicked: engine.seek(0)
            }

            // Play / Pause toggle
            Button {
                text: engine && engine.state === "playing" ? "\u23F8" : "\u25B6"
                font.pixelSize: 18
                flat: true
                implicitWidth: 44; implicitHeight: 32
                highlighted: true
                ToolTip.text: engine && engine.state === "playing" ? "Pause" : "Play"
                ToolTip.visible: hovered
                enabled: engine && engine.state !== "idle"
                onClicked: {
                    if (engine.state === "playing") {
                        engine.pause();
                    } else if (engine.state === "paused") {
                        engine.resume();
                    } else {
                        // "loaded" or "finished" — start fresh
                        engine.play(_getSelectedTopics());
                    }
                }
            }

            // Step forward (single message)
            Button {
                text: "\u23ED"
                font.pixelSize: 16
                flat: true
                implicitWidth: 36; implicitHeight: 32
                ToolTip.text: "Step forward (next message)"
                ToolTip.visible: hovered
                enabled: engine && (engine.state === "paused" || engine.state === "loaded")
                onClicked: engine.stepForward()
            }

            // Separator
            Rectangle { width: 1; height: 24; color: palette.mid; opacity: 0.3 }

            // Speed presets
            Repeater {
                model: [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0]

                Button {
                    text: modelData + "x"
                    font.pixelSize: 10
                    flat: true
                    implicitWidth: 44; implicitHeight: 28
                    highlighted: engine && Math.abs(engine.rate - modelData) < 0.01
                    onClicked: engine.rate = modelData
                }
            }

            Item { Layout.fillWidth: true }

            // Loop toggle
            Button {
                text: "\u21BB"  // clockwise arrow (loop)
                font.pixelSize: 16
                flat: true
                implicitWidth: 36; implicitHeight: 32
                checkable: true
                checked: engine && engine.looping
                ToolTip.text: "Loop playback"
                ToolTip.visible: hovered
                onToggled: engine.looping = checked

                contentItem: Label {
                    text: parent.text
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: parent.checked ? Material.color(Material.Blue) : palette.text
                    opacity: parent.checked ? 1.0 : 0.6
                }
            }
        }

        // --------------------------------------------------------------------
        // Options row
        // --------------------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            CheckBox {
                id: clockCheckbox
                text: "Publish /clock"
                font.pixelSize: 11
                checked: engine ? engine.clockEnabled : false
                onToggled: engine.clockEnabled = checked
            }

            RowLayout {
                spacing: 4
                visible: clockCheckbox.checked

                Label { text: "at"; font.pixelSize: 11; opacity: 0.7 }
                SpinBox {
                    from: 1; to: 1000
                    value: engine ? engine.clockFrequency : 100
                    editable: true
                    font.pixelSize: 11
                    implicitWidth: 90
                    onValueModified: engine.clockFrequency = value
                }
                Label { text: "Hz"; font.pixelSize: 11; opacity: 0.7 }
            }

            Item { Layout.fillWidth: true }

            // Error message
            Label {
                text: engine && engine.errorMessage ? engine.errorMessage : ""
                color: Material.color(Material.Red)
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.maximumWidth: 300
                visible: text !== ""
            }
        }

        // --------------------------------------------------------------------
        // Topic filter (collapsible)
        // --------------------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Button {
                id: topicFilterToggle
                text: (topicFilterExpanded ? "\u25BC" : "\u25B6") + " Topic Filter"
                font.pixelSize: 11
                flat: true
                property bool topicFilterExpanded: false
                onClicked: topicFilterExpanded = !topicFilterExpanded
            }

            Label {
                text: {
                    if (!engine) return "";
                    let selected = _countSelectedTopics();
                    return selected + " / " + engine.topicCount + " selected";
                }
                font.pixelSize: 11
                opacity: 0.5
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "All"
                font.pixelSize: 10
                flat: true
                visible: topicFilterToggle.topicFilterExpanded
                onClicked: _setAllTopics(true)
            }

            Button {
                text: "None"
                font.pixelSize: 10
                flat: true
                visible: topicFilterToggle.topicFilterExpanded
                onClicked: _setAllTopics(false)
            }
        }

        // Topic checkboxes
        Flow {
            Layout.fillWidth: true
            spacing: 4
            visible: topicFilterToggle.topicFilterExpanded

            Repeater {
                model: topicFilterModel

                CheckBox {
                    text: model.topic
                    font.pixelSize: 11
                    checked: model.selected
                    onToggled: {
                        topicFilterModel.set(index, { selected: checked });
                        if (engine) engine.setTopicEnabled(model.topic, checked);
                    }
                }
            }
        }
    }

    // ========================================================================
    // Topic Filter Model
    // ========================================================================

    ListModel {
        id: topicFilterModel
    }

    // Rebuild topic filter model when engine's topic list changes
    Connections {
        target: engine
        function onMetadataChanged() {
            _rebuildTopicFilter();
        }
    }

    function _rebuildTopicFilter() {
        topicFilterModel.clear();
        if (!engine) return;
        let topics = engine.topicList;
        for (let i = 0; i < topics.length; i++) {
            topicFilterModel.append({ topic: topics[i], selected: true });
        }
    }

    function _getSelectedTopics() {
        let result = [];
        let allSelected = true;
        for (let i = 0; i < topicFilterModel.count; i++) {
            let item = topicFilterModel.get(i);
            if (item.selected) {
                result.push(item.topic);
            } else {
                allSelected = false;
            }
        }
        // Return empty list (= all topics) if all are selected
        return allSelected ? [] : result;
    }

    function _countSelectedTopics() {
        let count = 0;
        for (let i = 0; i < topicFilterModel.count; i++) {
            if (topicFilterModel.get(i).selected) count++;
        }
        return count;
    }

    function _setAllTopics(selected) {
        for (let i = 0; i < topicFilterModel.count; i++) {
            topicFilterModel.set(i, { selected: selected });
            if (engine) engine.setTopicEnabled(topicFilterModel.get(i).topic, selected);
        }
    }
}
