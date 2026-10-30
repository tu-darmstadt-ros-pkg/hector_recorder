import QtQuick
import QtTest
import Ros2
import "../qml/interfaces" as Interfaces

Item {
    id: root

    readonly property string testStatusTopic: "/test_recorder/status"

    height: 600
    width: 800

    Interfaces.RecorderInterface {
        id: recorderInterface

        enabled: true
        recordedBy: "test-user"
        statusTopic: ""
    }
    SignalSpy {
        id: serviceResponseSpy

        signalName: "serviceResponse"
        target: recorderInterface
    }
    TestCase {
        function init() {
            Ros2.reset();
            Ros2.registerTopic(testStatusTopic, "hector_recorder_msgs/msg/RecorderStatus");
            registerSuccessService("start_recording", "StartRecording", "Recording started");
            registerSuccessService("stop_recording", "StopRecording", "Stopped");
            registerSuccessService("pause_recording", "PauseRecording", "Paused");
            registerSuccessService("resume_recording", "ResumeRecording", "Resumed");
            registerSuccessService("split_bag", "SplitBag", "Split");
            registerSuccessService("apply_config", "ApplyConfig", "Config applied");
            recorderInterface.enabled = true;
            recorderInterface.statusTopic = "";
            recorderInterface.recorderNamespace = "";
            recorderInterface.state = "disconnected";
            recorderInterface.status = null;
            recorderInterface._lastUpdateMs = 0;
            recorderInterface.topicsModel.clear();
            serviceResponseSpy.clear();
        }
        function injectStatus(msg) {
            var sub = Ros2.findSubscription(testStatusTopic);
            verify(sub !== null, "Status subscription should exist");
            sub.injectMessage(msg);
        }
        function registerSuccessService(name, type, message) {
            Ros2.registerService("/test_recorder/" + name, "hector_recorder_msgs/srv/" + type, function (req) {
                var resp = Ros2.createEmptyServiceResponse("hector_recorder_msgs/srv/" + type);
                resp.success = true;
                resp.message = message;
                return resp;
            });
        }
        function subscribeStatus() {
            recorderInterface.statusTopic = testStatusTopic;
            tryVerify(function () {
                return Ros2.findSubscription(testStatusTopic) !== null;
            }, 1000, "Status subscription should exist");
        }
        function test_apply_config_sends_request() {
            var lastRequest = null;
            Ros2.registerService("/test_recorder/apply_config", "hector_recorder_msgs/srv/ApplyConfig", function (req) {
                lastRequest = req;
                var resp = Ros2.createEmptyServiceResponse("hector_recorder_msgs/srv/ApplyConfig");
                resp.success = true;
                resp.message = "Config applied";
                return resp;
            });
            recorderInterface.recorderNamespace = "/test_recorder";
            recorderInterface.applyConfig("topics:\n  - /test", true);
            tryCompare(serviceResponseSpy, "count", 1, 1000, "Should receive config response");
            compare(serviceResponseSpy.signalArguments[0][0], "config");
            verify(serviceResponseSpy.signalArguments[0][1], "Apply config should succeed");
            compare(serviceResponseSpy.signalArguments[0][2], "Config applied");
            compare(lastRequest.config_yaml, "topics:\n  - /test");
            compare(lastRequest.restart, true);
        }
        function test_clients_created_on_namespace() {
            recorderInterface.recorderNamespace = "/test_recorder";
            tryVerify(function () {
                return recorderInterface.startClient !== null;
            }, 1000, "startClient should exist with namespace");
            verify(recorderInterface.stopClient !== null, "stopClient should exist with namespace");
            verify(recorderInterface.pauseClient !== null, "pauseClient should exist with namespace");
            verify(recorderInterface.resumeClient !== null, "resumeClient should exist with namespace");
            verify(recorderInterface.splitClient !== null, "splitClient should exist with namespace");
            verify(recorderInterface.configClient !== null, "configClient should exist with namespace");
            verify(recorderInterface.listBagsClient !== null, "listBagsClient should exist with namespace");
            verify(recorderInterface.getBagDetailsClient !== null, "getBagDetailsClient should exist with namespace");
            verify(recorderInterface.deleteBagClient !== null, "deleteBagClient should exist with namespace");
        }
        function test_clients_null_without_namespace() {
            compare(recorderInterface.recorderNamespace, "", "Namespace should be empty initially");
            compare(recorderInterface.startClient, null, "startClient should be null without namespace");
            compare(recorderInterface.stopClient, null, "stopClient should be null without namespace");
            compare(recorderInterface.pauseClient, null, "pauseClient should be null without namespace");
            compare(recorderInterface.resumeClient, null, "resumeClient should be null without namespace");
            compare(recorderInterface.splitClient, null, "splitClient should be null without namespace");
            compare(recorderInterface.configClient, null, "configClient should be null without namespace");
            compare(recorderInterface.listBagsClient, null, "listBagsClient should be null without namespace");
        }
        function test_fetch_available_topics() {
            Ros2.registerService("/test_recorder/get_available_topics", "hector_recorder_msgs/srv/GetAvailableTopics", function (req) {
                var resp = Ros2.createEmptyServiceResponse("hector_recorder_msgs/srv/GetAvailableTopics");
                resp.topics = ["/cam", "/lidar"];
                resp.types = ["sensor_msgs/msg/Image", "sensor_msgs/msg/PointCloud2"];
                return resp;
            });
            recorderInterface.recorderNamespace = "/test_recorder";
            var result = null;
            recorderInterface.fetchAvailableTopics(function (topics) {
                result = topics;
            });
            tryVerify(function () {
                return result !== null;
            }, 1000, "Should receive available topics");
            compare(result.length, 2, "Should have 2 topics");
            compare(result[0].name, "/cam");
            compare(result[0].type, "sensor_msgs/msg/Image");
            compare(result[1].name, "/lidar");
            compare(result[1].type, "sensor_msgs/msg/PointCloud2");
        }
        function test_list_bags() {
            Ros2.registerService("/test_recorder/list_bags", "hector_recorder_msgs/srv/ListBags", function (req) {
                var resp = Ros2.createEmptyServiceResponse("hector_recorder_msgs/srv/ListBags");
                resp.success = true;
                resp.bags = [
                    {
                        "name": "test_bag",
                        "path": "/bags/test_bag",
                        "size_bytes": 1024,
                        "start_time": "2025-01-01",
                        "duration_secs": 60,
                        "topic_count": 5,
                        "message_count": 1000,
                        "recorded_by": "user",
                        "storage_id": "sqlite3"
                    }
                ];
                return resp;
            });
            recorderInterface.recorderNamespace = "/test_recorder";
            var result = null;
            recorderInterface.listBags("", function (bags) {
                result = bags;
            });
            tryVerify(function () {
                return result !== null;
            }, 1000, "Should receive bag list");
            compare(result.length, 1);
            compare(result[0].name, "test_bag");
            compare(result[0].path, "/bags/test_bag");
            compare(result[0].sizeBytes, 1024);
            compare(result[0].durationSecs, 60);
            compare(result[0].topicCount, 5);
            compare(result[0].messageCount, 1000);
            compare(result[0].recordedBy, "user");
            compare(result[0].storageId, "sqlite3");
        }
        function test_stale_status_disconnects() {
            subscribeStatus();
            injectStatus({
                "node_name": "/test_recorder",
                "state": 1
            });
            tryCompare(recorderInterface, "state", "recording", 1000);
            verify(recorderInterface.connected, "Should be connected right after status");

            // Simulate time passing by moving the last update 6 seconds into the past
            recorderInterface._lastUpdateMs = Date.now() - 6000;
            verify(!recorderInterface.connected, "Should be disconnected when last update is >5s old");
        }
        function test_start_recording_sends_request() {
            var lastRequest = null;
            Ros2.registerService("/test_recorder/start_recording", "hector_recorder_msgs/srv/StartRecording", function (req) {
                lastRequest = req;
                var resp = Ros2.createEmptyServiceResponse("hector_recorder_msgs/srv/StartRecording");
                resp.success = true;
                resp.message = "Recording started";
                return resp;
            });
            recorderInterface.recorderNamespace = "/test_recorder";
            recorderInterface.startRecording("~/bags/test");
            tryCompare(serviceResponseSpy, "count", 1, 1000, "Should receive service response");
            compare(serviceResponseSpy.signalArguments[0][0], "start");
            verify(serviceResponseSpy.signalArguments[0][1], "Start should succeed");
            compare(serviceResponseSpy.signalArguments[0][2], "Recording started");
            compare(lastRequest.output_dir, "~/bags/test");
            compare(lastRequest.recorded_by, "test-user");
        }
        function test_state_transitions() {
            subscribeStatus();
            injectStatus({
                "node_name": "/test_recorder",
                "state": 0
            });
            tryCompare(recorderInterface, "state", "idle", 1000, "State 0 should be idle");
            injectStatus({
                "node_name": "/test_recorder",
                "state": 1
            });
            tryCompare(recorderInterface, "state", "recording", 1000, "State 1 should be recording");
            injectStatus({
                "node_name": "/test_recorder",
                "state": 2
            });
            tryCompare(recorderInterface, "state", "paused", 1000, "State 2 should be paused");
            injectStatus({
                "node_name": "/test_recorder",
                "state": 99
            });
            tryCompare(recorderInterface, "state", "unknown", 1000, "State 99 should be unknown");
        }
        function test_status_message_updates_state_and_topics() {
            subscribeStatus();
            injectStatus({
                "node_name": "/test_recorder",
                "state": 1,
                "duration": {
                    "sec": 120,
                    "nanosec": 0
                },
                "size": 1048576,
                "output_dir": "~/bags/",
                "files": ["rosbag2_001"],
                "topics": [
                    {
                        "topic": "/camera",
                        "msg_count": 100,
                        "frequency": 30.0,
                        "size": 500000,
                        "bandwidth": 15000,
                        "type": "sensor_msgs/msg/Image",
                        "publisher_count": 1,
                        "qos_reliability": "reliable",
                        "throttled": false
                    },
                    {
                        "topic": "/lidar",
                        "msg_count": 50,
                        "frequency": 10.0,
                        "size": 200000,
                        "bandwidth": 5000,
                        "type": "sensor_msgs/msg/PointCloud2",
                        "publisher_count": 1,
                        "qos_reliability": "best_effort",
                        "throttled": false
                    }
                ]
            });
            tryCompare(recorderInterface, "state", "recording", 1000, "State should be 'recording' after status with state=1");
            compare(recorderInterface.recorderNamespace, "/test_recorder", "Namespace should be set from node_name");
            verify(recorderInterface.connected, "Should be connected after status");
            compare(recorderInterface.status.output_dir, "~/bags/");
            compare(recorderInterface.topicsModel.count, 2, "Topics model should have 2 entries");
            compare(recorderInterface.topicsModel.get(0).topic, "/camera", "First topic should be /camera");
            compare(recorderInterface.topicsModel.get(0).msgCount, 100);
            compare(recorderInterface.topicsModel.get(0).frequency, 30.0);
            compare(recorderInterface.topicsModel.get(0).type, "sensor_msgs/msg/Image");
            compare(recorderInterface.topicsModel.get(1).topic, "/lidar", "Second topic should be /lidar");
            compare(recorderInterface.topicsModel.get(1).qosReliability, "best_effort");
        }
        function test_stop_pause_resume_split_send_requests() {
            recorderInterface.recorderNamespace = "/test_recorder";
            recorderInterface.stopRecording();
            tryCompare(serviceResponseSpy, "count", 1, 1000);
            compare(serviceResponseSpy.signalArguments[0][0], "stop");
            compare(serviceResponseSpy.signalArguments[0][2], "Stopped");
            recorderInterface.pauseRecording();
            tryCompare(serviceResponseSpy, "count", 2, 1000);
            compare(serviceResponseSpy.signalArguments[1][0], "pause");
            compare(serviceResponseSpy.signalArguments[1][2], "Paused");
            recorderInterface.resumeRecording();
            tryCompare(serviceResponseSpy, "count", 3, 1000);
            compare(serviceResponseSpy.signalArguments[2][0], "resume");
            compare(serviceResponseSpy.signalArguments[2][2], "Resumed");
            recorderInterface.splitBag();
            tryCompare(serviceResponseSpy, "count", 4, 1000);
            compare(serviceResponseSpy.signalArguments[3][0], "split");
            compare(serviceResponseSpy.signalArguments[3][2], "Split");
            for (var i = 0; i < 4; ++i)
                verify(serviceResponseSpy.signalArguments[i][1], serviceResponseSpy.signalArguments[i][0] + " should succeed");
        }

        name: "RecorderInterfaceTest"
        when: windowShown
    }
}
