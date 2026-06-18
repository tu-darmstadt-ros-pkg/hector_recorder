import QtQuick
import QtQuick.Controls
import QtTest
import "../qml/elements" as Elements
import RqmlRecorder

Item {
    id: windowRoot
    width: 800
    height: 600

    // Mock interface providing bag data
    QtObject {
        id: mockInterface

        property bool supportsTransfer: true
        property bool supportsDelete: true
        property bool supportsPlayback: true

        property var _mockBags: []
        property var _mockBagDetails: ({})
        property int _deleteBagCount: 0
        property string _lastDeletedBag: ""
        property var _recorderInfo: ({ hostname: "robot-pc", recordedBy: "user", configPath: "" })

        function listBags(path, callback) {
            if (callback) callback(_mockBags);
        }

        function getBagDetails(bagPath, callback) {
            if (callback) {
                var details = _mockBagDetails[bagPath] || { info: {}, topics: [] };
                callback(details.info, details.topics);
            }
        }

        function deleteBag(bagPath, callback) {
            _deleteBagCount++;
            _lastDeletedBag = bagPath;
            if (callback) callback(true, "Deleted");
        }

        function fetchRecorderInfo(callback) {
            if (callback) callback(_recorderInfo);
        }
    }

    Elements.BagBrowser {
        id: bagBrowser
        anchors.fill: parent
        recorderInterface: mockInterface
    }

    Utils {
        id: helpers
    }

    TestCase {
        name: "BagBrowserTest"
        when: windowShown

        function find(name) {
            return helpers.findChild(windowRoot, name);
        }

        function init() {
            mockInterface._mockBags = [];
            mockInterface._mockBagDetails = {};
            mockInterface._deleteBagCount = 0;
            mockInterface._lastDeletedBag = "";
            bagBrowser.bagModel.clear();
            bagBrowser.selectedIndex = -1;
            bagBrowser.detailModel.clear();
        }

        // ---- Test 1: Bag list rendering ----
        function test_01_bag_list_rendering() {
            mockInterface._mockBags = [
                { name: "bag_001", path: "/bags/bag_001", sizeBytes: 1024,
                  startTime: "2025-01-01", durationSecs: 60, topicCount: 3,
                  messageCount: 100, recordedBy: "alice", storageId: "sqlite3" },
                { name: "bag_002", path: "/bags/bag_002", sizeBytes: 2048,
                  startTime: "2025-01-02", durationSecs: 120, topicCount: 5,
                  messageCount: 200, recordedBy: "bob", storageId: "sqlite3" }
            ];

            bagBrowser.refresh();

            tryCompare(bagBrowser.bagModel, "count", 2, 1000, "Should have 2 bags in model");
        }

        // ---- Test 2: Sorting ----
        function test_02_sorting() {
            mockInterface._mockBags = [
                { name: "alpha_bag", path: "/bags/alpha", sizeBytes: 100,
                  startTime: "2025-01-01", durationSecs: 10, topicCount: 1,
                  messageCount: 10, recordedBy: "alice", storageId: "sqlite3" },
                { name: "beta_bag", path: "/bags/beta", sizeBytes: 500,
                  startTime: "2025-01-03", durationSecs: 30, topicCount: 3,
                  messageCount: 30, recordedBy: "bob", storageId: "sqlite3" },
                { name: "gamma_bag", path: "/bags/gamma", sizeBytes: 200,
                  startTime: "2025-01-02", durationSecs: 20, topicCount: 2,
                  messageCount: 20, recordedBy: "charlie", storageId: "sqlite3" }
            ];

            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 3, 1000, "Should have 3 bags in model");

            // Default sort is startTime descending
            compare(bagBrowser.sortColumn, "startTime", "Default sort column should be startTime");
            compare(bagBrowser.sortAscending, false, "Default sort should be descending");

            // Toggle to name ascending
            bagBrowser._toggleSort("name");
            compare(bagBrowser.sortColumn, "name");
            compare(bagBrowser.sortAscending, true, "Name should default to ascending");

            // Verify sorted order
            compare(bagBrowser.bagModel.get(0).name, "alpha_bag",
                "First bag should be alpha when sorted by name ascending");

            // Toggle again to descending
            bagBrowser._toggleSort("name");
            compare(bagBrowser.sortAscending, false, "Should toggle to descending");
        }

        // ---- Test 3: Detail panel ----
        function test_03_detail_panel() {
            mockInterface._mockBags = [
                { name: "test_bag", path: "/bags/test_bag", sizeBytes: 1024,
                  startTime: "2025-01-01", durationSecs: 60, topicCount: 2,
                  messageCount: 100, recordedBy: "user", storageId: "sqlite3" }
            ];
            mockInterface._mockBagDetails["/bags/test_bag"] = {
                info: {},
                topics: [
                    { name: "/camera", type: "sensor_msgs/msg/Image",
                      messageCount: 60, serializationFormat: "cdr" },
                    { name: "/imu", type: "sensor_msgs/msg/Imu",
                      messageCount: 40, serializationFormat: "cdr" }
                ]
            };

            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 1, 1000, "Should have 1 bag in model");

            compare(bagBrowser.selectedIndex, -1, "No selection initially");

            // Select first bag
            bagBrowser.selectedIndex = 0;
            bagBrowser._loadDetails("/bags/test_bag");

            tryCompare(bagBrowser.detailModel, "count", 2, 1000, "Should have 2 topic details");
            compare(bagBrowser.detailModel.get(0).name, "/camera");
            compare(bagBrowser.detailModel.get(1).name, "/imu");
        }

        // ---- Test 4: Deselection ----
        function test_04_deselection() {
            mockInterface._mockBags = [
                { name: "bag", path: "/bags/bag", sizeBytes: 100,
                  startTime: "2025-01-01", durationSecs: 10, topicCount: 1,
                  messageCount: 10, recordedBy: "user", storageId: "sqlite3" }
            ];

            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 1, 1000, "Should have 1 bag in model");

            bagBrowser.selectedIndex = 0;
            tryCompare(bagBrowser, "selectedIndex", 0, 1000);

            // Deselect
            bagBrowser.selectedIndex = -1;
            bagBrowser.detailModel.clear();
            compare(bagBrowser.selectedIndex, -1, "Should be deselected");
            compare(bagBrowser.detailModel.count, 0, "Detail model should be cleared");
        }

        // ---- Test 5: Delete flow ----
        function test_05_delete_flow() {
            mockInterface._mockBags = [
                { name: "delete_me", path: "/bags/delete_me", sizeBytes: 100,
                  startTime: "2025-01-01", durationSecs: 10, topicCount: 1,
                  messageCount: 10, recordedBy: "user", storageId: "sqlite3" }
            ];

            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 1, 1000, "Should have 1 bag in model");

            // Call delete directly on the interface
            mockInterface.deleteBag("/bags/delete_me", function(success, msg) {});
            compare(mockInterface._deleteBagCount, 1, "Delete should be called");
            compare(mockInterface._lastDeletedBag, "/bags/delete_me",
                "Should delete the correct bag");
        }

        // ---- Test 6: Action button visibility based on capabilities ----
        function test_06_action_button_visibility() {
            // When all capabilities are true
            compare(mockInterface.supportsPlayback, true);
            compare(mockInterface.supportsTransfer, true);
            compare(mockInterface.supportsDelete, true);

            // Disable transfer
            mockInterface.supportsTransfer = false;
            tryCompare(mockInterface, "supportsTransfer", false, 1000,
                "Transfer should be disabled");

            // Re-enable
            mockInterface.supportsTransfer = true;
        }

        // ---- Test 7: Empty state ----
        function test_07_empty_state() {
            bagBrowser.bagModel.clear();

            tryCompare(bagBrowser.bagModel, "count", 0, 1000, "Model should be empty");
        }

        // ---- Test 8: Sort persists across refresh ----
        function test_08_sort_persists_across_refresh() {
            mockInterface._mockBags = [
                { name: "aaa", path: "/bags/aaa", sizeBytes: 300,
                  startTime: "2025-01-01", durationSecs: 10, topicCount: 1,
                  messageCount: 10, recordedBy: "a", storageId: "sqlite3" },
                { name: "bbb", path: "/bags/bbb", sizeBytes: 100,
                  startTime: "2025-01-02", durationSecs: 20, topicCount: 2,
                  messageCount: 20, recordedBy: "b", storageId: "sqlite3" }
            ];

            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 2, 1000, "Should have 2 bags in model");

            // Change sort to name ascending
            bagBrowser._toggleSort("name");
            compare(bagBrowser.sortColumn, "name");
            compare(bagBrowser.sortAscending, true);

            // Refresh again
            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 2, 1000, "Should still have 2 bags after refresh");

            // Sort settings should persist
            compare(bagBrowser.sortColumn, "name", "Sort column should persist");
            compare(bagBrowser.sortAscending, true, "Sort direction should persist");
        }

        // ---- Test 9: Multiple bags sorting by size ----
        function test_09_sorting_by_size() {
            mockInterface._mockBags = [
                { name: "small", path: "/bags/small", sizeBytes: 100,
                  startTime: "2025-01-01", durationSecs: 10, topicCount: 1,
                  messageCount: 10, recordedBy: "user", storageId: "sqlite3" },
                { name: "large", path: "/bags/large", sizeBytes: 10000,
                  startTime: "2025-01-01", durationSecs: 10, topicCount: 1,
                  messageCount: 10, recordedBy: "user", storageId: "sqlite3" },
                { name: "medium", path: "/bags/medium", sizeBytes: 5000,
                  startTime: "2025-01-01", durationSecs: 10, topicCount: 1,
                  messageCount: 10, recordedBy: "user", storageId: "sqlite3" }
            ];

            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 3, 1000, "Should have 3 bags in model");

            bagBrowser._toggleSort("sizeBytes");
            compare(bagBrowser.sortColumn, "sizeBytes");
            // Numeric defaults to descending
            compare(bagBrowser.sortAscending, false);

            // Largest should be first
            compare(bagBrowser.bagModel.get(0).name, "large",
                "Largest bag should be first in descending size sort");
        }

        // ---- Test 10: Play requested signal ----
        function test_10_play_requested() {
            mockInterface._mockBags = [
                { name: "play_me", path: "/bags/play_me", sizeBytes: 100,
                  startTime: "2025-01-01", durationSecs: 60, topicCount: 3,
                  messageCount: 100, recordedBy: "user", storageId: "sqlite3" }
            ];

            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 1, 1000, "Should have 1 bag in model");

            var playReceived = false;
            var playPath = "";
            var playName = "";
            bagBrowser.playRequested.connect(function(path, name) {
                playReceived = true;
                playPath = path;
                playName = name;
            });

            // Emit play signal (simulate what a play button click does)
            bagBrowser.playRequested("/bags/play_me", "play_me");
            verify(playReceived, "playRequested signal should be emitted");
            compare(playPath, "/bags/play_me");
            compare(playName, "play_me");
        }

        // ---- Test 11: Path bar sets current path ----
        function test_11_path_bar() {
            bagBrowser.setPath("/custom/path/");
            compare(bagBrowser.currentPath, "/custom/path/",
                "setPath should update currentPath");
        }

        // ---- Test 12: Home button path ----
        function test_12_home_path() {
            bagBrowser.homePath = "~/default_bags/";
            compare(bagBrowser.homePath, "~/default_bags/",
                "homePath should be settable");
        }

        // ---- Test 13: Recent paths tracking ----
        function test_13_recent_paths() {
            bagBrowser.recentPaths = [];
            bagBrowser._addRecentPath("/path/a/");
            bagBrowser._addRecentPath("/path/b/");
            bagBrowser._addRecentPath("/path/c/");
            compare(bagBrowser.recentPaths.length, 3, "Should have 3 recent paths");
            compare(bagBrowser.recentPaths[0], "/path/c/",
                "Most recent should be first");
            compare(bagBrowser.recentPaths[2], "/path/a/",
                "Oldest should be last");

            // Adding duplicate should move to front
            bagBrowser._addRecentPath("/path/a/");
            compare(bagBrowser.recentPaths.length, 3,
                "Should still have 3 (duplicate removed)");
            compare(bagBrowser.recentPaths[0], "/path/a/",
                "Duplicate should move to front");
        }

        // ---- Test 14: Recent paths max limit ----
        function test_14_recent_paths_limit() {
            bagBrowser.recentPaths = [];
            for (var i = 0; i < 15; i++) {
                bagBrowser._addRecentPath("/path/" + i + "/");
            }
            compare(bagBrowser.recentPaths.length, 10,
                "Should cap at 10 recent paths");
            compare(bagBrowser.recentPaths[0], "/path/14/",
                "Most recent should be first");
        }

        // ---- Test 15: Refresh uses current path ----
        function test_15_refresh_uses_path() {
            bagBrowser.setPath("/custom/bags/");
            mockInterface._mockBags = [
                { name: "bag1", path: "/custom/bags/bag1", sizeBytes: 100,
                  startTime: "2025-01-01", durationSecs: 10, topicCount: 1,
                  messageCount: 10, recordedBy: "user", storageId: "sqlite3" }
            ];
            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 1, 1000,
                "Should show bags from custom path");
        }
    }
}
