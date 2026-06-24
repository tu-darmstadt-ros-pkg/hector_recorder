import QtQuick
import QtQuick.Controls
import QtTest
import "../qml/elements" as Elements
import RQml.Recorder

Item {
    id: windowRoot
    width: 800
    height: 600

    BagPlayerEngine {
        id: mockEngine
    }

    Elements.PlaybackPanel {
        id: panel
        anchors.fill: parent
        engine: mockEngine
    }

    TestCase {
        name: "PlaybackPanelTest"
        when: windowShown

        function init() {
            mockEngine.state = "idle";
            mockEngine.rate = 1.0;
            mockEngine.looping = false;
            mockEngine.clockEnabled = false;
            mockEngine.clockFrequency = 100;
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
            mockEngine._topicEnabled = {};
        }

        // ---- Test 1: Hidden when idle ----
        function test_01_hidden_when_idle() {
            compare(mockEngine.state, "idle");
            compare(panel.expanded, false, "Should not be expanded when idle");
        }

        // ---- Test 2: Expanded when loaded ----
        function test_02_expanded_when_loaded() {
            mockEngine.state = "loaded";
            tryCompare(panel, "expanded", true, 1000, "Should be expanded when loaded");
        }

        // ---- Test 3: Expanded when playing ----
        function test_03_expanded_when_playing() {
            mockEngine.state = "playing";
            tryCompare(panel, "expanded", true, 1000, "Should be expanded when playing");
        }

        // ---- Test 4: Play/pause toggle based on state ----
        function test_04_play_pause_toggle() {
            // From loaded state, play starts playback
            mockEngine.state = "loaded";
            mockEngine.duration = 60;
            mockEngine.topicList = ["/cam", "/imu"];
            mockEngine.topicCount = 2;

            // Verify panel is expanded
            tryCompare(panel, "expanded", true, 1000);

            // Simulate pause from playing state
            mockEngine.state = "playing";
            tryCompare(panel, "expanded", true, 1000);
            mockEngine.pause();
            compare(mockEngine._pauseCount, 1, "Pause should be called");
            compare(mockEngine.state, "paused");

            // Resume from paused
            mockEngine.resume();
            compare(mockEngine._resumeCount, 1, "Resume should be called");
            compare(mockEngine.state, "playing");
        }

        // ---- Test 5: Stop returns to idle ----
        function test_05_stop_returns_to_idle() {
            mockEngine.state = "playing";
            tryCompare(panel, "expanded", true, 1000);

            mockEngine.stop();
            compare(mockEngine._stopCount, 1, "Stop should be called");
            compare(mockEngine.state, "idle");
            // Poll the collapse animation rather than waiting a fixed duration
            tryCompare(panel, "expanded", false, 2000, "Should collapse after stop");
        }

        // ---- Test 6: Seek ----
        function test_06_seek() {
            mockEngine.state = "playing";
            mockEngine.duration = 120;
            tryCompare(panel, "expanded", true, 1000);

            mockEngine.seek(30);
            compare(mockEngine._seekCount, 1, "Seek should be called");
            compare(mockEngine._lastSeek, 30, "Should seek to 30s");

            // Seek to start
            mockEngine.seek(0);
            compare(mockEngine._seekCount, 2);
            compare(mockEngine._lastSeek, 0, "Should seek to 0");
        }

        // ---- Test 7: Rate presets ----
        function test_07_rate_presets() {
            mockEngine.state = "playing";
            tryCompare(panel, "expanded", true, 1000);

            mockEngine.rate = 2.0;
            compare(mockEngine.rate, 2.0, "Rate should be 2x");

            mockEngine.rate = 0.5;
            compare(mockEngine.rate, 0.5, "Rate should be 0.5x");

            mockEngine.rate = 10.0;
            compare(mockEngine.rate, 10.0, "Rate should be 10x");
        }

        // ---- Test 8: Loop toggle ----
        function test_08_loop_toggle() {
            mockEngine.state = "playing";
            tryCompare(panel, "expanded", true, 1000);

            compare(mockEngine.looping, false, "Looping should be off initially");
            mockEngine.looping = true;
            compare(mockEngine.looping, true, "Looping should be on");
            mockEngine.looping = false;
            compare(mockEngine.looping, false, "Looping should be off again");
        }

        // ---- Test 9: Clock settings ----
        function test_09_clock_settings() {
            mockEngine.state = "playing";
            tryCompare(panel, "expanded", true, 1000);

            compare(mockEngine.clockEnabled, false, "Clock should be off initially");
            mockEngine.clockEnabled = true;
            compare(mockEngine.clockEnabled, true, "Clock should be on");

            mockEngine.clockFrequency = 200;
            compare(mockEngine.clockFrequency, 200, "Clock frequency should be 200 Hz");
        }

        // ---- Test 10: Topic filter ----
        function test_10_topic_filter() {
            mockEngine.state = "loaded";
            mockEngine.topicList = ["/camera", "/lidar", "/imu"];
            mockEngine.topicCount = 3;
            mockEngine.metadataChanged();
            tryCompare(panel, "expanded", true, 1000);

            // Disable a topic
            mockEngine.setTopicEnabled("/camera", false);
            compare(mockEngine._topicEnabled["/camera"], false,
                "Camera should be disabled");

            // Re-enable
            mockEngine.setTopicEnabled("/camera", true);
            compare(mockEngine._topicEnabled["/camera"], true,
                "Camera should be re-enabled");
        }

        // ---- Test 11: Finished state ----
        function test_11_finished_state() {
            mockEngine.state = "finished";
            tryCompare(panel, "expanded", true, 1000,
                "Should stay expanded in finished state");
        }

        // ---- Test 12: Step forward ----
        function test_12_step_forward() {
            mockEngine.state = "paused";
            tryCompare(panel, "expanded", true, 1000);

            var result = mockEngine.stepForward();
            compare(result, true, "stepForward should return true");
        }
    }
}
