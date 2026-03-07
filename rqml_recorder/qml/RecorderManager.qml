import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts
import RqmlRecorder
import "interfaces"
import "elements"
import "utils.js" as Utils

/**
 * RQML plugin for controlling and monitoring hector_recorder instances.
 * Discovers multiple recorders via their status topics and provides
 * a unified interface for remote control and statistics visualization.
 */
Rectangle {
    id: root
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(600, 400)
    color: palette.base

    Component.onCompleted: {
        if (!context.selectedRecorder)
            context.selectedRecorder = "";
        if (context.autoRefresh === undefined)
            context.autoRefresh = true;
        // Delay initial discovery to ensure all child components are ready
        Qt.callLater(d.discoverRecorders);
    }

    // ========================================================================
    // Private Data
    // ========================================================================

    QtObject {
        id: d

        // Map of status topic -> RecorderInterface instance
        property var recorderInterfaces: ({})

        // List of known recorder status topics
        property var recorderTopics: []

        // Currently selected interface (set imperatively, not via binding,
        // because QML cannot track property access on plain JS object maps)
        property var currentInterface: null

        function _updateCurrentInterface() {
            currentInterface = recorderInterfaces[context.selectedRecorder] || null;
        }

        function discoverRecorders() {
            let topics = Ros2.queryTopics("hector_recorder_msgs/msg/RecorderStatus");

            // Create interfaces for new topics
            let changed = false;
            for (let i = 0; i < topics.length; i++) {
                let topic = topics[i];
                if (!recorderInterfaces[topic]) {
                    let iface = recorderInterfaceComponent.createObject(root, {
                        statusTopic: topic,
                        enabled: true
                    });
                    if (!iface) {
                        console.warn("RecorderManager: failed to create interface for", topic);
                        continue;
                    }
                    recorderInterfaces[topic] = iface;
                    changed = true;
                }
            }

            if (changed || recorderTopics.length !== topics.length) {
                recorderTopics = topics;
            }

            // Auto-select first recorder if none selected or selection is stale
            if (topics.length > 0 &&
                (!context.selectedRecorder || !recorderInterfaces[context.selectedRecorder])) {
                context.selectedRecorder = topics[0];
            }

            // Always refresh currentInterface after discovery
            _updateCurrentInterface();
        }

        function formatBytes(bytes) { return Utils.formatBytes(bytes); }
        function formatDuration(duration) { return Utils.formatDuration(duration); }
    }

    Component {
        id: recorderInterfaceComponent
        RecorderInterface {}
    }

    // Periodic discovery refresh
    Timer {
        interval: 5000
        running: context.autoRefresh
        repeat: true
        onTriggered: d.discoverRecorders()
    }

    // ========================================================================
    // UI Layout
    // ========================================================================

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // --------------------------------------------------------------------
        // Header Row: Recorder Selector
        // --------------------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "Recorder:" }

            ComboBox {
                id: recorderSelector
                Layout.fillWidth: true
                model: d.recorderTopics

                // Keep currentIndex in sync when model or selection changes
                function _syncIndex() {
                    let idx = d.recorderTopics.indexOf(context.selectedRecorder);
                    if (idx >= 0) currentIndex = idx;
                }

                Component.onCompleted: _syncIndex()
                onModelChanged: _syncIndex()

                onActivated: function(index) {
                    if (index >= 0 && index < d.recorderTopics.length) {
                        context.selectedRecorder = d.recorderTopics[index];
                        d._updateCurrentInterface();
                    }
                }
            }

            RefreshButton {
                onClicked: d.discoverRecorders()
            }
        }

        // --------------------------------------------------------------------
        // Machine Info
        // --------------------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: d.currentInterface && d.currentInterface.status

            property var s: d.currentInterface ? d.currentInterface.status : null

            Label {
                text: "Host: " + (parent.s ? parent.s.hostname : "")
                font.pixelSize: 11
                color: palette.mid
            }

            Rectangle { width: 1; height: 14; color: palette.mid; opacity: 0.4 }

            Label {
                text: "User: " + (parent.s ? parent.s.recorded_by : "")
                font.pixelSize: 11
                color: palette.mid
            }

            Rectangle { width: 1; height: 14; color: palette.mid; opacity: 0.4 }

            Label {
                text: "Node: " + (parent.s ? parent.s.node_name : "")
                font.pixelSize: 11
                color: palette.mid
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
        }

        // --------------------------------------------------------------------
        // Tab Bar: Recording / Bags
        // --------------------------------------------------------------------

        TabBar {
            id: tabBar
            Layout.fillWidth: true

            TabButton { text: "Recording" }
            TabButton { text: "Bags" }
        }

        // --------------------------------------------------------------------
        // Stacked Content
        // --------------------------------------------------------------------

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // ================================================================
            // Tab 0: Recording (live monitoring + controls)
            // ================================================================

            ColumnLayout {
                spacing: 8

                // Control Bar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: !!d.currentInterface

                    StateIndicator {
                        state: {
                            if (!d.currentInterface) return "unknown";
                            switch (d.currentInterface.state) {
                                case "recording": return "active";
                                case "paused": return "inactive";
                                case "idle": return "unconfigured";
                                case "disconnected": return "unloaded";
                                default: return "unknown";
                            }
                        }
                    }

                    Label {
                        text: d.currentInterface ? d.currentInterface.state.toUpperCase() : "N/A"
                        font.bold: true
                        color: {
                            if (!d.currentInterface) return palette.text;
                            switch (d.currentInterface.state) {
                                case "recording": return Material.color(Material.Green);
                                case "paused": return Material.color(Material.Orange);
                                case "idle": return palette.mid;
                                case "disconnected": return Material.color(Material.Red);
                                default: return palette.text;
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        icon.source: ""
                        text: "\u25B6 Start"
                        font.pixelSize: 12
                        ToolTip.text: "Start a new recording"
                        ToolTip.visible: hovered
                        enabled: d.currentInterface &&
                            (d.currentInterface.state === "idle" || d.currentInterface.state === "disconnected")
                        onClicked: outputDirDialog.open()
                    }

                    Button {
                        text: d.currentInterface && d.currentInterface.state === "paused"
                            ? "\u25B6 Resume" : "\u23F8 Pause"
                        font.pixelSize: 12
                        ToolTip.text: d.currentInterface && d.currentInterface.state === "paused"
                            ? "Resume recording" : "Pause recording"
                        ToolTip.visible: hovered
                        enabled: d.currentInterface &&
                            (d.currentInterface.state === "recording" || d.currentInterface.state === "paused")
                        onClicked: {
                            if (d.currentInterface.state === "paused") {
                                d.currentInterface.resumeRecording();
                            } else {
                                d.currentInterface.pauseRecording();
                            }
                        }
                    }

                    Button {
                        text: "\u23F9 Stop"
                        font.pixelSize: 12
                        ToolTip.text: "Stop the current recording"
                        ToolTip.visible: hovered
                        enabled: d.currentInterface &&
                            (d.currentInterface.state === "recording" || d.currentInterface.state === "paused")
                        onClicked: d.currentInterface.stopRecording()
                    }

                    Button {
                        text: "\u2702 Split"
                        font.pixelSize: 12
                        ToolTip.text: "Split the current bag file"
                        ToolTip.visible: hovered
                        enabled: d.currentInterface && d.currentInterface.state === "recording"
                        onClicked: d.currentInterface.splitBag()
                    }

                    IconButton {
                        text: IconFont.iconSettings
                        tooltipText: "Configure"
                        onClicked: configEditor.open()
                    }
                }

                // Summary Bar
                RowLayout {
                    Layout.fillWidth: true
                    visible: d.currentInterface && d.currentInterface.status
                    spacing: 16

                    Label {
                        property var s: d.currentInterface ? d.currentInterface.status : null
                        text: s ? "Duration: " + d.formatDuration(s.duration)
                                + "  |  Size: " + d.formatBytes(s.size)
                                + "  |  Files: " + (s.files ? s.files.length : 0)
                                + "  |  Topics: " + (s.topics ? s.topics.length : 0)
                            : ""
                        color: palette.mid
                    }
                }

                // Topic Table
                TopicTable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: d.currentInterface ? d.currentInterface.topicsModel : null
                }
            }

            // ================================================================
            // Tab 1: Bag Browser
            // ================================================================

            BagBrowser {
                id: bagBrowser
                recorderInterface: d.currentInterface

                onStatusMessage: function(msg, isError) {
                    serviceStatusLabel.text = (isError ? "\u2717 " : "\u2713 ") + msg;
                    serviceStatusLabel.color = isError ? "red" : "green";
                    statusResetTimer.restart();
                }
            }
        }

        // Auto-refresh bags when switching to Bags tab
        Connections {
            target: tabBar
            function onCurrentIndexChanged() {
                if (tabBar.currentIndex === 1) {
                    bagBrowser.refresh();
                }
            }
        }

        // --------------------------------------------------------------------
        // Status Bar
        // --------------------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true

            Label {
                id: serviceStatusLabel
                color: palette.mid
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                text: {
                    let s = d.currentInterface ? d.currentInterface.status : null;
                    return s ? "Output: " + s.output_dir : "No recorder selected";
                }

                Connections {
                    target: d.currentInterface
                    function onServiceResponse(name, success, message) {
                        serviceStatusLabel.text = (success ? "\u2713 " : "\u2717 ") + name + ": " + message;
                        serviceStatusLabel.color = success ? "green" : "red";
                        statusResetTimer.restart();
                    }
                }

                Timer {
                    id: statusResetTimer
                    interval: 5000
                    onTriggered: {
                        let s = d.currentInterface ? d.currentInterface.status : null;
                        serviceStatusLabel.text = s ? "Output: " + s.output_dir : "No recorder selected";
                        serviceStatusLabel.color = palette.mid;
                    }
                }
            }

            Label {
                text: d.recorderTopics.length + " recorder" + (d.recorderTopics.length !== 1 ? "s" : "")
                color: palette.mid
                font.pixelSize: 11
            }
        }
    }

    // ========================================================================
    // Empty State
    // ========================================================================

    Label {
        anchors.centerIn: parent
        visible: d.recorderTopics.length === 0
        text: "No recorder instances found.\nWaiting for hector_recorder_msgs/msg/RecorderStatus topics..."
        horizontalAlignment: Text.AlignHCenter
        color: palette.mid
    }

    // ========================================================================
    // Dialogs
    // ========================================================================

    // Start recording dialog
    Popup {
        id: outputDirDialog
        modal: true
        width: 400
        height: 140
        anchors.centerIn: parent
        padding: 16

        background: Rectangle {
            color: palette.window
            border.color: palette.mid
            radius: 8
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: "Output Directory (leave empty for default):"
                font.bold: true
            }

            TextField {
                id: outputDirField
                Layout.fillWidth: true
                placeholderText: "/path/to/bags/"
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }

                Button {
                    text: "Cancel"
                    onClicked: outputDirDialog.close()
                }

                Button {
                    text: "Start Recording"
                    highlighted: true
                    onClicked: {
                        if (d.currentInterface) {
                            d.currentInterface.startRecording(outputDirField.text);
                        }
                        outputDirDialog.close();
                        outputDirField.text = "";
                    }
                }
            }
        }
    }

    // Config editor dialog
    ConfigEditor {
        id: configEditor
        recorderInterface: d.currentInterface
        savedConfigNames: PresetStore.presetNames
        onConfigSaved: function(name, yaml) {
            PresetStore.save(name, yaml);
        }
        onConfigDeleted: function(name) {
            PresetStore.remove(name);
        }
    }
}
