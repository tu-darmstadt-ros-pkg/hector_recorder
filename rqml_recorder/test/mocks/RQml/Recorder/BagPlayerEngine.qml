import QtQuick

QtObject {
    id: root

    property string bagPath: ""
    property string bagName: ""
    property string state: "idle"
    property double rate: 1.0
    property bool looping: false
    property double duration: 0
    property double currentTime: 0
    property double progress: 0
    property bool clockEnabled: false
    property double clockFrequency: 100
    property int topicCount: 0
    property int messageCount: 0
    property var topicList: []
    property string errorMessage: ""

    signal metadataChanged()
    signal playbackFinished()

    // Mock tracking
    property int _loadCount: 0
    property int _playCount: 0
    property int _pauseCount: 0
    property int _resumeCount: 0
    property int _stopCount: 0
    property int _seekCount: 0
    property double _lastSeek: 0
    property var _lastPlayTopics: []
    property var _topicEnabled: ({})

    function load(path) {
        _loadCount++;
        bagPath = path;
        bagName = path.split("/").pop();
        state = "loaded";
    }

    function play(topicFilter) {
        _playCount++;
        _lastPlayTopics = topicFilter || [];
        state = "playing";
    }

    function pause() {
        _pauseCount++;
        state = "paused";
    }

    function resume() {
        _resumeCount++;
        state = "playing";
    }

    function stop() {
        _stopCount++;
        state = "idle";
    }

    function seek(seconds) {
        _seekCount++;
        _lastSeek = seconds;
    }

    function stepForward() {
        return true;
    }

    function setTopicEnabled(topic, enabled) {
        _topicEnabled[topic] = enabled;
    }
}
