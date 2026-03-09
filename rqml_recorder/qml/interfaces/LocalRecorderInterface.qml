import QtQuick
import RqmlRecorder

/**
 * Local recording interface that implements the same API contract as
 * RecorderInterface but records bags directly using BagRecorderEngine
 * (rosbag2_cpp::Writer + GenericSubscription) instead of remote services.
 *
 * Drop-in replacement for RecorderInterface in RecorderManager.
 */
BagProviderInterface {
    id: root

    supportsTransfer: false
    supportsDelete: true
    supportsPlayback: true

    //! Whether this interface is active
    property bool enabled: true

    //! Always empty for local recording (no remote namespace)
    property string recorderNamespace: ""

    //! Synthetic status object matching RecorderStatus message shape
    property var status: _buildStatus()

    //! Recorder state: "idle", "recording", "paused"
    property string state: engine.state

    //! Always connected for local recording
    readonly property bool connected: true

    //! Topics model for the table
    property var topicsModel: ListModel {}

    //! Whether this is a local recorder (UI can use this for conditional display)
    readonly property bool isLocal: true

    //! Number of topics selected for recording
    readonly property int selectedTopicCount: _selectedTopics.length

    //! Number of topics available on the ROS graph (cached, refreshed on discover)
    property int availableTopicCount: 0

    // ========================================================================
    // Signals
    // ========================================================================

    signal serviceResponse(string serviceName, bool success, string message)

    // ========================================================================
    // C++ Backend (declared as properties since QtObject has no default property)
    // ========================================================================

    property BagRecorderEngine engine: BagRecorderEngine {
        outputDir: "~/bags/"
        onStatsChanged: {
            root._updateTopicsModel();
            root.status = root._buildStatus();
        }

        onStateChanged: {
            root.state = engine.state;
            root.status = root._buildStatus();
        }

        onRecordingFinished: function(bagPath) {
            root.serviceResponse("stop", true, "Recording saved to " + bagPath);
        }

        onErrorMessageChanged: {
            if (engine.errorMessage) {
                root.serviceResponse("error", false, engine.errorMessage);
            }
        }
    }

    property LocalBagScanner scanner: LocalBagScanner {
        scanPath: engine.outputDir || "~/bags/"
    }

    // Refresh available topic count on creation (delayed to ensure node is ready)
    property Timer _initTimer: Timer {
        interval: 500
        onTriggered: {
            root.refreshAvailableTopics();
            // Set recorded_by from local user info
            scanner.fetchRecorderInfo(function(info) {
                if (info.recordedBy) engine.recordedBy = info.recordedBy;
            });
        }
    }
    Component.onCompleted: _initTimer.start()

    // ========================================================================
    // Public API — same as RecorderInterface
    // ========================================================================

    //! The topics argument is handled via ConfigEditor / applyConfig.
    //! For local recording, we store selected topics and pass them to startRecording.
    property var _selectedTopics: []

    function startRecording(outputDir) {
        if (_selectedTopics.length === 0) {
            // If no topics configured, discover and select all
            let topics = engine.discoverTopics();
            _selectedTopics = topics.map(function(t) { return t.name; });
        }

        // Update output dir if provided
        if (outputDir) {
            engine.outputDir = outputDir;
        }

        let topicList = [];
        for (let i = 0; i < _selectedTopics.length; i++) {
            topicList.push(_selectedTopics[i]);
        }

        engine.startRecording(topicList, outputDir || "");
        if (engine.state !== "idle") {
            serviceResponse("start", true, "Recording started");
        }
    }

    function stopRecording() {
        engine.stopRecording();
    }

    function pauseRecording() {
        engine.pauseRecording();
        serviceResponse("pause", true, "Recording paused");
    }

    function resumeRecording() {
        engine.resumeRecording();
        serviceResponse("resume", true, "Recording resumed");
    }

    function splitBag() {
        engine.splitBag();
        serviceResponse("split", true, "Bag split requested");
    }

    function applyConfig(yamlString, restart) {
        // Parse YAML to extract topic list for local recording
        let topics = _parseTopicsFromYaml(yamlString);
        if (topics.length > 0) {
            _selectedTopics = topics;
        }

        // Restart recording if requested and currently running
        if (restart && engine.state !== "idle") {
            let dir = engine.outputDir;
            engine.stopRecording();
            engine.startRecording(_selectedTopics, dir);
        }

        root.status = root._buildStatus();
        serviceResponse("config", true,
            "Selected " + _selectedTopics.length + " topic(s) for recording");
    }

    function fetchConfig(callback) {
        if (!callback) return;

        // Build a simple YAML from selected topics
        let yaml = "# Local recording configuration\n";
        yaml += "output: \"" + (engine.outputDir || "~/bags/") + "\"\n";
        yaml += "topics:\n";
        for (let i = 0; i < _selectedTopics.length; i++) {
            yaml += "  - " + _selectedTopics[i] + "\n";
        }
        callback(yaml);
    }

    function refreshAvailableTopics() {
        let topics = engine.discoverTopics();
        availableTopicCount = topics.length;
        return topics;
    }

    function fetchAvailableTopics(callback) {
        if (!callback) return;
        let topics = refreshAvailableTopics();
        callback(topics);
    }

    function fetchRecorderInfo(callback) {
        if (!callback) return;
        scanner.fetchRecorderInfo(callback);
    }

    // BagProviderInterface overrides — delegate to LocalBagScanner
    function listBags(path, callback) {
        scanner.listBags(path, callback);
    }

    function getBagDetails(bagPath, callback) {
        scanner.getBagDetails(bagPath, callback);
    }

    function deleteBag(bagPath, callback) {
        scanner.deleteBag(bagPath, function(success, message) {
            serviceResponse("delete_bag", success, message);
            if (callback) callback(success, message);
        });
    }

    // ========================================================================
    // Internal
    // ========================================================================

    function _buildStatus() {
        return {
            node_name: "local_recorder",
            state: engine.state === "recording" ? 1 : engine.state === "paused" ? 2 : 0,
            duration: engine.duration,
            size: engine.totalSize,
            output_dir: engine.outputDir || "~/bags/",
            files: engine.currentBagPath ? [engine.currentBagPath] : [],
            topics: engine.getTopicStats()
        };
    }

    function _updateTopicsModel() {
        let stats = engine.getTopicStats();
        let count = stats.length;

        while (topicsModel.count > count)
            topicsModel.remove(topicsModel.count - 1);
        while (topicsModel.count < count)
            topicsModel.append({});

        for (let i = 0; i < count; i++) {
            let t = stats[i];
            topicsModel.set(i, {
                topic: t.topic || "",
                msgCount: t.msgCount || 0,
                frequency: t.frequency || 0,
                size: t.size || 0,
                bandwidth: t.bandwidth || 0,
                type: t.type || "",
                publisherCount: t.publisherCount || 0,
                qosReliability: "",
                throttled: false
            });
        }
    }

    function _parseTopicsFromYaml(yaml) {
        // Simple YAML topic list parser
        // Matches lines like "  - /topic_name" under a "topics:" section
        let topics = [];
        let lines = yaml.split("\n");
        let inTopics = false;
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i];
            if (line.match(/^topics:/)) {
                inTopics = true;
                continue;
            }
            if (inTopics) {
                let m = line.match(/^\s+-\s+(\S+)/);
                if (m) {
                    topics.push(m[1]);
                } else if (line.match(/^\S/) && line.trim().length > 0) {
                    inTopics = false;
                }
            }
        }
        return topics;
    }
}
