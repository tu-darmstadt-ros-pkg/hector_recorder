import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts
import RQml.Recorder
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

    readonly property string _localKey: "__local__"

    //! Local user identity for recorded_by metadata (fetched once on startup)
    property string _localRecordedBy: ""
    property var kddockwidgets_min_size: Qt.size(600, 400)

    //! Initialize the BagBrowser path from the current recorder's config output dir
    function _initBagBrowserPath() {
        if (!d.currentInterface)
            return;

        // Only set path if BagBrowser doesn't have one yet
        if (bagBrowser.currentPath && bagBrowser.currentPath !== "")
            return;

        d.currentInterface.fetchConfig(function (yaml) {
            let m = yaml.match(/^output:\s*"?([^"\n]*)"?$/m);
            let dir = m ? m[1] : "";
            // Strip trailing rosbag2_* timestamp folder
            dir = dir.replace(/\/rosbag2_[^/]+\/?$/, "/");
            if (dir && dir !== "") {
                bagBrowser.homePath = dir;
                bagBrowser.setPath(dir);
            }
        });
    }

    anchors.fill: parent
    color: palette.base

    Component.onCompleted: {
        // Fetch local user identity for recorded_by
        _localUserScanner.fetchRecorderInfo(function (info) {
            _localRecordedBy = info.recordedBy || "";
        });
        // Delay initial discovery to ensure all child components are ready
        Qt.callLater(d.discoverRecorders);
    }

    // Scanner used only to fetch local user info
    LocalBagScanner {
        id: _localUserScanner

    }

    // ========================================================================
    // Private Data
    // ========================================================================

    QtObject {
        id: d

        // Whether a new recording can be started with the current interface
        readonly property bool canStartRecording: currentInterface && (currentInterface.state === "idle" || currentInterface.state === "disconnected") && (!isLocal || currentInterface.selectedTopicCount > 0)

        // Currently selected interface (set imperatively, not via binding,
        // because QML cannot track property access on plain JS object maps)
        property var currentInterface: null

        // Whether the current interface is the local recorder
        readonly property bool isLocal: currentInterface && currentInterface.isLocal === true

        // List of all entries for the ComboBox (local + discovered remote topics)
        property var recorderEntries: []

        // Map of key -> interface instance (status topics for remote, _localKey for local)
        property var recorderInterfaces: ({})

        // Display names for ComboBox entries
        property var recorderLabels: []

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
        function formatBytes(bytes) {
            return Utils.formatBytes(bytes);
        }
        function formatDuration(duration) {
            return Utils.formatDuration(duration);
        }
    }
    Component {
        id: recorderInterfaceComponent

        RecorderInterface {
        }
    }
    Component {
        id: localInterfaceComponent

        LocalRecorderInterface {
        }
    }

    // Periodic discovery refresh
    Timer {
        interval: 5000
        repeat: true
        running: context.autoRefresh ?? true

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

            Label {
                text: "Recorder:"
            }
            ComboBox {
                id: recorderSelector

                // Keep currentIndex in sync when model or selection changes
                function _syncIndex() {
                    let idx = d.recorderEntries.indexOf(context.selectedRecorder);
                    if (idx >= 0)
                        currentIndex = idx;
                }

                Layout.fillWidth: true
                model: d.recorderLabels
                objectName: "recorderManagerRecorderSelector"

                Component.onCompleted: _syncIndex()
                onActivated: function (index) {
                    if (index >= 0 && index < d.recorderEntries.length) {
                        context.selectedRecorder = d.recorderEntries[index];
                        d._updateCurrentInterface();
                    }
                }
                onModelChanged: _syncIndex()
            }
            RefreshButton {
                objectName: "recorderManagerRefreshButton"

                onClicked: d.discoverRecorders()
            }
        }

        // --------------------------------------------------------------------
        // WiFi Warning (shown when local recorder is selected)
        // --------------------------------------------------------------------

        Rectangle {
            Layout.fillWidth: true
            color: Material.color(Material.Orange, Material.Shade100)
            height: wifiWarningLabel.implicitHeight + 12
            objectName: "recorderManagerWifiWarning"
            radius: 4
            visible: d.isLocal

            Label {
                id: wifiWarningLabel

                anchors.fill: parent
                anchors.margins: 6
                color: Material.color(Material.Orange, Material.Shade900)
                objectName: "recorderManagerWifiWarningLabel"
                text: "\u26A0 Local recording pulls data over the network. " + "For high-bandwidth topics (cameras, point clouds), prefer the remote recorder."
                wrapMode: Text.Wrap
            }
        }

        // --------------------------------------------------------------------
        // Machine Info (fetched via GetRecorderInfo service, hidden for local)
        // --------------------------------------------------------------------

        RowLayout {
            id: machineInfoRow

            property string _hostname: ""
            property string _recordedBy: ""

            function _fetchInfo() {
                if (!d.currentInterface || !d.currentInterface.recorderNamespace)
                    return;
                d.currentInterface.fetchRecorderInfo(function (info) {
                    machineInfoRow._hostname = info.hostname;
                    machineInfoRow._recordedBy = info.recordedBy;
                });
            }

            Layout.fillWidth: true
            objectName: "recorderManagerMachineInfoRow"
            spacing: 12
            visible: !d.isLocal && d.currentInterface && d.currentInterface.status

            // recorderNamespace is set from the first status message, so it may
            // be empty when the interface is first assigned. We listen for both
            // events: interface change (may already have namespace) and namespace
            // change (fires when first status arrives).
            Connections {
                function onRecorderNamespaceChanged() {
                    machineInfoRow._fetchInfo();
                }

                target: d.currentInterface
            }
            Connections {
                function onCurrentInterfaceChanged() {
                    machineInfoRow._hostname = "";
                    machineInfoRow._recordedBy = "";
                    if (!d.isLocal)
                        machineInfoRow._fetchInfo();
                }

                target: d
            }
            Label {
                objectName: "recorderManagerHostLabel"
                opacity: 0.7
                text: "Host: " + parent._hostname
            }
            Rectangle {
                color: palette.text
                height: 14
                opacity: 0.15
                width: 1
            }
            Label {
                objectName: "recorderManagerUserLabel"
                opacity: 0.7
                text: "User: " + parent._recordedBy
            }
            Rectangle {
                color: palette.text
                height: 14
                opacity: 0.15
                width: 1
            }
            Label {
                property var s: d.currentInterface ? d.currentInterface.status : null

                Layout.fillWidth: true
                elide: Text.ElideMiddle
                objectName: "recorderManagerNodeLabel"
                opacity: 0.7
                text: "Node: " + (s ? s.node_name : "")
            }
        }

        // --------------------------------------------------------------------
        // Tab Bar: Recording / Bags
        // --------------------------------------------------------------------

        TabBar {
            id: tabBar

            Layout.fillWidth: true
            objectName: "recorderManagerTabBar"

            TabButton {
                objectName: "recorderManagerRecordingTab"
                text: "Recording"
            }
            TabButton {
                objectName: "recorderManagerBagsTab"
                text: "Bags"
            }
        }

        // --------------------------------------------------------------------
        // Stacked Content
        // --------------------------------------------------------------------

        StackLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
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
                        objectName: "recorderManagerStateIndicator"
                        state: {
                            if (!d.currentInterface)
                                return "unknown";
                            switch (d.currentInterface.state) {
                            case "recording":
                                return "active";
                            case "paused":
                                return "inactive";
                            case "idle":
                                return "unconfigured";
                            case "disconnected":
                                return "unloaded";
                            default:
                                return "unknown";
                            }
                        }
                    }
                    Label {
                        color: {
                            if (!d.currentInterface)
                                return palette.text;
                            switch (d.currentInterface.state) {
                            case "recording":
                                return Material.color(Material.Green);
                            case "paused":
                                return Material.color(Material.Orange);
                            case "idle":
                                return palette.text;
                            case "disconnected":
                                return Material.color(Material.Red);
                            default:
                                return palette.text;
                            }
                        }
                        font.bold: true
                        objectName: "recorderManagerStateLabel"
                        text: d.currentInterface ? d.currentInterface.state.toUpperCase() : "N/A"
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Button {
                        ToolTip.text: d.isLocal && d.currentInterface && d.currentInterface.selectedTopicCount === 0 ? "Configure topics first (click Settings)" : "Start a new recording"
                        ToolTip.visible: hovered
                        enabled: d.canStartRecording
                        icon.source: ""
                        objectName: "recorderManagerStartButton"
                        text: "▶ Start"

                        onClicked: outputDirDialog.open()
                    }
                    Button {
                        ToolTip.text: d.currentInterface && d.currentInterface.state === "paused" ? "Resume recording" : "Pause recording"
                        ToolTip.visible: hovered
                        enabled: d.currentInterface && (d.currentInterface.state === "recording" || d.currentInterface.state === "paused")
                        objectName: "recorderManagerPauseResumeButton"
                        text: d.currentInterface && d.currentInterface.state === "paused" ? "\u25B6 Resume" : "\u23F8 Pause"

                        onClicked: {
                            if (d.currentInterface.state === "paused") {
                                d.currentInterface.resumeRecording();
                            } else {
                                d.currentInterface.pauseRecording();
                            }
                        }
                    }
                    Button {
                        ToolTip.text: "Stop the current recording"
                        ToolTip.visible: hovered
                        enabled: d.currentInterface && (d.currentInterface.state === "recording" || d.currentInterface.state === "paused")
                        objectName: "recorderManagerStopButton"
                        text: "\u23F9 Stop"

                        onClicked: d.currentInterface.stopRecording()
                    }
                    Button {
                        ToolTip.text: "Split the current bag file"
                        ToolTip.visible: hovered
                        enabled: d.currentInterface && d.currentInterface.state === "recording"
                        objectName: "recorderManagerSplitButton"
                        text: "\u2702 Split"

                        onClicked: d.currentInterface.splitBag()
                    }
                    IconButton {
                        objectName: "recorderManagerSettingsButton"
                        text: IconFont.iconSettings
                        tooltipText: "Configure"

                        onClicked: configEditor.open()
                    }
                }

                // Config Info (local recorder only)
                Label {
                    Layout.fillWidth: true
                    objectName: "recorderManagerConfigInfoLabel"
                    opacity: 0.7
                    text: {
                        if (!d.currentInterface || !d.isLocal)
                            return "";
                        let sel = d.currentInterface.selectedTopicCount;
                        let avail = d.currentInterface.availableTopicCount;
                        if (sel === 0 && avail === 0)
                            return "No topics configured. Click Settings to select topics.";
                        if (sel === 0)
                            return "No topics selected (0 of " + avail + " available). Click Settings to select topics.";
                        return "Selected " + sel + " of " + avail + " available topic" + (avail !== 1 ? "s" : "") + " for recording.";
                    }
                    visible: d.isLocal && d.currentInterface
                }

                // Summary Bar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    visible: d.currentInterface && d.currentInterface.status

                    Label {
                        property var s: d.currentInterface ? d.currentInterface.status : null

                        objectName: "recorderManagerSummaryLabel"
                        opacity: 0.7
                        text: s ? "Duration: " + d.formatDuration(s.duration) + "  |  Size: " + d.formatBytes(s.size) + "  |  Files: " + (s.files ? s.files.length : 0) + "  |  Topics: " + (s.topics ? s.topics.length : 0) : ""
                    }
                }

                // Topic Table
                TopicTable {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    model: d.currentInterface ? d.currentInterface.topicsModel : null
                    objectName: "recorderManagerTopicTable"
                }
            }

            // ================================================================
            // Tab 1: Bag Browser
            // ================================================================

            BagBrowser {
                id: bagBrowser

                objectName: "recorderManagerBagBrowser"
                recorderInterface: d.currentInterface

                Component.onCompleted: {
                    if (context._recentBagPaths)
                        recentPaths = context._recentBagPaths;
                }
                onRecentPathsChanged: {
                    context._recentBagPaths = recentPaths;
                }
                onStatusMessage: function (msg, isError) {
                    serviceStatusLabel.text = (isError ? "\u2717 " : "\u2713 ") + msg;
                    serviceStatusLabel.color = isError ? Material.color(Material.Red) : Material.color(Material.Green);
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
            function onCurrentIndexChanged() {
                if (tabBar.currentIndex === 1) {
                    root._initBagBrowserPath();
                    bagRefreshTimer.restart();
                }
            }

            target: tabBar
        }

        // --------------------------------------------------------------------
        // Status Bar
        // --------------------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true

            Label {
                id: serviceStatusLabel

                Layout.fillWidth: true
                color: palette.mid
                elide: Text.ElideMiddle
                objectName: "recorderManagerServiceStatusLabel"
                text: {
                    let s = d.currentInterface ? d.currentInterface.status : null;
                    return s ? "Output: " + s.output_dir : "No recorder selected";
                }

                Connections {
                    function onServiceResponse(name, success, message) {
                        serviceStatusLabel.text = (success ? "\u2713 " : "\u2717 ") + name + ": " + message;
                        serviceStatusLabel.color = success ? Material.color(Material.Green) : Material.color(Material.Red);
                        statusResetTimer.restart();
                    }

                    target: d.currentInterface
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

                color: palette.mid
                objectName: "recorderManagerRemoteCountLabel"
                text: d.isLocal ? "Local" : remoteCount + " remote recorder" + (remoteCount !== 1 ? "s" : "")
            }
        }
    }

    // ========================================================================
    // Empty State
    // ========================================================================

    Label {
        anchors.centerIn: parent
        color: palette.mid
        horizontalAlignment: Text.AlignHCenter
        objectName: "recorderManagerEmptyStateLabel"
        text: "No recorder selected."
        visible: !d.currentInterface
    }

    // ========================================================================
    // Dialogs
    // ========================================================================

    // Start recording dialog
    Popup {
        id: outputDirDialog

        anchors.centerIn: parent
        height: 220
        modal: true
        objectName: "recorderManagerStartDialog"
        padding: 16
        width: 450

        background: Rectangle {
            border.color: palette.mid
            color: palette.window
            radius: 8
        }

        onOpened: {
            bagNameField.text = "";
            // Fetch the raw configured output path (e.g. "~/bags/") from the
            // config YAML, not from status.output_dir which holds the resolved
            // path of the last recording.
            outputDirField.text = "";
            if (d.currentInterface) {
                d.currentInterface.fetchConfig(function (yaml) {
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
                font.bold: true
                text: "Start Recording"
            }
            GridLayout {
                Layout.fillWidth: true
                columnSpacing: 8
                columns: 2
                rowSpacing: 6

                Label {
                    text: "Directory:"
                }
                TextField {
                    id: outputDirField

                    Layout.fillWidth: true
                    objectName: "recorderManagerOutputDirField"
                    placeholderText: "~/bags/"
                }
                Label {
                    text: "Name:"
                }
                TextField {
                    id: bagNameField

                    Layout.fillWidth: true
                    objectName: "recorderManagerBagNameField"
                    placeholderText: "auto (rosbag2_YYYY_MM_DD-HH_mm_ss)"
                }
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                opacity: 0.7
                text: bagNameField.text ? "Bag folder: " + outputDirField.text + bagNameField.text : "A timestamped subfolder will be created automatically."
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true

                Item {
                    Layout.fillWidth: true
                }
                Button {
                    objectName: "recorderManagerStartDialogCancelButton"
                    text: "Cancel"

                    onClicked: outputDirDialog.close()
                }
                Button {
                    highlighted: true
                    objectName: "recorderManagerStartDialogConfirmButton"
                    text: "Start Recording"

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

        objectName: "recorderManagerConfigEditor"
        recorderInterface: d.currentInterface
        savedConfigNames: PresetStore.presetNames

        onConfigDeleted: function (name) {
            PresetStore.remove(name);
        }
        onConfigSaved: function (name, yaml) {
            PresetStore.save(name, yaml);
        }
    }
}
