import QtQuick
import QtQuick.Controls
import QtTest
import RQml.Recorder

Item {
    id: root

    property var context: contextObj
    property var plugin: pluginLoader.item

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 600
    width: 800

    QtObject {
        id: contextObj

        // Left undefined so the plugin's `?? "~/bags/"` default applies
        property var bag_path: undefined
    }
    Utils {
        id: helpers

    }
    Loader {
        id: pluginLoader

        function reload() {
            source = "";
            source = "../qml/BagPlayer.qml";
        }

        anchors.fill: parent
    }
    TestCase {
        function init() {
            contextObj.bag_path = undefined;
            pluginLoader.reload();
            tryVerify(function () {
                return pluginLoader.status === Loader.Ready;
            }, 2000, "Loader should be ready");
        }
        function requestPlay(name, path) {
            // The browser's play buttons emit playRequested(path, name)
            find("bagPlayerBagBrowser").playRequested(path, name);
        }
        function scanAndFindPlayButton(name, path) {
            find("bagPlayerScanner")._mockBags = [
                {
                    "name": name,
                    "path": path,
                    "sizeBytes": 1024,
                    "startTime": "2025-01-01",
                    "durationSecs": 60,
                    "topicCount": 2,
                    "messageCount": 100,
                    "recordedBy": "user",
                    "storageId": "sqlite3"
                }
            ];
            mouseClick(find("bagPlayerScanButton"));
            var playButton = null;
            tryVerify(function () {
                playButton = find("bagBrowserPlayButton_0");
                return playButton !== null && playButton.visible && playButton.width > 0;
            }, 2000, "Scanned bag should be listed with a play button");
            return playButton;
        }
        function test_engine_error_is_shown_in_status() {
            var engine = find("bagPlayerEngine");
            engine.errorMessage = "Test error message";
            tryCompare(find("bagPlayerStatusLabel"), "text", "✗ Test error message", 1000);
        }
        function test_path_autocomplete() {
            var scanner = find("bagPlayerScanner");
            var pathField = find("bagPlayerPathField");
            var popup = find("bagPlayerCompletionPopup");
            var list = find("bagPlayerCompletionList");
            scanner._mockCompletions = ["/home/user/bags/", "/home/user/backup/"];
            pathField.forceActiveFocus();
            pathField.text = "/home/user/b";
            keyClick(Qt.Key_A);
            tryCompare(popup, "visible", true, 1000, "Completion popup should open");
            compare(list.count, 2, "Should show 2 completions");
            var first = null;
            tryVerify(function () {
                first = find("bagPlayerCompletionItem_0");
                return first !== null && find("bagPlayerCompletionItem_1") !== null;
            }, 1000);
            compare(first.contentItem.text, "/home/user/bags/");
            compare(find("bagPlayerCompletionItem_1").contentItem.text, "/home/user/backup/");

            // Accepting the highlighted completion fills the field
            keyClick(Qt.Key_Tab);
            compare(pathField.text, "/home/user/bags/");

            // No completions closes the popup
            scanner._mockCompletions = [];
            pathField.text = "/nonexistent";
            keyClick(Qt.Key_Slash);
            tryCompare(popup, "visible", false, 1000, "Popup should close without completions");
            compare(list.count, 0, "Should show no completions");
        }
        function test_play_requested_loads_and_plays_bag() {
            var engine = find("bagPlayerEngine");
            var playButton = scanAndFindPlayButton("test_bag", "/bags/test_bag");
            var states = [];
            var recordState = function () {
                states.push(engine.state);
            };
            engine.stateChanged.connect(recordState);
            mouseClick(playButton);
            engine.stateChanged.disconnect(recordState);
            compare(engine._loadCount, 1, "Load should be called");
            compare(engine.bagPath, "/bags/test_bag");
            compare(engine.bagName, "test_bag", "Bag name should be extracted");
            compare(engine._playCount, 1, "Play should be called");
            compare(engine._lastPlayTopics.length, 0, "Auto-play should play all topics");
            compare(states, ["loaded", "playing"], "Engine should be loaded, then playing");
            compare(engine.state, "playing", "Engine should be playing");
            compare(find("bagPlayerStatusLabel").text, "▶ Playing: test_bag");
            tryCompare(find("bagPlayerPlaybackPanel"), "expanded", true, 1000);
        }
        function test_playback_finished_is_shown_in_status() {
            var engine = find("bagPlayerEngine");
            requestPlay("finished_bag", "/bags/finished_bag");
            engine.playbackFinished();
            compare(find("bagPlayerStatusLabel").text, "✓ Playback finished: finished_bag");
        }
        function test_player_engine_starts_idle() {
            var engine = find("bagPlayerEngine");
            verify(engine !== null, "Player engine should exist");
            compare(engine.state, "idle", "Engine should start idle");
            compare(find("bagPlayerPlaybackPanel").expanded, false, "Playback panel should be collapsed while idle");
        }
        function test_plugin_loads_with_default_path() {
            verify(plugin !== null, "BagPlayer should load");
            var pathField = find("bagPlayerPathField");
            verify(pathField !== null, "Path field should exist");
            tryCompare(pathField, "text", "~/bags/", 1000, "Default bag path should be ~/bags/");
            compare(pathField.placeholderText, "~/bags/", "Path field should show the default path as placeholder");
        }
        function test_scan_persists_path_to_context() {
            var pathField = find("bagPlayerPathField");
            verify(pathField !== null, "Path field should exist");
            pathField.text = "/tmp/other_bags/";
            mouseClick(find("bagPlayerScanButton"));
            tryCompare(contextObj, "bag_path", "/tmp/other_bags/", 1000, "Applying a path should persist it to context");
            compare(find("bagPlayerBagBrowser").currentPath, "/tmp/other_bags/");
            compare(find("bagPlayerScanner").scanPath, "/tmp/other_bags/");
        }
        function test_scanner_uses_default_path() {
            var scanner = find("bagPlayerScanner");
            verify(scanner !== null, "Scanner should exist");
            compare(scanner.scanPath, "~/bags/");
        }
        function test_stop_returns_to_idle() {
            var engine = find("bagPlayerEngine");
            requestPlay("finished_bag", "/bags/finished_bag");
            tryCompare(engine, "state", "playing", 1000);
            waitForPanelFullyExpanded();
            mouseClick(find("playbackPanelStopButton"));
            compare(engine._stopCount, 1, "Stop should be called");
            compare(engine.state, "idle");
            tryCompare(find("bagPlayerPlaybackPanel"), "expanded", false, 1000);
        }
        function waitForPanelFullyExpanded() {
            var panel = find("bagPlayerPlaybackPanel");
            tryVerify(function () {
                var stopButton = find("playbackPanelStopButton");
                var pos = stopButton.mapToItem(panel, 0, 0);
                return panel.expanded && pos.y + stopButton.height <= panel.height;
            }, 2000, "Playback panel should finish expanding");
        }

        name: "BagPlayerTest"
        when: windowShown
    }
}
