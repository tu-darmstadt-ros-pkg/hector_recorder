import QtQuick
import QtTest
import RQml.Recorder
import "../qml/interfaces" as Interfaces

Item {
    id: root

    height: 600
    width: 800

    Interfaces.LocalRecorderInterface {
        id: localInterface

    }
    SignalSpy {
        id: serviceResponseSpy

        signalName: "serviceResponse"
        target: localInterface
    }
    TestCase {
        function init() {
            var engine = localInterface.engine;
            engine._startCount = 0;
            engine._stopCount = 0;
            engine._pauseCount = 0;
            engine._resumeCount = 0;
            engine._splitCount = 0;
            engine._lastStartTopics = [];
            engine._lastStartDir = "";
            engine._mockTopics = [];
            engine._mockTopicStats = [];
            engine.outputDir = "~/bags/";
            engine.state = "idle";
            localInterface._selectedTopics = [];
            serviceResponseSpy.clear();
        }
        function test_apply_config_keeps_topics_without_topics_section() {
            localInterface._selectedTopics = ["/camera", "/lidar", "/imu"];
            localInterface.applyConfig("output: \"~/bags/\"\n", false);
            compare(localInterface._selectedTopics.length, 3, "Should keep previous topics when YAML has no topics section");
            compare(localInterface._selectedTopics[0], "/camera");
        }
        function test_apply_config_parses_topics_from_yaml() {
            localInterface.applyConfig("output: \"~/bags/\"\ntopics:\n  - /camera\n  - /lidar\n  - /imu\n", false);
            compare(localInterface._selectedTopics.length, 3, "Should parse 3 topics");
            compare(localInterface._selectedTopics[0], "/camera");
            compare(localInterface._selectedTopics[1], "/lidar");
            compare(localInterface._selectedTopics[2], "/imu");
            compare(localInterface.selectedTopicCount, 3);
            compare(serviceResponseSpy.count, 1);
            compare(serviceResponseSpy.signalArguments[0][0], "config");
            verify(serviceResponseSpy.signalArguments[0][1], "Applying a config should report success");
        }
        function test_apply_config_stops_topic_list_at_next_key() {
            localInterface.applyConfig("topics:\n  - /a\n  - /b\nother_key: value\n", false);
            compare(localInterface._selectedTopics.length, 2, "Should stop at next key");
            compare(localInterface._selectedTopics[0], "/a");
            compare(localInterface._selectedTopics[1], "/b");
        }
        function test_apply_config_with_restart_restarts_engine() {
            localInterface._selectedTopics = ["/old_topic"];
            localInterface.engine.state = "recording";
            localInterface.engine.outputDir = "~/bags/";
            localInterface.applyConfig("topics:\n  - /new_topic\n", true);
            compare(localInterface._selectedTopics[0], "/new_topic", "Topics should be updated");
            compare(localInterface.engine._stopCount, 1, "Engine should be stopped");
            compare(localInterface.engine._startCount, 1, "Engine should be restarted");
            compare(localInterface.engine._lastStartTopics[0], "/new_topic", "Engine should be restarted with the new topics");
        }
        function test_fetch_config_generates_yaml() {
            localInterface._selectedTopics = ["/cam", "/lidar"];
            localInterface.engine.outputDir = "~/bags/";
            var result = null;
            localInterface.fetchConfig(function (yaml) {
                result = yaml;
            });
            verify(result !== null, "Callback should be called synchronously");
            verify(result.indexOf("/cam") >= 0, "YAML should contain /cam");
            verify(result.indexOf("/lidar") >= 0, "YAML should contain /lidar");
            verify(result.indexOf("~/bags/") >= 0, "YAML should contain output dir");
        }
        function test_is_local_and_always_connected() {
            compare(localInterface.isLocal, true, "Should be local");
            compare(localInterface.connected, true, "Should always be connected");
            compare(localInterface.supportsTransfer, false, "Should not support transfer");
            compare(localInterface.supportsDelete, true, "Should support delete");
            compare(localInterface.supportsPlayback, true, "Should support playback");
        }
        function test_start_recording_discovers_topics_when_none_selected() {
            localInterface.engine._mockTopics = [
                {
                    "name": "/cam",
                    "type": "sensor_msgs/msg/Image",
                    "publisherCount": 1
                },
                {
                    "name": "/imu",
                    "type": "sensor_msgs/msg/Imu",
                    "publisherCount": 1
                }
            ];
            localInterface.startRecording("~/bags/");
            compare(localInterface.engine._startCount, 1, "Engine should be started");
            compare(localInterface._selectedTopics.length, 2, "Should have discovered and selected 2 topics");
            verify(localInterface._selectedTopics.indexOf("/cam") >= 0, "Should have /cam selected");
            verify(localInterface._selectedTopics.indexOf("/imu") >= 0, "Should have /imu selected");
            compare(serviceResponseSpy.count, 1);
            compare(serviceResponseSpy.signalArguments[0][0], "start");
            verify(serviceResponseSpy.signalArguments[0][1], "Start should report success");
        }
        function test_start_recording_uses_selected_topics() {
            localInterface._selectedTopics = ["/topic_a", "/topic_b"];
            localInterface.startRecording("~/bags/test");
            compare(localInterface.engine._startCount, 1);
            compare(localInterface.engine._lastStartTopics.length, 2, "Should use pre-selected topics");
            compare(localInterface.engine._lastStartTopics[0], "/topic_a");
            compare(localInterface.engine._lastStartTopics[1], "/topic_b");
            compare(localInterface.engine._lastStartDir, "~/bags/test");
            compare(localInterface.engine.outputDir, "~/bags/test", "Output dir should be forwarded to the engine");
        }
        function test_state_mirrors_engine() {
            compare(localInterface.state, "idle", "Initial state should be idle");
            localInterface.engine.state = "recording";
            compare(localInterface.state, "recording", "State should mirror engine recording");
            compare(localInterface.status.state, 1, "Recording should map to state enum 1");
            localInterface.engine.state = "paused";
            compare(localInterface.state, "paused", "State should mirror engine paused");
            compare(localInterface.status.node_name, "local_recorder");
            compare(localInterface.status.state, 2, "Paused should map to state enum 2");
        }

        name: "LocalRecorderInterfaceTest"
        when: windowShown
    }
}
