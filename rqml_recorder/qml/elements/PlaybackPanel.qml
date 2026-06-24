import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RQml.Fonts
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

    //! Cached count of selected topics in the filter (recomputed on every mutation)
    property int selectedTopicCount: 0

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
                objectName: "playbackPanelStateLabel"
                text: engine ? engine.state.charAt(0).toUpperCase() + engine.state.slice(1) : ""
                font.bold: true
            }

            Label {
                objectName: "playbackPanelBagNameLabel"
                text: engine ? engine.bagName : ""
                elide: Text.ElideMiddle
                opacity: 0.7
                Layout.fillWidth: true
            }

            Label {
                objectName: "playbackPanelTopicCountLabel"
                text: engine ? engine.topicCount + " topics, " + engine.messageCount + " msgs" : ""
                opacity: 0.5
            }

            Button {
                objectName: "playbackPanelStopButton"
                text: "\u23F9 Stop"
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
                objectName: "playbackPanelCurrentTimeLabel"
                text: engine ? Utils.formatDuration(engine.currentTime) : "0:00:00"
                font.family: "monospace"
                Layout.preferredWidth: 55
            }

            Slider {
                id: progressSlider
                objectName: "playbackPanelProgressSlider"
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
                objectName: "playbackPanelDurationLabel"
                text: engine ? Utils.formatDuration(engine.duration) : "0:00:00"
                font.family: "monospace"
                Layout.preferredWidth: 55
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
                objectName: "playbackPanelStepBackButton"
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
                objectName: "playbackPanelPlayPauseButton"
                text: engine && engine.state === "playing" ? IconFont.iconPause : IconFont.iconPlay
                font.family: IconFont.name
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
                objectName: "playbackPanelStepForwardButton"
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
            Rectangle { width: 1; height: 24; color: palette.text; opacity: 0.3 }

            // Speed control
            Label {
                text: "Speed:"
                opacity: 0.7
            }

            SpinBox {
                id: rateSpinBox
                objectName: "playbackPanelRateSpinBox"
                from: 1; to: 2000        // 0.01x – 20.0x stored as integers × 100
                stepSize: 25             // 0.25x per step
                editable: true
                implicitWidth: 130
                enabled: engine && engine.state !== "idle"

                property bool _syncing: false

                value: 100  // default 1.00x

                // Display as e.g. "1.00x"
                textFromValue: function(v) { return (v / 100).toFixed(2) + "x" }
                valueFromText: function(t) {
                    let n = parseFloat(t.replace("x", ""));
                    if (isNaN(n)) return rateSpinBox.value;
                    return Math.round(Math.max(0.01, Math.min(20.0, n)) * 100);
                }

                onValueModified: {
                    if (engine && !_syncing)
                        engine.rate = value / 100.0;
                }

                Connections {
                    target: engine
                    function onRateChanged() {
                        rateSpinBox._syncing = true;
                        rateSpinBox.value = Math.round(engine.rate * 100);
                        rateSpinBox._syncing = false;
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Loop toggle
            Button {
                objectName: "playbackPanelLoopButton"
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
                objectName: "playbackPanelClockCheckbox"
                text: "Publish /clock"
                checked: engine ? engine.clockEnabled : false
                onToggled: engine.clockEnabled = checked
                ToolTip.text: "Publish bag timestamps on /clock for nodes using use_sim_time"
                ToolTip.visible: hovered
                ToolTip.delay: 500
            }

            Item { Layout.fillWidth: true }

            // Error message
            Label {
                objectName: "playbackPanelErrorLabel"
                text: engine && engine.errorMessage ? engine.errorMessage : ""
                color: Material.color(Material.Red)
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
                objectName: "playbackPanelTopicFilterToggle"
                text: (topicFilterExpanded ? "\u25BC" : "\u25B6") + " Topic Filter"
                flat: true
                property bool topicFilterExpanded: false
                onClicked: topicFilterExpanded = !topicFilterExpanded
            }

            Label {
                objectName: "playbackPanelTopicSelectedCountLabel"
                text: engine ? root.selectedTopicCount + " / " + engine.topicCount + " selected" : ""
                opacity: 0.5
            }

            Item { Layout.fillWidth: true }

            Button {
                objectName: "playbackPanelTopicAllButton"
                text: "All"
                flat: true
                visible: topicFilterToggle.topicFilterExpanded
                onClicked: _setAllTopics(true)
            }

            Button {
                objectName: "playbackPanelTopicNoneButton"
                text: "None"
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
                    objectName: "playbackPanelTopicCheckbox_" + index
                    text: model.topic
                    checked: model.selected
                    onToggled: {
                        topicFilterModel.set(index, { selected: checked });
                        if (engine) engine.setTopicEnabled(model.topic, checked);
                        root._updateSelectedCount();
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
        _updateSelectedCount();
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

    function _updateSelectedCount() {
        let count = 0;
        for (let i = 0; i < topicFilterModel.count; i++) {
            if (topicFilterModel.get(i).selected) count++;
        }
        root.selectedTopicCount = count;
    }

    function _setAllTopics(selected) {
        for (let i = 0; i < topicFilterModel.count; i++) {
            topicFilterModel.set(i, { selected: selected });
            if (engine) engine.setTopicEnabled(topicFilterModel.get(i).topic, selected);
        }
        _updateSelectedCount();
    }
}
