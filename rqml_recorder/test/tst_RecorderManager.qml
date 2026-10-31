import QtQuick
import QtTest
import Ros2

Item {
    id: root

    property var context: contextObj
    property var plugin: pluginLoader.item

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 600
    width: 800

    QtObject {
        id: contextObj

        property var _recentBagPaths: null
        property bool autoRefresh: false
        property string selectedRecorder: ""
    }
    Utils {
        id: helpers

    }
    Loader {
        id: pluginLoader

        function reload() {
            source = "";
            source = "../qml/RecorderManager.qml";
        }

        anchors.fill: parent
    }
    TestCase {
        id: testCase

        //! The interface currently used by the plugin (exposed through the config editor).
        function currentInterface() {
            return find("recorderManagerConfigEditor").recorderInterface;
        }
        function init() {
            Ros2.reset();
            contextObj.selectedRecorder = "";
            contextObj.autoRefresh = false;
            contextObj._recentBagPaths = null;
            pluginLoader.reload();
            tryVerify(function () {
                return pluginLoader.status === Loader.Ready;
            }, 2000, "Loader should be ready");
            // Initial discovery runs one event loop tick after loading
            tryCompare(contextObj, "selectedRecorder", "__local__", 2000, "Local recorder should be auto-selected after load");
        }

        //! Registers a remote recorder that reports its info via the GetRecorderInfo service.
        function registerRemoteRecorder(statusTopic, nodeName) {
            Ros2.registerTopic(statusTopic, "hector_recorder_msgs/msg/RecorderStatus");
            Ros2.registerService(nodeName + "/get_recorder_info", "hector_recorder_msgs/srv/GetRecorderInfo", function (request) {
                var response = Ros2.createEmptyServiceResponse("hector_recorder_msgs/srv/GetRecorderInfo");
                response.hostname = "robot-host";
                response.recorded_by = "alice@robot-pc";
                response.config_path = "";
                return response;
            });
        }

        //! Selects the recorder entry with the given label through the recorder ComboBox.
        function selectRecorder(label) {
            var selector = find("recorderManagerRecorderSelector");
            var index = selector.model.indexOf(label);
            verify(index >= 0, "Recorder " + label + " should be listed");
            selector.currentIndex = index;
            selector.activated(index);
        }
        function test_auto_select_fallback() {
            // Set an invalid (stale) selection
            contextObj.selectedRecorder = "nonexistent_topic";
            mouseClick(find("recorderManagerRefreshButton"));
            tryCompare(contextObj, "selectedRecorder", "__local__", 1000, "Should auto-select local when selection is stale");
            verify(currentInterface().isLocal);
        }
        function test_config_editor_opens() {
            var configEditor = find("recorderManagerConfigEditor");
            compare(configEditor.visible, false, "ConfigEditor should be hidden initially");
            mouseClick(find("recorderManagerSettingsButton"));
            tryCompare(configEditor, "opened", true, 1000, "Settings button should open the config editor");
            compare(configEditor.recorderInterface, currentInterface());
            configEditor.close();
            tryCompare(configEditor, "visible", false, 1000);
        }
        function test_control_buttons() {
            var iface = currentInterface();
            compare(iface.isLocal, true, "Should be local interface");
            var engine = iface.engine;
            var stopButton = find("recorderManagerStopButton");
            var pauseResumeButton = find("recorderManagerPauseResumeButton");
            var splitButton = find("recorderManagerSplitButton");
            compare(stopButton.enabled, false, "Stop should be disabled while idle");
            compare(pauseResumeButton.enabled, false, "Pause should be disabled while idle");
            compare(splitButton.enabled, false, "Split should be disabled while idle");

            engine.state = "recording";
            tryCompare(stopButton, "enabled", true, 1000);
            mouseClick(stopButton);
            compare(engine._stopCount, 1, "Stop should call engine");
            tryCompare(find("recorderManagerStateLabel"), "text", "IDLE", 1000);

            engine.state = "recording";
            tryCompare(pauseResumeButton, "enabled", true, 1000);
            mouseClick(pauseResumeButton);
            compare(engine._pauseCount, 1, "Pause should call engine");
            tryCompare(find("recorderManagerStateLabel"), "text", "PAUSED", 1000);

            tryVerify(function () {
                return pauseResumeButton.text.indexOf("Resume") >= 0;
            }, 1000, "Pause button should turn into resume while paused");
            mouseClick(pauseResumeButton);
            compare(engine._resumeCount, 1, "Resume should call engine");
            tryCompare(find("recorderManagerStateLabel"), "text", "RECORDING", 1000);

            tryCompare(splitButton, "enabled", true, 1000);
            mouseClick(splitButton);
            compare(engine._splitCount, 1, "Split should call engine");
        }
        function test_local_recorder_always_present() {
            var selector = find("recorderManagerRecorderSelector");
            compare(selector.count, 1, "Only the local recorder should be listed without remote recorders");
            compare(selector.model[0], "⬤ Bag Recorder", "First entry should be the local recorder");
            compare(selector.currentIndex, 0);
            compare(contextObj.selectedRecorder, "__local__", "First entry should be the local key");
        }
        function test_local_recorder_auto_selected() {
            var iface = currentInterface();
            verify(iface !== null && iface !== undefined, "Should have current interface");
            verify(iface.isLocal, "Should be local interface");
            compare(find("recorderManagerEmptyStateLabel").visible, false, "Empty state should be hidden with a selected recorder");
            compare(find("recorderManagerStateLabel").text, "IDLE");
            compare(find("recorderManagerRemoteCountLabel").text, "Local");
        }
        function test_plugin_loads() {
            verify(plugin !== null, "RecorderManager should load");
            verify(find("recorderManagerRecorderSelector") !== null);
            verify(find("recorderManagerRefreshButton") !== null);
            verify(find("recorderManagerTabBar") !== null);
            verify(find("recorderManagerConfigEditor") !== null);
        }
        function test_remote_discovery() {
            registerRemoteRecorder("/robot1/recorder/status", "/robot1/recorder");
            registerRemoteRecorder("/robot2/recorder/status", "/robot2/recorder");
            mouseClick(find("recorderManagerRefreshButton"));
            var selector = find("recorderManagerRecorderSelector");
            tryCompare(selector, "count", 3, 1000, "Should have local + 2 remote entries");
            compare(selector.model[0], "⬤ Bag Recorder", "Local recorder should stay first");
            verify(selector.model.indexOf("/robot1/recorder/status") >= 0, "Should contain robot1 topic");
            verify(selector.model.indexOf("/robot2/recorder/status") >= 0, "Should contain robot2 topic");
            compare(contextObj.selectedRecorder, "__local__", "Discovery should keep the local selection");
        }
        function test_status_display_updates() {
            registerRemoteRecorder("/recorder/status", "/recorder");
            mouseClick(find("recorderManagerRefreshButton"));
            var selector = find("recorderManagerRecorderSelector");
            tryCompare(selector, "count", 2, 1000, "Remote recorder should be discovered");
            selectRecorder("/recorder/status");
            compare(contextObj.selectedRecorder, "/recorder/status", "Selecting the remote recorder should update the context");
            tryVerify(function () {
                var iface = currentInterface();
                return iface && !iface.isLocal;
            }, 1000, "Should not be local");
            compare(find("recorderManagerStateLabel").text, "DISCONNECTED", "Remote recorder is disconnected until a status arrives");
            compare(find("recorderManagerRemoteCountLabel").text, "1 remote recorder");
            var sub = null;
            tryVerify(function () {
                sub = Ros2.findSubscription("/recorder/status");
                return sub !== null;
            }, 1000, "Status subscription should be created");
            var msg = Ros2.createEmptyMessage("hector_recorder_msgs/msg/RecorderStatus");
            msg.node_name = "/recorder";
            msg.state = 1;
            msg.duration = {
                "sec": 60,
                "nanosec": 0
            };
            msg.size = 2048;
            msg.output_dir = "~/bags/";
            sub.injectMessage(msg);
            tryCompare(currentInterface(), "state", "recording", 1000, "Current interface should show recording state");
            tryCompare(find("recorderManagerStateLabel"), "text", "RECORDING", 1000);
            tryCompare(find("recorderManagerSummaryLabel"), "text", "Duration: 0:01:00  |  Size: 2.0 KB  |  Files: 0  |  Topics: 0", 1000);
            tryCompare(find("recorderManagerServiceStatusLabel"), "text", "Output: ~/bags/", 1000);
            tryCompare(find("recorderManagerMachineInfoRow"), "visible", true, 1000, "Machine info should be shown for remote recorders");
            tryCompare(find("recorderManagerNodeLabel"), "text", "Node: /recorder", 1000);
            tryCompare(find("recorderManagerHostLabel"), "text", "Host: robot-host", 1000, "Host should be fetched via GetRecorderInfo");
            tryCompare(find("recorderManagerUserLabel"), "text", "User: alice@robot-pc", 1000);
        }
        function test_tab_switching() {
            var tabBar = find("recorderManagerTabBar");
            var bagBrowser = find("recorderManagerBagBrowser");
            var topicTable = find("recorderManagerTopicTable");
            var iface = currentInterface();
            compare(tabBar.currentIndex, 0);
            compare(topicTable.visible, true, "Recording tab should be shown initially");
            compare(bagBrowser.visible, false);
            mouseClick(find("recorderManagerBagsTab"));
            tryCompare(tabBar, "currentIndex", 1, 1000);
            tryCompare(bagBrowser, "visible", true, 1000, "Bags tab should show the bag browser");
            compare(topicTable.visible, false);
            compare(bagBrowser.recorderInterface, iface, "Bag browser should use the current interface");
            mouseClick(find("recorderManagerRecordingTab"));
            tryCompare(tabBar, "currentIndex", 0, 1000);
            tryCompare(topicTable, "visible", true, 1000);
            compare(currentInterface(), iface, "Interface should be stable across tab switches");
            compare(find("recorderManagerRecorderSelector").count, 1);
        }
        function test_wifi_warning_only_for_local() {
            var wifiWarning = find("recorderManagerWifiWarning");
            tryCompare(wifiWarning, "visible", true, 1000, "WiFi warning should be visible for the local recorder");
            compare(find("recorderManagerConfigInfoLabel").visible, true, "Config info should be visible for the local recorder");
            compare(find("recorderManagerMachineInfoRow").visible, false, "Machine info should be hidden for the local recorder");
            registerRemoteRecorder("/remote/status", "/remote");
            mouseClick(find("recorderManagerRefreshButton"));
            tryCompare(find("recorderManagerRecorderSelector"), "count", 2, 1000, "Remote recorder should be discovered");
            selectRecorder("/remote/status");
            tryVerify(function () {
                return !currentInterface().isLocal;
            }, 1000, "Should not be local for remote recorder");
            tryCompare(wifiWarning, "visible", false, 1000, "WiFi warning should be hidden for remote recorders");
            compare(find("recorderManagerConfigInfoLabel").visible, false);
        }

        name: "RecorderManagerTest"
        when: windowShown
    }
}
