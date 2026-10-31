import QtQuick
import QtQuick.Controls
import QtTest
import RQml.Recorder
import "../qml/elements" as Elements

Item {
    id: root

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 600
    width: 800

    Utils {
        id: helpers

    }
    BagPlayerEngine {
        id: mockEngine

    }
    Elements.PlaybackPanel {
        id: panel

        anchors.left: parent.left
        anchors.right: parent.right
        engine: mockEngine
    }
    TestCase {
        function clickUncovered(name) {
            var item = find(name);
            waitUntilUncovered(item);
            mouseClick(item);
        }
        function expandWith(state) {
            mockEngine.state = state;
            tryCompare(panel, "expanded", true, 1000);
            waitUntilUncovered(find("playbackPanelTopicFilterToggle"));
        }
        function init() {
            mockEngine.state = "idle";
            mockEngine.rate = 1.0;
            mockEngine.looping = false;
            mockEngine.clockEnabled = false;
            mockEngine.duration = 0;
            mockEngine.currentTime = 0;
            mockEngine.progress = 0;
            mockEngine.topicList = [];
            mockEngine.topicCount = 0;
            mockEngine.messageCount = 0;
            mockEngine.errorMessage = "";
            mockEngine.bagPath = "";
            mockEngine.bagName = "";
            mockEngine._loadCount = 0;
            mockEngine._playCount = 0;
            mockEngine._pauseCount = 0;
            mockEngine._resumeCount = 0;
            mockEngine._stopCount = 0;
            mockEngine._seekCount = 0;
            mockEngine._stepForwardCount = 0;
            mockEngine._lastSeek = 0;
            mockEngine._lastPlayTopics = [];
            mockEngine._topicEnabled = {};
            mockEngine.metadataChanged();
            find("playbackPanelTopicFilterToggle").topicFilterExpanded = false;
            tryCompare(panel, "height", 0, 2000, "Panel should be collapsed after reset");
        }
        // Items that just became visible share a position until their layout runs.
        function overlapsSibling(item) {
            var siblings = item.parent ? item.parent.children : [];
            for (var i = 0; i < siblings.length; ++i) {
                var other = siblings[i];
                if (other === item || !other.visible || other.width <= 0 || other.height <= 0)
                    continue;
                if (other.x < item.x + item.width && item.x < other.x + other.width && other.y < item.y + item.height && item.y < other.y + other.height)
                    return true;
            }
            return false;
        }
        function setTopics(topics) {
            mockEngine.topicList = topics;
            mockEngine.topicCount = topics.length;
            mockEngine.metadataChanged();
        }
        function test_clock_settings() {
            expandWith("playing");
            var clockCheckbox = find("playbackPanelClockCheckbox");
            compare(mockEngine.clockEnabled, false, "Clock should be off initially");
            compare(clockCheckbox.checked, false);
            mouseClick(clockCheckbox);
            compare(mockEngine.clockEnabled, true, "Clock should be on");
        }
        function test_error_message_shown() {
            expandWith("loaded");
            var errorLabel = find("playbackPanelErrorLabel");
            compare(errorLabel.visible, false, "Error label hidden without error");
            mockEngine.errorMessage = "Something failed";
            compare(errorLabel.text, "Something failed");
            compare(errorLabel.visible, true);
        }
        function test_expanded_when_finished() {
            mockEngine.state = "finished";
            tryCompare(panel, "expanded", true, 1000, "Should stay expanded in finished state");
        }
        function test_expanded_when_loaded() {
            mockEngine.state = "loaded";
            tryCompare(panel, "expanded", true, 1000, "Should be expanded when loaded");
            tryCompare(panel, "visible", true, 1000);
        }
        function test_expanded_when_playing() {
            mockEngine.state = "playing";
            tryCompare(panel, "expanded", true, 1000, "Should be expanded when playing");
        }
        function test_header_shows_engine_info() {
            mockEngine.bagName = "my_bag";
            mockEngine.topicCount = 2;
            mockEngine.messageCount = 42;
            mockEngine.duration = 3725;
            mockEngine.currentTime = 65;
            expandWith("playing");
            compare(find("playbackPanelStateLabel").text, "Playing");
            compare(find("playbackPanelBagNameLabel").text, "my_bag");
            compare(find("playbackPanelTopicCountLabel").text, "2 topics, 42 msgs");
            compare(find("playbackPanelCurrentTimeLabel").text, "0:01:05");
            compare(find("playbackPanelDurationLabel").text, "1:02:05");
        }
        function test_hidden_when_idle() {
            compare(mockEngine.state, "idle");
            compare(panel.expanded, false, "Should not be expanded when idle");
            compare(panel.visible, false, "Should be hidden when idle");
        }
        function test_loop_toggle() {
            expandWith("playing");
            var loopButton = find("playbackPanelLoopButton");
            compare(mockEngine.looping, false, "Looping should be off initially");
            compare(loopButton.checked, false);
            mouseClick(loopButton);
            compare(mockEngine.looping, true, "Looping should be on");
            mouseClick(loopButton);
            compare(mockEngine.looping, false, "Looping should be off again");
        }
        function test_play_button_restarts_when_finished() {
            expandWith("finished");
            clickUncovered("playbackPanelPlayPauseButton");
            compare(mockEngine._playCount, 1, "Play should be called from finished state");
            compare(mockEngine.state, "playing");
        }
        function test_play_button_starts_playback_from_loaded() {
            mockEngine.duration = 60;
            setTopics(["/cam", "/imu"]);
            expandWith("loaded");
            var playPause = find("playbackPanelPlayPauseButton");
            compare(playPause.ToolTip.text, "Play");
            mouseClick(playPause);
            compare(mockEngine._playCount, 1, "Play should be called");
            compare(mockEngine._lastPlayTopics.length, 0, "All topics selected plays everything");
            compare(mockEngine.state, "playing");
            compare(playPause.ToolTip.text, "Pause");
        }
        function test_play_pause_toggle() {
            expandWith("playing");
            var playPause = find("playbackPanelPlayPauseButton");
            mouseClick(playPause);
            compare(mockEngine._pauseCount, 1, "Pause should be called");
            compare(mockEngine.state, "paused");
            mouseClick(playPause);
            compare(mockEngine._resumeCount, 1, "Resume should be called");
            compare(mockEngine.state, "playing");
        }
        function test_progress_follows_engine() {
            mockEngine.duration = 120;
            expandWith("playing");
            mockEngine.progress = 0.5;
            tryCompare(find("playbackPanelProgressSlider"), "value", 0.5, 1000);
        }
        function test_rate_follows_engine() {
            expandWith("playing");
            var spinBox = find("playbackPanelRateSpinBox");
            compare(spinBox.value, 100);
            mockEngine.rate = 2.0;
            compare(spinBox.value, 200, "Rate should be 2x");
            mockEngine.rate = 0.5;
            compare(spinBox.value, 50, "Rate should be 0.5x");
            mockEngine.rate = 10.0;
            compare(spinBox.value, 1000, "Rate should be 10x");
            compare(spinBox.displayText, "10.00x");
        }
        function test_rate_spinbox_sets_engine_rate() {
            expandWith("playing");
            var spinBox = find("playbackPanelRateSpinBox");
            spinBox.forceActiveFocus();
            keyClick(Qt.Key_Up);
            compare(mockEngine.rate, 1.25, "Stepping up should increase rate by 0.25x");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            compare(mockEngine.rate, 0.75, "Stepping down should decrease rate by 0.25x");
        }
        function test_seek() {
            mockEngine.duration = 120;
            expandWith("playing");
            var slider = find("playbackPanelProgressSlider");
            verify(slider.enabled, "Progress slider should be enabled while playing");
            mouseClick(slider, slider.leftPadding + slider.availableWidth * 0.25, slider.height / 2);
            compare(mockEngine._seekCount, 1, "Seek should be called");
            fuzzyCompare(mockEngine._lastSeek, 30, 3, "Should seek to ~30s");

            // Seek to start
            clickUncovered("playbackPanelStepBackButton");
            compare(mockEngine._seekCount, 2);
            compare(mockEngine._lastSeek, 0, "Should seek to 0");
        }
        function test_step_forward_steps_engine_only_when_paused_or_loaded() {
            var stepForward = find("playbackPanelStepForwardButton");
            expandWith("paused");
            verify(stepForward.enabled, "Step forward should be enabled when paused");
            mouseClick(stepForward);
            compare(mockEngine._stepForwardCount, 1, "Click should step the engine forward");
            compare(mockEngine.state, "paused", "Stepping should not change state");
            mockEngine.state = "loaded";
            verify(stepForward.enabled, "Step forward should be enabled when loaded");
            mockEngine.state = "playing";
            verify(!stepForward.enabled, "Step forward should be disabled while playing");
        }
        function test_stop_returns_to_idle() {
            expandWith("playing");
            clickUncovered("playbackPanelStopButton");
            compare(mockEngine._stopCount, 1, "Stop should be called");
            compare(mockEngine.state, "idle");
            tryCompare(panel, "expanded", false, 2000, "Should collapse after stop");
            tryCompare(panel, "visible", false, 2000);
        }
        function test_topic_filter() {
            setTopics(["/camera", "/lidar", "/imu"]);
            expandWith("loaded");
            var countLabel = find("playbackPanelTopicSelectedCountLabel");
            compare(countLabel.text, "3 / 3 selected");
            clickUncovered("playbackPanelTopicFilterToggle");
            var cameraCheckbox = find("playbackPanelTopicCheckbox_0");
            verify(cameraCheckbox !== null, "Topic checkboxes should exist");
            waitUntilUncovered(cameraCheckbox);
            compare(cameraCheckbox.text, "/camera");

            // Disable a topic
            mouseClick(cameraCheckbox);
            compare(mockEngine._topicEnabled["/camera"], false, "Camera should be disabled");
            compare(countLabel.text, "2 / 3 selected");

            // Playing only sends the selected topics
            clickUncovered("playbackPanelPlayPauseButton");
            compare(mockEngine._lastPlayTopics, ["/lidar", "/imu"]);

            // Re-enable
            mouseClick(cameraCheckbox);
            compare(mockEngine._topicEnabled["/camera"], true, "Camera should be re-enabled");
            compare(countLabel.text, "3 / 3 selected");
        }
        function test_topic_filter_all_and_none() {
            setTopics(["/camera", "/lidar"]);
            expandWith("loaded");
            clickUncovered("playbackPanelTopicFilterToggle");
            clickUncovered("playbackPanelTopicNoneButton");
            compare(mockEngine._topicEnabled["/camera"], false);
            compare(mockEngine._topicEnabled["/lidar"], false);
            compare(find("playbackPanelTopicSelectedCountLabel").text, "0 / 2 selected");
            clickUncovered("playbackPanelTopicAllButton");
            compare(mockEngine._topicEnabled["/camera"], true);
            compare(mockEngine._topicEnabled["/lidar"], true);
            compare(find("playbackPanelTopicSelectedCountLabel").text, "2 / 2 selected");
        }
        // The panel animates its height and clips; wait until an item is fully inside it.
        function waitUntilUncovered(item) {
            tryVerify(function () {
                var pos = item.mapToItem(panel, 0, 0);
                return item.visible && item.height > 0 && pos.y + item.height <= panel.height && !overlapsSibling(item);
            }, 2000, "Item should be fully visible in the panel");
        }

        name: "PlaybackPanelTest"
        when: windowShown
    }
}
