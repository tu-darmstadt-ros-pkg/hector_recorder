import QtQuick

QtObject {
    id: root

    property var _lastPlayTopics: []
    property double _lastSeek: 0

    // Mock tracking
    property int _loadCount: 0
    property int _pauseCount: 0
    property int _playCount: 0
    property int _resumeCount: 0
    property int _seekCount: 0
    property int _stepForwardCount: 0
    property int _stopCount: 0
    property var _topicEnabled: ({})
    property string bagName: ""
    property string bagPath: ""
    property bool clockEnabled: false
    property double currentTime: 0
    property double duration: 0
    property string errorMessage: ""
    property bool looping: false
    property int messageCount: 0
    property double progress: 0
    property double rate: 1.0
    property string state: "idle"
    property int topicCount: 0
    property var topicList: []

    signal metadataChanged
    signal playbackFinished

    function load(path) {
        _loadCount++;
        bagPath = path;
        bagName = path.split("/").pop();
        state = "loaded";
    }
    function pause() {
        _pauseCount++;
        state = "paused";
    }
    function play(topicFilter) {
        _playCount++;
        _lastPlayTopics = topicFilter || [];
        state = "playing";
    }
    function resume() {
        _resumeCount++;
        state = "playing";
    }
    function seek(seconds) {
        _seekCount++;
        _lastSeek = seconds;
    }
    function setTopicEnabled(topic, enabled) {
        _topicEnabled[topic] = enabled;
    }
    function stepForward() {
        _stepForwardCount++;
        return true;
    }
    function stop() {
        _stopCount++;
        state = "idle";
    }
}
