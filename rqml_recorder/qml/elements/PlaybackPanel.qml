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

    //! The BagPlayerEngine to control
    property var engine: null

    //! Whether the panel is expanded (visible when a bag is loaded/playing)
    property bool expanded: engine && engine.state !== "idle"

    //! Cached count of selected topics in the filter (recomputed on every mutation)
    property int selectedTopicCount: 0

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
    function _rebuildTopicFilter() {
        topicFilterModel.clear();
        if (!engine)
            return;
        let topics = engine.topicList;
        for (let i = 0; i < topics.length; i++) {
            topicFilterModel.append({
                topic: topics[i],
                selected: true
            });
        }
        _updateSelectedCount();
    }
    function _setAllTopics(selected) {
        for (let i = 0; i < topicFilterModel.count; i++) {
            topicFilterModel.set(i, {
                selected: selected
            });
            if (engine)
                engine.setTopicEnabled(topicFilterModel.get(i).topic, selected);
        }
        _updateSelectedCount();
    }
    function _updateSelectedCount() {
        let count = 0;
        for (let i = 0; i < topicFilterModel.count; i++) {
            if (topicFilterModel.get(i).selected)
                count++;
        }
        root.selectedTopicCount = count;
    }

    clip: true
    color: palette.window
    implicitHeight: expanded ? contentLayout.implicitHeight + 16 : 0
    radius: 4
    visible: implicitHeight > 0

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
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
                color: {
                    if (!engine)
                        return "gray";
                    switch (engine.state) {
                    case "playing":
                        return Material.color(Material.Green);
                    case "paused":
                        return Material.color(Material.Orange);
                    case "finished":
                        return palette.mid;
                    default:
                        return palette.mid;
                    }
                }
                height: 10
                radius: 5
                width: 10
            }
            Label {
                font.bold: true
                objectName: "playbackPanelStateLabel"
                text: engine ? engine.state.charAt(0).toUpperCase() + engine.state.slice(1) : ""
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                objectName: "playbackPanelBagNameLabel"
                opacity: 0.7
                text: engine ? engine.bagName : ""
            }
            Label {
                objectName: "playbackPanelTopicCountLabel"
                opacity: 0.5
                text: engine ? engine.topicCount + " topics, " + engine.messageCount + " msgs" : ""
            }
            Button {
                enabled: engine && engine.state !== "idle"
                flat: true
                objectName: "playbackPanelStopButton"
                text: "\u23F9 Stop"

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
                Layout.preferredWidth: 55
                font.family: "monospace"
                objectName: "playbackPanelCurrentTimeLabel"
                text: engine ? Utils.formatDuration(engine.currentTime) : "0:00:00"
            }
            Slider {
                id: progressSlider

                // Avoid binding loop: only update from engine when not dragging
                property bool _userDragging: false

                Layout.fillWidth: true
                enabled: engine && (engine.state === "playing" || engine.state === "paused" || engine.state === "loaded" || engine.state === "finished")
                from: 0
                objectName: "playbackPanelProgressSlider"
                to: 1
                value: engine ? engine.progress : 0

                onPressedChanged: {
                    _userDragging = pressed;
                    if (!pressed && engine) {
                        engine.seek(value * engine.duration);
                    }
                }

                Connections {
                    function onProgressChanged() {
                        if (!progressSlider._userDragging) {
                            progressSlider.value = engine.progress;
                        }
                    }

                    target: engine
                }
            }
            Label {
                Layout.preferredWidth: 55
                font.family: "monospace"
                objectName: "playbackPanelDurationLabel"
                text: engine ? Utils.formatDuration(engine.duration) : "0:00:00"
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
                ToolTip.text: "Seek to start"
                ToolTip.visible: hovered
                enabled: engine && engine.state !== "idle"
                flat: true
                font.pixelSize: 16
                implicitHeight: 32
                implicitWidth: 36
                objectName: "playbackPanelStepBackButton"
                text: "\u23EE"

                onClicked: engine.seek(0)
            }

            // Play / Pause toggle
            Button {
                ToolTip.text: engine && engine.state === "playing" ? "Pause" : "Play"
                ToolTip.visible: hovered
                enabled: engine && engine.state !== "idle"
                flat: true
                font.family: IconFont.name
                font.pixelSize: 18
                highlighted: true
                implicitHeight: 32
                implicitWidth: 44
                objectName: "playbackPanelPlayPauseButton"
                text: engine && engine.state === "playing" ? IconFont.iconPause : IconFont.iconPlay

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
                ToolTip.text: "Step forward (next message)"
                ToolTip.visible: hovered
                enabled: engine && (engine.state === "paused" || engine.state === "loaded")
                flat: true
                font.pixelSize: 16
                implicitHeight: 32
                implicitWidth: 36
                objectName: "playbackPanelStepForwardButton"
                text: "\u23ED"

                onClicked: engine.stepForward()
            }

            // Separator
            Rectangle {
                color: palette.text
                height: 24
                opacity: 0.3
                width: 1
            }

            // Speed control
            Label {
                opacity: 0.7
                text: "Speed:"
            }
            SpinBox {
                id: rateSpinBox

                property bool _syncing: false

                editable: true
                enabled: engine && engine.state !== "idle"
                from: 1
                implicitWidth: 130
                objectName: "playbackPanelRateSpinBox"
                stepSize: 25             // 0.25x per step

                // Display as e.g. "1.00x"
                textFromValue: function (v) {
                    return (v / 100).toFixed(2) + "x";
                }
                to: 2000        // 0.01x – 20.0x stored as integers × 100
                value: 100  // default 1.00x

                valueFromText: function (t) {
                    let n = parseFloat(t.replace("x", ""));
                    if (isNaN(n))
                        return rateSpinBox.value;
                    return Math.round(Math.max(0.01, Math.min(20.0, n)) * 100);
                }

                onValueModified: {
                    if (engine && !_syncing)
                        engine.rate = value / 100.0;
                }

                Connections {
                    function onRateChanged() {
                        rateSpinBox._syncing = true;
                        rateSpinBox.value = Math.round(engine.rate * 100);
                        rateSpinBox._syncing = false;
                    }

                    target: engine
                }
            }
            Item {
                Layout.fillWidth: true
            }

            // Loop toggle
            Button {
                ToolTip.text: "Loop playback"
                ToolTip.visible: hovered
                checkable: true
                checked: engine && engine.looping
                flat: true
                font.pixelSize: 16
                implicitHeight: 32
                implicitWidth: 36
                objectName: "playbackPanelLoopButton"
                text: "\u21BB"  // clockwise arrow (loop)

                contentItem: Label {
                    color: parent.checked ? Material.color(Material.Blue) : palette.text
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    opacity: parent.checked ? 1.0 : 0.6
                    text: parent.text
                    verticalAlignment: Text.AlignVCenter
                }

                onToggled: engine.looping = checked
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

                ToolTip.delay: 500
                ToolTip.text: "Publish bag timestamps on /clock for nodes using use_sim_time"
                ToolTip.visible: hovered
                checked: engine ? engine.clockEnabled : false
                objectName: "playbackPanelClockCheckbox"
                text: "Publish /clock"

                onToggled: engine.clockEnabled = checked
            }
            Item {
                Layout.fillWidth: true
            }

            // Error message
            Label {
                Layout.maximumWidth: 300
                color: Material.color(Material.Red)
                elide: Text.ElideRight
                objectName: "playbackPanelErrorLabel"
                text: engine && engine.errorMessage ? engine.errorMessage : ""
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

                property bool topicFilterExpanded: false

                flat: true
                objectName: "playbackPanelTopicFilterToggle"
                text: (topicFilterExpanded ? "\u25BC" : "\u25B6") + " Topic Filter"

                onClicked: topicFilterExpanded = !topicFilterExpanded
            }
            Label {
                objectName: "playbackPanelTopicSelectedCountLabel"
                opacity: 0.5
                text: engine ? root.selectedTopicCount + " / " + engine.topicCount + " selected" : ""
            }
            Item {
                Layout.fillWidth: true
            }
            Button {
                flat: true
                objectName: "playbackPanelTopicAllButton"
                text: "All"
                visible: topicFilterToggle.topicFilterExpanded

                onClicked: _setAllTopics(true)
            }
            Button {
                flat: true
                objectName: "playbackPanelTopicNoneButton"
                text: "None"
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
                    checked: model.selected
                    objectName: "playbackPanelTopicCheckbox_" + index
                    text: model.topic

                    onToggled: {
                        topicFilterModel.set(index, {
                            selected: checked
                        });
                        if (engine)
                            engine.setTopicEnabled(model.topic, checked);
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
        function onMetadataChanged() {
            _rebuildTopicFilter();
        }

        target: engine
    }
}
