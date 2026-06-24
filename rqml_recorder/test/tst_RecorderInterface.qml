import QtQuick
import QtTest
import "../qml/interfaces" as Interfaces
import Ros2

Item {
    id: windowRoot
    width: 800
    height: 600

    Interfaces.RecorderInterface {
        id: recorderInterface
        statusTopic: ""
        enabled: true
        recordedBy: "test-user"
    }

    TestCase {
        name: "RecorderInterfaceTest"
        when: windowShown

        function init() {
            Ros2.reset();
            recorderInterface.statusTopic = "";
            recorderInterface.recorderNamespace = "";
            recorderInterface.state = "disconnected";
            recorderInterface._lastUpdateMs = 0;
        }

        // ---- Test 1: Service clients null before namespace ----
        function test_01_clients_null_without_namespace() {
            compare(recorderInterface.recorderNamespace, "",
                "Namespace should be empty initially");
            compare(recorderInterface.startClient, null,
                "startClient should be null without namespace");
            compare(recorderInterface.stopClient, null,
                "stopClient should be null without namespace");
            compare(recorderInterface.pauseClient, null,
                "pauseClient should be null without namespace");
            compare(recorderInterface.resumeClient, null,
                "resumeClient should be null without namespace");
            compare(recorderInterface.splitClient, null,
                "splitClient should be null without namespace");
            compare(recorderInterface.configClient, null,
                "configClient should be null without namespace");
            compare(recorderInterface.listBagsClient, null,
                "listBagsClient should be null without namespace");
        }

        // ---- Test 2: Service clients created on namespace ----
        function test_02_clients_created_on_namespace() {
            recorderInterface.recorderNamespace = "/test_recorder";

            tryVerify(function() { return recorderInterface.startClient !== null; }, 1000,
                "startClient should exist with namespace");
            verify(recorderInterface.stopClient !== null,
                "stopClient should exist with namespace");
            verify(recorderInterface.pauseClient !== null,
                "pauseClient should exist with namespace");
            verify(recorderInterface.resumeClient !== null,
                "resumeClient should exist with namespace");
            verify(recorderInterface.splitClient !== null,
                "splitClient should exist with namespace");
            verify(recorderInterface.configClient !== null,
                "configClient should exist with namespace");
            verify(recorderInterface.listBagsClient !== null,
                "listBagsClient should exist with namespace");
            verify(recorderInterface.getBagDetailsClient !== null,
                "getBagDetailsClient should exist with namespace");
            verify(recorderInterface.deleteBagClient !== null,
                "deleteBagClient should exist with namespace");
        }

        // ---- Test 3: Status processing ----
        function test_03_status_processing() {
            recorderInterface.statusTopic = "/test_recorder/status";
            recorderInterface.enabled = true;

            tryVerify(function() { return Ros2.findSubscription("/test_recorder/status") !== null; },
                1000, "Status subscription should exist");
            var sub = Ros2.findSubscription("/test_recorder/status");

            sub.injectMessage({
                node_name: "/test_recorder",
                state: 1, // recording
                duration: { sec: 120, nanosec: 0 },
                size: 1048576,
                output_dir: "~/bags/",
                files: ["rosbag2_001"],
                topics: [
                    { topic: "/camera", msg_count: 100, frequency: 30.0,
                      size: 500000, bandwidth: 15000, type: "sensor_msgs/msg/Image",
                      publisher_count: 1, qos_reliability: "reliable", throttled: false },
                    { topic: "/lidar", msg_count: 50, frequency: 10.0,
                      size: 200000, bandwidth: 5000, type: "sensor_msgs/msg/PointCloud2",
                      publisher_count: 1, qos_reliability: "best_effort", throttled: false }
                ]
            });

            tryCompare(recorderInterface, "state", "recording", 1000,
                "State should be 'recording' after status with state=1");
            compare(recorderInterface.recorderNamespace, "/test_recorder",
                "Namespace should be set from node_name");
            verify(recorderInterface.connected, "Should be connected after status");
            compare(recorderInterface.topicsModel.count, 2,
                "Topics model should have 2 entries");
            compare(recorderInterface.topicsModel.get(0).topic, "/camera",
                "First topic should be /camera");
            compare(recorderInterface.topicsModel.get(1).topic, "/lidar",
                "Second topic should be /lidar");
        }

        // ---- Test 4: State transitions ----
        function test_04_state_transitions() {
            recorderInterface.statusTopic = "/test_recorder/status";
            tryVerify(function() { return Ros2.findSubscription("/test_recorder/status") !== null; },
                1000, "Subscription should exist");
            var sub = Ros2.findSubscription("/test_recorder/status");

            // Idle
            sub.injectMessage({ node_name: "/test_recorder", state: 0, topics: [] });
            tryCompare(recorderInterface, "state", "idle", 1000, "State 0 should be idle");

            // Recording
            sub.injectMessage({ node_name: "/test_recorder", state: 1, topics: [] });
            tryCompare(recorderInterface, "state", "recording", 1000, "State 1 should be recording");

            // Paused
            sub.injectMessage({ node_name: "/test_recorder", state: 2, topics: [] });
            tryCompare(recorderInterface, "state", "paused", 1000, "State 2 should be paused");

            // Unknown
            sub.injectMessage({ node_name: "/test_recorder", state: 99, topics: [] });
            tryCompare(recorderInterface, "state", "unknown", 1000, "State 99 should be unknown");
        }

        // ---- Test 5: Start recording service call ----
        function test_05_start_recording() {
            Ros2._mockServiceResponses["/test_recorder/start_recording"] = function(req) {
                return { success: true, message: "Recording started" };
            };
            recorderInterface.recorderNamespace = "/test_recorder";

            var responseReceived = false;
            var lastSuccess = false;
            var lastMessage = "";

            recorderInterface.serviceResponse.connect(function(name, success, message) {
                responseReceived = true;
                lastSuccess = success;
                lastMessage = message;
            });

            recorderInterface.startRecording("~/bags/test");
            tryVerify(function() { return responseReceived; }, 1000,
                "Should receive service response");
            verify(lastSuccess, "Start should succeed");
            compare(lastMessage, "Recording started");
        }

        // ---- Test 6: Stop/pause/resume/split ----
        function test_06_stop_pause_resume_split() {
            Ros2._mockServiceResponses["/test_recorder/stop_recording"] =
                { success: true, message: "Stopped" };
            Ros2._mockServiceResponses["/test_recorder/pause_recording"] =
                { success: true, message: "Paused" };
            Ros2._mockServiceResponses["/test_recorder/resume_recording"] =
                { success: true, message: "Resumed" };
            Ros2._mockServiceResponses["/test_recorder/split_bag"] =
                { success: true, message: "Split" };
            recorderInterface.recorderNamespace = "/test_recorder";

            var responses = [];
            recorderInterface.serviceResponse.connect(function(name, success, message) {
                responses.push({ name: name, success: success, message: message });
            });

            recorderInterface.stopRecording();
            tryVerify(function() { return responses.length >= 1; }, 1000);
            compare(responses[0].name, "stop");

            recorderInterface.pauseRecording();
            tryVerify(function() { return responses.length >= 2; }, 1000);
            compare(responses[1].name, "pause");

            recorderInterface.resumeRecording();
            tryVerify(function() { return responses.length >= 3; }, 1000);
            compare(responses[2].name, "resume");

            recorderInterface.splitBag();
            tryVerify(function() { return responses.length >= 4; }, 1000);
            compare(responses[3].name, "split");
        }

        // ---- Test 7: Apply config ----
        function test_07_apply_config() {
            Ros2._mockServiceResponses["/test_recorder/apply_config"] = function(req) {
                return { success: true, message: "Config applied" };
            };
            recorderInterface.recorderNamespace = "/test_recorder";

            var responseReceived = false;
            recorderInterface.serviceResponse.connect(function(name, success, message) {
                if (name === "config") responseReceived = true;
            });

            recorderInterface.applyConfig("topics:\n  - /test", true);
            tryVerify(function() { return responseReceived; }, 1000,
                "Should receive config response");
        }

        // ---- Test 8: Fetch available topics ----
        function test_08_fetch_available_topics() {
            Ros2._mockServiceResponses["/test_recorder/get_available_topics"] = function() {
                var topics = ["/cam", "/lidar"];
                topics.at = function(i) { return this[i]; };
                var types = ["sensor_msgs/msg/Image", "sensor_msgs/msg/PointCloud2"];
                types.at = function(i) { return this[i]; };
                return { topics: topics, types: types };
            };
            recorderInterface.recorderNamespace = "/test_recorder";

            var result = null;
            recorderInterface.fetchAvailableTopics(function(topics) {
                result = topics;
            });
            tryVerify(function() { return result !== null; }, 1000);
            compare(result.length, 2, "Should have 2 topics");
            compare(result[0].name, "/cam");
            compare(result[0].type, "sensor_msgs/msg/Image");
            compare(result[1].name, "/lidar");
        }

        // ---- Test 9: List bags ----
        function test_09_list_bags() {
            Ros2._mockServiceResponses["/test_recorder/list_bags"] = function() {
                var bags = [{
                    name: "test_bag", path: "/bags/test_bag",
                    size_bytes: 1024, start_time: "2025-01-01",
                    duration_secs: 60, topic_count: 5,
                    message_count: 1000, recorded_by: "user",
                    storage_id: "sqlite3"
                }];
                bags.at = function(i) { return this[i]; };
                return { success: true, bags: bags };
            };
            recorderInterface.recorderNamespace = "/test_recorder";

            var result = null;
            recorderInterface.listBags("", function(bags) {
                result = bags;
            });
            tryVerify(function() { return result !== null; }, 1000);
            compare(result.length, 1);
            compare(result[0].name, "test_bag");
            compare(result[0].sizeBytes, 1024);
            compare(result[0].durationSecs, 60);
            compare(result[0].recordedBy, "user");
        }

        // ---- Test 10: Stale detection ----
        function test_10_stale_detection() {
            recorderInterface.statusTopic = "/test_recorder/status";
            tryVerify(function() { return Ros2.findSubscription("/test_recorder/status") !== null; },
                1000);
            var sub = Ros2.findSubscription("/test_recorder/status");

            sub.injectMessage({ node_name: "/test_recorder", state: 1, topics: [] });
            tryCompare(recorderInterface, "state", "recording", 1000);
            verify(recorderInterface.connected, "Should be connected right after status");

            // Simulate time passing by setting _lastUpdateMs to 6 seconds ago
            recorderInterface._lastUpdateMs = Date.now() - 6000;
            verify(!recorderInterface.connected,
                "Should be disconnected when last update is >5s old");
        }
    }
}
