import QtQuick

QtObject {
    id: root

    property string state: "idle"
    property string outputDir: "~/bags/"
    property string recordedBy: ""
    property string currentBagPath: ""
    property double duration: 0
    property double totalSize: 0
    property int messageCount: 0
    property int topicCount: 0
    property string errorMessage: ""

    signal statsChanged()
    signal recordingFinished(string bagPath)

    // Mock tracking
    property var _lastStartTopics: []
    property string _lastStartDir: ""
    property var _mockTopics: []
    property var _mockTopicStats: []
    property int _startCount: 0
    property int _stopCount: 0
    property int _pauseCount: 0
    property int _resumeCount: 0
    property int _splitCount: 0

    function discoverTopics() {
        return _mockTopics;
    }

    function startRecording(topics, outputDir) {
        _lastStartTopics = topics;
        _lastStartDir = outputDir || "";
        _startCount++;
        root.state = "recording";
    }

    function stopRecording() {
        _stopCount++;
        root.state = "idle";
        recordingFinished(currentBagPath);
    }

    function pauseRecording() {
        _pauseCount++;
        root.state = "paused";
    }

    function resumeRecording() {
        _resumeCount++;
        root.state = "recording";
    }

    function splitBag() {
        _splitCount++;
    }

    function getTopicStats() {
        return _mockTopicStats;
    }
}
