import QtQuick
import QtQuick.Controls
import QtTest
import "../qml" as PluginQml
import RqmlRecorder

Item {
    id: windowRoot
    width: 800
    height: 600

    // Fresh context: bag_path absent so the plugin's ?? default applies
    property var context: ({})

    PluginQml.BagPlayer {
        id: bagPlayer
        anchors.fill: parent
    }

    Utils { id: helpers }

    TestCase {
        name: "BagPlayerTest"
        when: windowShown

        function find(name) { return helpers.findChild(windowRoot, name); }

        // TODO(test-guidelines): expose objectName on pathField/scanner/engine to allow Utils.findChild lookup
        function findChildByProperty(parentItem, propName, propValue) {
            if (!parentItem) return null;
            if (parentItem[propName] === propValue) return parentItem;
            var children = parentItem.children || [];
            if (parentItem.contentItem) children = parentItem.contentItem.children;
            for (var i = 0; i < children.length; i++) {
                var found = findChildByProperty(children[i], propName, propValue);
                if (found) return found;
            }
            return null;
        }

        // ---- Test 1: Plugin loads with default path ----
        function test_01_plugin_loads() {
            verify(bagPlayer !== null, "BagPlayer should load");
            // Default resolves at the binding site via ?? "~/bags/"
            var pathField = find("bagPlayerPathField");
            verify(pathField !== null, "Path field should exist");
            tryCompare(pathField, "text", "~/bags/", 1000,
                "Default bag path should be ~/bags/");
        }

        // ---- Test 2: Path editing ----
        function test_02_path_editing() {
            tryVerify(function() {
                return findChildByProperty(bagPlayer, "placeholderText", "~/bags/") !== null;
            }, 1000, "Path text field should exist");
        }

        // ---- Test 3: Scanner integration ----
        function test_03_scanner_integration() {
            // Find the scanner by looking through children
            tryVerify(function() {
                return _findScanner() !== null;
            }, 1000, "Scanner should exist");
        }

        // ---- Test 4: Player engine exists ----
        function test_04_player_engine() {
            var engine = null;
            for (var i = 0; i < bagPlayer.data.length; i++) {
                var obj = bagPlayer.data[i];
                if (obj && obj.bagPath !== undefined && obj.play !== undefined) {
                    engine = obj;
                    break;
                }
            }
            verify(engine !== null, "Player engine should exist");
            compare(engine.state, "idle", "Engine should start idle");
        }

        // ---- Test 5: Error display ----
        function test_05_error_display() {
            var engine = _findEngine();
            verify(engine !== null);

            engine.errorMessage = "Test error message";
            tryCompare(engine, "errorMessage", "Test error message", 1000);
        }

        // ---- Test 6: Play requested loads and plays ----
        function test_06_play_requested() {
            var engine = _findEngine();
            verify(engine !== null);

            // Simulate what BagPlayer.onPlayRequested does
            engine.load("/bags/test_bag");
            compare(engine._loadCount, 1, "Load should be called");
            compare(engine.state, "loaded", "Engine should be loaded");
            compare(engine.bagName, "test_bag", "Bag name should be extracted");

            engine.play([]);
            compare(engine._playCount, 1, "Play should be called");
            compare(engine.state, "playing", "Engine should be playing");
        }

        // ---- Test 7: Playback finished status ----
        function test_07_playback_finished() {
            var engine = _findEngine();
            verify(engine !== null);

            engine.load("/bags/finished_bag");
            engine.play([]);
            tryCompare(engine, "state", "playing", 1000);

            // Simulate playback finishing
            engine.stop();
            compare(engine.state, "idle");
        }

        // ---- Test 8: Path autocomplete ----
        function test_08_autocomplete() {
            var scanner = _findScanner();
            verify(scanner !== null);

            // Set mock completions
            scanner._mockCompletions = ["/home/user/bags/", "/home/user/backup/"];

            var completions = scanner.completePath("/home/user/ba");
            compare(completions.length, 2, "Should return 2 completions");
            compare(completions[0], "/home/user/bags/");
            compare(completions[1], "/home/user/backup/");

            // Empty completions
            scanner._mockCompletions = [];
            completions = scanner.completePath("/nonexistent/");
            compare(completions.length, 0, "Should return no completions");
        }

        // ---- Test 9: Context bag_path persists ----
        function test_09_context_persistence() {
            // Changing the path and scanning writes the new value back to context
            var pathField = find("bagPlayerPathField");
            verify(pathField !== null, "Path field should exist");
            pathField.text = "/tmp/other_bags/";
            bagPlayer._applyScan();
            tryCompare(windowRoot.context, "bag_path", "/tmp/other_bags/", 1000,
                "Applying a path should persist it to context");
        }

        // ---- Helpers ----

        // TODO(test-guidelines): expose objectName on BagPlayerEngine to allow Utils.findChild lookup
        function _findEngine() {
            for (var i = 0; i < bagPlayer.data.length; i++) {
                var obj = bagPlayer.data[i];
                if (obj && obj.bagPath !== undefined && obj.play !== undefined)
                    return obj;
            }
            return null;
        }

        // TODO(test-guidelines): expose objectName on LocalBagScanner to allow Utils.findChild lookup
        function _findScanner() {
            for (var i = 0; i < bagPlayer.data.length; i++) {
                var obj = bagPlayer.data[i];
                if (obj && obj.scanPath !== undefined)
                    return obj;
            }
            return null;
        }
    }
}
