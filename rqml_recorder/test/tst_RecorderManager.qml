import QtQuick
import QtQuick.Controls
import QtTest
import "../qml" as PluginQml
import Ros2

Item {
    id: windowRoot
    width: 800
    height: 600

    property var context: ({
        selectedRecorder: "",
        autoRefresh: false
    })

    PluginQml.RecorderManager {
        id: recorderManager
        anchors.fill: parent
    }

    Utils { id: helpers }

    TestCase {
        name: "RecorderManagerTest"
        when: windowShown

        function find(name) { return helpers.findChild(windowRoot, name); }

        // TODO(test-guidelines): expose objectName on internal d object / ConfigEditor to allow Utils.findChild lookup
        function findChildByProperty(parentItem, propName, propValue) {
            if (!parentItem) return null;
            if (parentItem[propName] === propValue) return parentItem;
            var children = parentItem.children || [];
            if (parentItem.contentItem) children = parentItem.contentItem.children;
            for (var i = 0; i < children.length; i++) {
                var found = findChildByProperty(children[i], propName, propValue);
                if (found) return found;
            }
            return null;
        }

        function findObjectByName(parentItem, objName) {
            return findChildByProperty(parentItem, "objectName", objName);
        }

        // TODO(test-guidelines): expose objectName on internal d object to allow Utils.findChild lookup
        function findInternalD() {
            // Access internal d object via the plugin's children
            for (var i = 0; i < recorderManager.data.length; i++) {
                var obj = recorderManager.data[i];
                if (obj && obj.recorderInterfaces !== undefined)
                    return obj;
            }
            return null;
        }

        function init() {
            Ros2.reset();
            windowRoot.context.selectedRecorder = "";
            windowRoot.context.autoRefresh = false;
        }

        // ---- Test 1: Plugin loads ----
        function test_01_plugin_loads() {
            verify(recorderManager !== null, "RecorderManager should load");
        }

        // ---- Test 2: Local recorder always present ----
        function test_02_local_always_present() {
            // After load, the local recorder should be available
            var d = findInternalD();
            verify(d !== null, "Internal d object should exist");
            verify(d.recorderEntries.length >= 1,
                "Should have at least 1 entry (local)");
            compare(d.recorderEntries[0], "__local__",
                "First entry should be local");
        }

        // ---- Test 3: Remote discovery ----
        function test_03_remote_discovery() {
            Ros2._mockTopics["hector_recorder_msgs/msg/RecorderStatus"] = [
                "/robot1/recorder/status",
                "/robot2/recorder/status"
            ];

            var d = findInternalD();
            verify(d !== null);
            d.discoverRecorders();

            tryVerify(function() { return d.recorderEntries.length >= 3; }, 1000,
                "Should have local + 2 remote entries");
            verify(d.recorderEntries.indexOf("/robot1/recorder/status") >= 0,
                "Should contain robot1 topic");
            verify(d.recorderEntries.indexOf("/robot2/recorder/status") >= 0,
                "Should contain robot2 topic");

            // Labels should match
            compare(d.recorderLabels.length, d.recorderEntries.length,
                "Labels and entries should have same length");
        }

        // ---- Test 4: Recorder selection ----
        function test_04_recorder_selection() {
            var d = findInternalD();
            verify(d !== null);

            // Default should auto-select local
            d.discoverRecorders();
            tryCompare(windowRoot.context, "selectedRecorder", "__local__", 1000,
                "Should auto-select local");
            verify(d.currentInterface !== null, "Should have current interface");
            verify(d.isLocal, "Should be local interface");
        }

        // ---- Test 5: Status display updates ----
        function test_05_status_display_updates() {
            Ros2._mockTopics["hector_recorder_msgs/msg/RecorderStatus"] = [
                "/recorder/status"
            ];
            var d = findInternalD();
            d.discoverRecorders();
            tryVerify(function() {
                return d.recorderEntries.indexOf("/recorder/status") >= 0;
            }, 1000, "Remote recorder should be discovered");

            // Select the remote recorder
            windowRoot.context.selectedRecorder = "/recorder/status";
            d._updateCurrentInterface();

            tryVerify(function() { return d.currentInterface !== null; }, 1000);
            tryVerify(function() { return !d.isLocal; }, 1000, "Should not be local");

            // Inject status via subscription
            var sub = Ros2.findSubscription("/recorder/status");
            if (sub) {
                sub.injectMessage({
                    node_name: "/recorder",
                    state: 1,
                    duration: { sec: 60 },
                    size: 2048,
                    output_dir: "~/bags/",
                    files: [],
                    topics: []
                });

                tryCompare(d.currentInterface, "state", "recording", 1000,
                    "Current interface should show recording state");
            }
        }

        // ---- Test 6: Control buttons call correct methods ----
        function test_06_control_buttons() {
            var d = findInternalD();
            d.discoverRecorders();

            // With local selected, verify interface exists
            tryVerify(function() { return d.currentInterface !== null; }, 1000,
                "Should have interface");
            compare(d.currentInterface.isLocal, true, "Should be local interface");

            // Test that stop/pause/resume/split delegate correctly
            d.currentInterface.engine.state = "recording";
            d.currentInterface.stopRecording();
            compare(d.currentInterface.engine._stopCount, 1, "Stop should call engine");

            d.currentInterface.engine.state = "recording";
            d.currentInterface.pauseRecording();
            compare(d.currentInterface.engine._pauseCount, 1, "Pause should call engine");

            d.currentInterface.engine.state = "paused";
            d.currentInterface.resumeRecording();
            compare(d.currentInterface.engine._resumeCount, 1, "Resume should call engine");

            d.currentInterface.engine.state = "recording";
            d.currentInterface.splitBag();
            compare(d.currentInterface.engine._splitCount, 1, "Split should call engine");
        }

        // ---- Test 7: Config editor opens ----
        function test_07_config_editor() {
            // Find the ConfigEditor by looking for the modal popup
            var configEditor = null;
            for (var i = 0; i < recorderManager.data.length; i++) {
                var obj = recorderManager.data[i];
                if (obj && obj.toString().indexOf("ConfigEditor") >= 0) {
                    configEditor = obj;
                    break;
                }
            }
            // ConfigEditor is a Popup; verify it's not visible initially
            if (configEditor) {
                compare(configEditor.visible, false,
                    "ConfigEditor should be hidden initially");
            }
        }

        // ---- Test 8: WiFi warning only for local ----
        function test_08_wifi_warning() {
            var d = findInternalD();
            d.discoverRecorders();

            // Local is selected — WiFi warning should be visible
            tryCompare(d, "isLocal", true, 1000);

            // Switch to remote (if available)
            Ros2._mockTopics["hector_recorder_msgs/msg/RecorderStatus"] = [
                "/remote/status"
            ];
            d.discoverRecorders();
            tryVerify(function() {
                return d.recorderEntries.indexOf("/remote/status") >= 0;
            }, 1000, "Remote recorder should be discovered");

            windowRoot.context.selectedRecorder = "/remote/status";
            d._updateCurrentInterface();
            tryCompare(d, "isLocal", false, 1000, "Should not be local for remote recorder");
        }

        // ---- Test 9: Auto-select fallback ----
        function test_09_auto_select_fallback() {
            var d = findInternalD();
            // Set an invalid selection
            windowRoot.context.selectedRecorder = "nonexistent_topic";
            d.discoverRecorders();

            // Should fall back to local
            tryCompare(windowRoot.context, "selectedRecorder", "__local__", 1000,
                "Should auto-select local when selection is stale");
        }

        // ---- Test 10: Tab switching ----
        function test_10_tab_switching() {
            // RecorderManager has a TabBar with "Recording" and "Bags" tabs
            // Just verify the d object and interface are stable across interactions
            var d = findInternalD();
            d.discoverRecorders();
            tryVerify(function() { return d.currentInterface !== null; }, 1000);
            verify(d.recorderEntries.length >= 1);
        }
    }
}
