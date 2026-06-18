import QtQuick
import QtTest
import "../qml/interfaces" as Interfaces
import RqmlRecorder

Item {
    id: windowRoot
    width: 800
    height: 600

    Interfaces.LocalRecorderInterface {
        id: localInterface
    }

    TestCase {
        name: "LocalRecorderInterfaceTest"
        when: windowShown

        function init() {
            localInterface.engine._startCount = 0;
            localInterface.engine._stopCount = 0;
            localInterface.engine._pauseCount = 0;
            localInterface.engine._resumeCount = 0;
            localInterface.engine._splitCount = 0;
            localInterface.engine.state = "idle";
            localInterface._selectedTopics = [];
        }

        // ---- Test 1: Always local and connected ----
        function test_01_local_and_connected() {
            compare(localInterface.isLocal, true, "Should be local");
            compare(localInterface.connected, true, "Should always be connected");
            compare(localInterface.supportsTransfer, false, "Should not support transfer");
            compare(localInterface.supportsDelete, true, "Should support delete");
            compare(localInterface.supportsPlayback, true, "Should support playback");
        }

        // ---- Test 2: Start recording discovers topics when none selected ----
        function test_02_start_discovers_topics() {
            localInterface.engine._mockTopics = [
                { name: "/cam", type: "sensor_msgs/msg/Image", publisherCount: 1 },
                { name: "/imu", type: "sensor_msgs/msg/Imu", publisherCount: 1 }
            ];
            localInterface._selectedTopics = [];

            localInterface.startRecording("~/bags/");

            compare(localInterface.engine._startCount, 1, "Engine should be started");
            compare(localInterface._selectedTopics.length, 2,
                "Should have discovered and selected 2 topics");
            verify(localInterface._selectedTopics.indexOf("/cam") >= 0,
                "Should have /cam selected");
            verify(localInterface._selectedTopics.indexOf("/imu") >= 0,
                "Should have /imu selected");
        }

        // ---- Test 3: Start recording with pre-selected topics ----
        function test_03_start_with_selected_topics() {
            localInterface._selectedTopics = ["/topic_a", "/topic_b"];

            localInterface.startRecording("~/bags/test");

            compare(localInterface.engine._startCount, 1);
            compare(localInterface.engine._lastStartTopics.length, 2,
                "Should use pre-selected topics");
        }

        // ---- Test 4: YAML topic parsing ----
        function test_04_yaml_parsing() {
            // Normal case
            localInterface.applyConfig(
                "output: \"~/bags/\"\ntopics:\n  - /camera\n  - /lidar\n  - /imu\n", false);
            compare(localInterface._selectedTopics.length, 3, "Should parse 3 topics");
            compare(localInterface._selectedTopics[0], "/camera");
            compare(localInterface._selectedTopics[1], "/lidar");
            compare(localInterface._selectedTopics[2], "/imu");

            // Empty YAML (no topics section)
            var oldTopics = localInterface._selectedTopics.slice();
            localInterface.applyConfig("output: \"~/bags/\"\n", false);
            // Should keep previous topics since no topics were found
            compare(localInterface._selectedTopics.length, oldTopics.length,
                "Should keep previous topics when YAML has no topics section");

            // Mixed content after topics section
            localInterface.applyConfig(
                "topics:\n  - /a\n  - /b\nother_key: value\n", false);
            compare(localInterface._selectedTopics.length, 2, "Should stop at next key");
            compare(localInterface._selectedTopics[0], "/a");
            compare(localInterface._selectedTopics[1], "/b");
        }

        // ---- Test 5: Fetch config generates YAML ----
        function test_05_fetch_config() {
            localInterface._selectedTopics = ["/cam", "/lidar"];
            localInterface.engine.outputDir = "~/bags/";

            var result = null;
            localInterface.fetchConfig(function(yaml) {
                result = yaml;
            });

            verify(result !== null, "Callback should be called synchronously");
            verify(result.indexOf("/cam") >= 0, "YAML should contain /cam");
            verify(result.indexOf("/lidar") >= 0, "YAML should contain /lidar");
            verify(result.indexOf("~/bags/") >= 0, "YAML should contain output dir");
        }

        // ---- Test 6: State mirrors engine ----
        function test_06_state_mirrors_engine() {
            compare(localInterface.state, "idle", "Initial state should be idle");

            localInterface.engine.state = "recording";
            compare(localInterface.state, "recording",
                "State should mirror engine recording");

            localInterface.engine.state = "paused";
            compare(localInterface.state, "paused",
                "State should mirror engine paused");

            // Check synthetic status
            var status = localInterface._buildStatus();
            compare(status.node_name, "local_recorder");
            compare(status.state, 2, "Paused should map to state enum 2");
        }

        // ---- Test 7: Apply config with restart ----
        function test_07_apply_config_restart() {
            localInterface._selectedTopics = ["/old_topic"];
            localInterface.engine.state = "recording";
            localInterface.engine.outputDir = "~/bags/";

            localInterface.applyConfig(
                "topics:\n  - /new_topic\n", true);

            compare(localInterface._selectedTopics[0], "/new_topic",
                "Topics should be updated");
            // Engine should have been stopped and restarted
            compare(localInterface.engine._stopCount, 1, "Engine should be stopped");
            compare(localInterface.engine._startCount, 1, "Engine should be restarted");
        }
    }
}
