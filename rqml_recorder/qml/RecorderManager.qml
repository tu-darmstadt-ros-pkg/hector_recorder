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
 * Also supports local recording directly in rqml via BagRecorderEngine.
 */
Rectangle {
    id: root
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(600, 400)
    color: palette.base

    readonly property string _localKey: "__local__"

    //! Local user identity for recorded_by metadata (fetched once on startup)
    property string _localRecordedBy: ""

    Component.onCompleted: {
        if (!context.selectedRecorder)
            context.selectedRecorder = "";
        if (context.autoRefresh === undefined)
            context.autoRefresh = true;
        // Fetch local user identity for recorded_by
        _localUserScanner.fetchRecorderInfo(function(info) {
            _localRecordedBy = info.recordedBy || "";
        });
        // Delay initial discovery to ensure all child components are ready
        Qt.callLater(d.discoverRecorders);
    }

    // Scanner used only to fetch local user info
    LocalBagScanner { id: _localUserScanner }

    // ========================================================================
    // Private Data
    // ========================================================================

    QtObject {
        id: d

        // Map of key -> interface instance (status topics for remote, _localKey for local)
        property var recorderInterfaces: ({})

        // List of all entries for the ComboBox (local + discovered remote topics)
        property var recorderEntries: []

        // Display names for ComboBox entries
        property var recorderLabels: []

        // Currently selected interface (set imperatively, not via binding,
        // because QML cannot track property access on plain JS object maps)
        property var currentInterface: null

        // Whether the current interface is the local recorder
        readonly property bool isLocal: currentInterface && currentInterface.isLocal === true

        function _updateCurrentInterface() {
            currentInterface = recorderInterfaces[context.selectedRecorder] || null;
        }

        function discoverRecorders() {
            let topics = Ros2.queryTopics("hector_recorder_msgs/msg/RecorderStatus");

            // Ensure local interface exists
            if (!recorderInterfaces[_localKey]) {
                let iface = localInterfaceComponent.createObject(root);
                if (iface) {
                    recorderInterfaces[_localKey] = iface;
                }
            }

            // Create interfaces for new remote topics
            let changed = false;
            for (let i = 0; i < topics.length; i++) {
                let topic = topics[i];
                if (!recorderInterfaces[topic]) {
                    let iface = recorderInterfaceComponent.createObject(root, {
                        statusTopic: topic,
                        enabled: true,
                        recordedBy: root._localRecordedBy
                    });
                    if (!iface) {
                        console.warn("RecorderManager: failed to create interface for", topic);
                        continue;
                    }
                    recorderInterfaces[topic] = iface;
                    changed = true;
                }
            }

            // Build entries: local first, then remote topics
            let entries = [_localKey];
            let labels = ["\u2B24 Bag Recorder"];
            for (let i = 0; i < topics.length; i++) {
                entries.push(topics[i]);
                labels.push(topics[i]);
            }

            if (changed || recorderEntries.length !== entries.length) {
                recorderEntries = entries;
                recorderLabels = labels;
            }

            // Auto-select local if nothing selected or selection is stale
            if (!context.selectedRecorder || !recorderInterfaces[context.selectedRecorder]) {
                context.selectedRecorder = _localKey;
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

    Component {
        id: localInterfaceComponent
        LocalRecorderInterface {}
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
                model: d.recorderLabels

                // Keep currentIndex in sync when model or selection changes
                function _syncIndex() {
                    let idx = d.recorderEntries.indexOf(context.selectedRecorder);
                    if (idx >= 0) currentIndex = idx;
                }

                Component.onCompleted: _syncIndex()
                onModelChanged: _syncIndex()

                onActivated: function(index) {
                    if (index >= 0 && index < d.recorderEntries.length) {
                        context.selectedRecorder = d.recorderEntries[index];
                        d._updateCurrentInterface();
                    }
                }
            }

            RefreshButton {
                onClicked: d.discoverRecorders()
            }
        }

        // --------------------------------------------------------------------
        // WiFi Warning (shown when local recorder is selected)
        // --------------------------------------------------------------------

        Rectangle {
            Layout.fillWidth: true
            height: wifiWarningLabel.implicitHeight + 12
            radius: 4
            color: Material.color(Material.Orange, Material.Shade100)
            visible: d.isLocal

            Label {
                id: wifiWarningLabel
                anchors.fill: parent
                anchors.margins: 6
                text: "\u26A0 Local recording pulls data over the network. " +
                      "For high-bandwidth topics (cameras, point clouds), prefer the remote recorder."
                wrapMode: Text.Wrap
                font.pixelSize: 11
                color: Material.color(Material.Orange, Material.Shade900)
            }
        }

        // --------------------------------------------------------------------
        // Machine Info (fetched via GetRecorderInfo service, hidden for local)
        // --------------------------------------------------------------------

        RowLayout {
            id: machineInfoRow
            Layout.fillWidth: true
            spacing: 12
            visible: !d.isLocal && d.currentInterface && d.currentInterface.status

            property string _hostname: ""
            property string _recordedBy: ""

            function _fetchInfo() {
                if (!d.currentInterface || !d.currentInterface.recorderNamespace) return;
                d.currentInterface.fetchRecorderInfo(function(info) {
                    machineInfoRow._hostname = info.hostname;
                    machineInfoRow._recordedBy = info.recordedBy;
                });
            }

            // recorderNamespace is set from the first status message, so it may
            // be empty when the interface is first assigned. We listen for both
            // events: interface change (may already have namespace) and namespace
            // change (fires when first status arrives).
            Connections {
                target: d.currentInterface
                function onRecorderNamespaceChanged() {
                    machineInfoRow._fetchInfo();
                }
            }

            Connections {
                target: d
                function onCurrentInterfaceChanged() {
                    machineInfoRow._hostname = "";
                    machineInfoRow._recordedBy = "";
                    if (!d.isLocal) machineInfoRow._fetchInfo();
                }
            }

            Label {
                text: "Host: " + parent._hostname
                font.pixelSize: 11
                opacity: 0.7
            }

            Rectangle { width: 1; height: 14; color: palette.mid; opacity: 0.4 }

            Label {
                text: "User: " + parent._recordedBy
                font.pixelSize: 11
                opacity: 0.7
            }

            Rectangle { width: 1; height: 14; color: palette.mid; opacity: 0.4 }

            Label {
                property var s: d.currentInterface ? d.currentInterface.status : null
                text: "Node: " + (s ? s.node_name : "")
                font.pixelSize: 11
                opacity: 0.7
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
                                case "idle": return palette.text;
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
                        ToolTip.text: d.isLocal && d.currentInterface && d.currentInterface.selectedTopicCount === 0
                            ? "Configure topics first (click Settings)"
                            : "Start a new recording"
                        ToolTip.visible: hovered
                        enabled: d.currentInterface &&
                            (d.currentInterface.state === "idle" || d.currentInterface.state === "disconnected") &&
                            (!d.isLocal || d.currentInterface.selectedTopicCount > 0)
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

                // Config Info (local recorder only)
                Label {
                    Layout.fillWidth: true
                    visible: d.isLocal && d.currentInterface
                    font.pixelSize: 11
                    opacity: 0.7
                    text: {
                        if (!d.currentInterface || !d.isLocal) return "";
                        let sel = d.currentInterface.selectedTopicCount;
                        let avail = d.currentInterface.availableTopicCount;
                        if (sel === 0 && avail === 0)
                            return "No topics configured. Click Settings to select topics.";
                        if (sel === 0)
                            return "No topics selected (0 of " + avail + " available). Click Settings to select topics.";
                        return "Selected " + sel + " of " + avail + " available topic" + (avail !== 1 ? "s" : "") + " for recording.";
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
                        opacity: 0.7
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
        // Delay bag refresh until after the StackLayout finishes its geometry pass
        Timer {
            id: bagRefreshTimer
            interval: 50
            onTriggered: bagBrowser.refresh()
        }
        Connections {
            target: tabBar
            function onCurrentIndexChanged() {
                if (tabBar.currentIndex === 1) {
                    bagRefreshTimer.restart();
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
                property int remoteCount: d.recorderEntries.length - 1
                text: d.isLocal ? "Local" : remoteCount + " remote recorder" + (remoteCount !== 1 ? "s" : "")
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
        visible: !d.currentInterface
        text: "No recorder selected."
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
        width: 450
        height: 220
        anchors.centerIn: parent
        padding: 16

        background: Rectangle {
            color: palette.window
            border.color: palette.mid
            radius: 8
        }

        onOpened: {
            bagNameField.text = "";
            // Fetch the raw configured output path (e.g. "~/bags/") from the
            // config YAML, not from status.output_dir which holds the resolved
            // path of the last recording.
            outputDirField.text = "";
            if (d.currentInterface) {
                d.currentInterface.fetchConfig(function(yaml) {
                    let m = yaml.match(/^output:\s*"?([^"\n]*)"?$/m);
                    let dir = m ? m[1] : "";
                    // Strip any trailing rosbag2_* timestamp folder that may leak
                    // from storage_options.uri after a previous recording
                    dir = dir.replace(/\/rosbag2_[^/]+\/?$/, "/");
                    if (dir.length > 0 && dir[dir.length - 1] !== "/")
                        dir += "/";
                    outputDirField.text = dir;
                });
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: "Start Recording"
                font.bold: true
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 6

                Label { text: "Directory:" }
                TextField {
                    id: outputDirField
                    Layout.fillWidth: true
                    placeholderText: "~/bags/"
                }

                Label { text: "Name:" }
                TextField {
                    id: bagNameField
                    Layout.fillWidth: true
                    placeholderText: "auto (rosbag2_YYYY_MM_DD-HH_mm_ss)"
                }
            }

            Label {
                text: bagNameField.text
                    ? "Bag folder: " + outputDirField.text + bagNameField.text
                    : "A timestamped subfolder will be created automatically."
                font.pixelSize: 11
                opacity: 0.7
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                elide: Text.ElideMiddle
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
                            let dir = outputDirField.text;
                            let name = bagNameField.text.trim();
                            if (name) {
                                // Ensure directory has trailing slash before appending name
                                if (dir.length > 0 && dir[dir.length - 1] !== "/")
                                    dir += "/";
                                d.currentInterface.startRecording(dir + name);
                            } else {
                                d.currentInterface.startRecording(dir);
                            }
                        }
                        outputDirDialog.close();
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
