import QtQuick

QtObject {
    id: root

    property string _lastStartDir: ""

    // Mock tracking
    property var _lastStartTopics: []
    property var _mockTopicStats: []
    property var _mockTopics: []
    property int _pauseCount: 0
    property int _resumeCount: 0
    property int _splitCount: 0
    property int _startCount: 0
    property int _stopCount: 0
    property string currentBagPath: ""
    property double duration: 0
    property string errorMessage: ""
    property int messageCount: 0
    property string outputDir: "~/bags/"
    property string recordedBy: ""
    property string state: "idle"
    property int topicCount: 0
    property double totalSize: 0

    signal recordingFinished(string bagPath)
    signal statsChanged

    function discoverTopics() {
        return _mockTopics;
    }
    function getTopicStats() {
        return _mockTopicStats;
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
}
