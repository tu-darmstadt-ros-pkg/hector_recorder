import QtQuick
import Ros2

/**
 * Backend interface for a single hector_recorder instance.
 * Subscribes to its status topic and provides service clients for remote control.
 * Extends BagProviderInterface for use with BagBrowser.
 */
BagProviderInterface {
    id: root

    supportsTransfer: true
    supportsDelete: true

    //! Whether this interface is active
    property bool enabled: true

    //! The status topic this interface subscribes to
    property string statusTopic: ""

    //! Derived: the recorder node's fully qualified name (for service calls)
    property string recorderNamespace: ""

    //! Last received status message
    property var status: null

    //! Recorder state: "idle", "recording", "paused", "disconnected"
    property string state: "disconnected"

    //! Whether we have received at least one status message recently
    readonly property bool connected: _lastUpdateMs > 0 &&
                                       (Date.now() - _lastUpdateMs) < 5000

    //! Topics model for the table
    property var topicsModel: ListModel {}

    //! Who is recording — sent to the remote recorder on startRecording
    property string recordedBy: ""

    // ========================================================================
    // Service Clients (created lazily when recorderNamespace is set)
    // ========================================================================

    property var startClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/start_recording",
            "hector_recorder_msgs/srv/StartRecording") : null
    property var stopClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/stop_recording",
            "hector_recorder_msgs/srv/StopRecording") : null
    property var pauseClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/pause_recording",
            "hector_recorder_msgs/srv/PauseRecording") : null
    property var resumeClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/resume_recording",
            "hector_recorder_msgs/srv/ResumeRecording") : null
    property var splitClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/split_bag",
            "hector_recorder_msgs/srv/SplitBag") : null
    property var configClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/apply_config",
            "hector_recorder_msgs/srv/ApplyConfig") : null
    property var saveConfigClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/save_config",
            "hector_recorder_msgs/srv/SaveConfig") : null
    property var availableTopicsClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/get_available_topics",
            "hector_recorder_msgs/srv/GetAvailableTopics") : null
    property var availableServicesClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/get_available_services",
            "hector_recorder_msgs/srv/GetAvailableServices") : null
    property var getConfigClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/get_config",
            "hector_recorder_msgs/srv/GetConfig") : null
    property var getRecorderInfoClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/get_recorder_info",
            "hector_recorder_msgs/srv/GetRecorderInfo") : null
    property var listBagsClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/list_bags",
            "hector_recorder_msgs/srv/ListBags") : null
    property var getBagDetailsClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/get_bag_details",
            "hector_recorder_msgs/srv/GetBagDetails") : null
    property var deleteBagClient: recorderNamespace
        ? Ros2.createServiceClient(recorderNamespace + "/delete_bag",
            "hector_recorder_msgs/srv/DeleteBag") : null

    // ========================================================================
    // Signals
    // ========================================================================

    signal serviceResponse(string serviceName, bool success, string message)

    // ========================================================================
    // Public API
    // ========================================================================

    function startRecording(outputDir) {
        if (!startClient) {
            serviceResponse("start", false, "Service client not available");
            return;
        }
        startClient.sendRequestAsync({
            output_dir: outputDir || "",
            recorded_by: recordedBy || ""
        }, function(response) {
            serviceResponse("start", response ? response.success : false,
                response ? response.message : "No response");
        });
    }

    function stopRecording() {
        if (!stopClient) return;
        stopClient.sendRequestAsync({}, function(response) {
            serviceResponse("stop", response ? response.success : false,
                response ? response.message : "No response");
        });
    }

    function pauseRecording() {
        if (!pauseClient) return;
        pauseClient.sendRequestAsync({}, function(response) {
            serviceResponse("pause", response ? response.success : false,
                response ? response.message : "No response");
        });
    }

    function resumeRecording() {
        if (!resumeClient) return;
        resumeClient.sendRequestAsync({}, function(response) {
            serviceResponse("resume", response ? response.success : false,
                response ? response.message : "No response");
        });
    }

    function splitBag() {
        if (!splitClient) return;
        splitClient.sendRequestAsync({}, function(response) {
            serviceResponse("split", response ? response.success : false,
                response ? response.message : "No response");
        });
    }

    function applyConfig(yamlString, restart) {
        if (!configClient) return;
        configClient.sendRequestAsync({
            config_yaml: yamlString,
            restart: restart || false
        }, function(response) {
            serviceResponse("config", response ? response.success : false,
                response ? response.message : "No response");
        });
    }

    function saveConfigToFile(yamlString, filePath) {
        if (!saveConfigClient) return;
        saveConfigClient.sendRequestAsync({
            config_yaml: yamlString,
            file_path: filePath
        }, function(response) {
            serviceResponse("save_config", response ? response.success : false,
                response ? response.message : "No response");
        });
    }

    function fetchAvailableTopics(callback) {
        if (!availableTopicsClient) return;
        availableTopicsClient.sendRequestAsync({}, function(response) {
            if (response && callback) {
                let result = [];
                for (let i = 0; i < response.topics.length; i++) {
                    result.push({
                        name: response.topics.at(i),
                        type: response.types.at(i)
                    });
                }
                callback(result);
            }
        });
    }

    function fetchAvailableServices(callback) {
        if (!availableServicesClient) return;
        availableServicesClient.sendRequestAsync({}, function(response) {
            if (response && callback) {
                let result = [];
                for (let i = 0; i < response.services.length; i++) {
                    result.push({
                        name: response.services.at(i),
                        type: response.types.at(i)
                    });
                }
                callback(result);
            }
        });
    }

    function fetchConfig(callback) {
        if (!getConfigClient) return;
        getConfigClient.sendRequestAsync({}, function(response) {
            if (response && callback) {
                callback(response.config_yaml || "");
            }
        });
    }

    function fetchRecorderInfo(callback) {
        if (!getRecorderInfoClient) return;
        getRecorderInfoClient.sendRequestAsync({}, function(response) {
            if (response && callback) {
                callback({
                    hostname: response.hostname || "",
                    recordedBy: response.recorded_by || "",
                    configPath: response.config_path || ""
                });
            }
        });
    }

    function listBags(path, callback) {
        if (!listBagsClient) return;
        listBagsClient.sendRequestAsync({path: path || ""}, function(response) {
            if (!response) return;
            if (!response.success) {
                serviceResponse("list_bags", false, response.message);
                return;
            }
            if (callback) {
                let bags = [];
                for (let i = 0; i < response.bags.length; i++) {
                    let b = response.bags.at(i);
                    bags.push({
                        name: b.name || "",
                        path: b.path || "",
                        sizeBytes: Number(b.size_bytes) || 0,
                        startTime: b.start_time || "",
                        durationSecs: Number(b.duration_secs) || 0,
                        topicCount: Number(b.topic_count) || 0,
                        messageCount: Number(b.message_count) || 0,
                        recordedBy: b.recorded_by || "",
                        storageId: b.storage_id || ""
                    });
                }
                callback(bags);
            }
        });
    }

    function getBagDetails(bagPath, callback) {
        if (!getBagDetailsClient) return;
        getBagDetailsClient.sendRequestAsync({bag_path: bagPath}, function(response) {
            if (!response) return;
            if (!response.success) {
                serviceResponse("get_bag_details", false, response.message);
                return;
            }
            if (callback) {
                let topics = [];
                for (let i = 0; i < response.topics.length; i++) {
                    let t = response.topics.at(i);
                    topics.push({
                        name: t.name || "",
                        type: t.type || "",
                        messageCount: Number(t.message_count) || 0,
                        serializationFormat: t.serialization_format || ""
                    });
                }
                callback(response.info, topics);
            }
        });
    }

    function deleteBag(bagPath, callback) {
        if (!deleteBagClient) return;
        deleteBagClient.sendRequestAsync({
            bag_path: bagPath,
            confirm: true
        }, function(response) {
            let success = response ? response.success : false;
            let message = response ? response.message : "No response";
            serviceResponse("delete_bag", success, message);
            if (callback) callback(success, message);
        });
    }

    // ========================================================================
    // Internal
    // ========================================================================

    property real _lastUpdateMs: 0

    function _processStatus(msg) {
        root.status = msg;
        root.recorderNamespace = msg.node_name || "";
        root._lastUpdateMs = Date.now();

        // Update state from enum
        switch (msg.state) {
            case 0: root.state = "idle"; break;
            case 1: root.state = "recording"; break;
            case 2: root.state = "paused"; break;
            default: root.state = "unknown";
        }

        // Update topics model in-place to preserve scroll position
        _updateTopicsModel(msg.topics);
    }

    function _updateTopicsModel(topics) {
        let count = topics ? topics.length : 0;

        while (topicsModel.count > count)
            topicsModel.remove(topicsModel.count - 1);
        while (topicsModel.count < count)
            topicsModel.append({});

        for (let i = 0; i < count; i++) {
            let t = topics.at(i);
            // Convert ROS int64 fields to JS numbers explicitly
            topicsModel.set(i, {
                topic: t.topic || "",
                msgCount: Number(t.msg_count) || 0,
                frequency: Number(t.frequency) || 0,
                size: Number(t.size) || 0,
                bandwidth: Number(t.bandwidth) || 0,
                type: t.type || "",
                publisherCount: Number(t.publisher_count) || 0,
                qosReliability: t.qos_reliability || "",
                throttled: t.throttled || false
            });
        }
    }

    // Subscription
    property Subscription _statusSub: Subscription {
        topic: root.enabled ? root.statusTopic : ""
        messageType: "hector_recorder_msgs/msg/RecorderStatus"
        qos: Ros2.QoS().reliable().keep_last(10)
        throttleRate: 0
        onNewMessage: function(msg) {
            if (!root.enabled) return;
            root._processStatus(msg);
        }
    }

    // Stale detection timer
    property Timer _staleTimer: Timer {
        interval: 3000
        running: root.enabled && root._lastUpdateMs > 0
        repeat: true
        onTriggered: {
            if ((Date.now() - root._lastUpdateMs) > 5000) {
                root.state = "disconnected";
            }
        }
    }
}
