import QtQuick
import QtQuick.Controls
import QtTest
import "../qml/elements" as Elements
import RQml.Recorder

Item {
    id: root

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 600
    width: 800

    // Mock interface providing bag data
    QtObject {
        id: mockInterface

        property int _deleteBagCount: 0
        property string _lastDeletedBag: ""
        property string _lastListPath: ""
        property int _listBagsCount: 0
        property var _mockBagDetails: ({})
        property var _mockBags: []
        property var _recorderInfo: ({
                "hostname": "robot-pc",
                "recordedBy": "user",
                "configPath": ""
            })
        property bool supportsDelete: true
        property bool supportsPlayback: true
        property bool supportsTransfer: true

        function deleteBag(bagPath, callback) {
            _deleteBagCount++;
            _lastDeletedBag = bagPath;
            _mockBags = _mockBags.filter(function (b) {
                return b.path !== bagPath;
            });
            if (callback)
                callback(true, "Deleted");
        }
        function fetchRecorderInfo(callback) {
            if (callback)
                callback(_recorderInfo);
        }
        function getBagDetails(bagPath, callback) {
            if (callback) {
                var details = _mockBagDetails[bagPath] || {
                    "info": {},
                    "topics": []
                };
                callback(details.info, details.topics);
            }
        }
        function listBags(path, callback) {
            _listBagsCount++;
            _lastListPath = path;
            if (callback)
                callback(_mockBags);
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
    SignalSpy {
        id: playSpy

        signalName: "playRequested"
        target: bagBrowser
    }
    TestCase {
        id: testCase

        function bag(name, path, sizeBytes, startTime, recordedBy) {
            return {
                "name": name,
                "path": path,
                "sizeBytes": sizeBytes,
                "startTime": startTime,
                "durationSecs": 10,
                "topicCount": 1,
                "messageCount": 10,
                "recordedBy": recordedBy || "user",
                "storageId": "sqlite3"
            };
        }
        function bagNameAt(index) {
            var label = find("bagBrowserBagNameLabel_" + index);
            return label ? label.text : "";
        }
        function clickRefresh() {
            var refreshButton = find("bagBrowserRefreshButton");
            verify(refreshButton !== null, "Refresh button should exist");
            mouseClick(refreshButton);
        }
        function clickRow(index) {
            var row = null;
            tryVerify(function () {
                row = find("bagBrowserBagRow_" + index);
                return row !== null;
            }, 1000, "Bag row " + index + " should exist");
            mouseClick(row, 20, row.height / 2);
        }
        function init() {
            mockInterface._mockBags = [];
            mockInterface._mockBagDetails = {};
            mockInterface._deleteBagCount = 0;
            mockInterface._lastDeletedBag = "";
            mockInterface._listBagsCount = 0;
            mockInterface._lastListPath = "";
            mockInterface.supportsTransfer = true;
            mockInterface.supportsDelete = true;
            mockInterface.supportsPlayback = true;
            find("bagBrowserDeleteConfirmDialog").close();
            bagBrowser.sortColumn = "startTime";
            bagBrowser.sortAscending = false;
            bagBrowser.homePath = "";
            bagBrowser.recentPaths = [];
            bagBrowser.setPath("");
            bagBrowser.bagModel.clear();
            bagBrowser.selectedIndex = -1;
            bagBrowser.detailModel.clear();
            playSpy.clear();
            tryVerify(function () {
                return !find("bagBrowserDeleteConfirmDialog").visible;
            }, 1000);
        }
        function scanPath(path) {
            var pathField = find("bagBrowserPathField");
            pathField.text = path;
            mouseClick(find("bagBrowserScanButton"));
        }
        function test_action_buttons_follow_capabilities() {
            mockInterface._mockBags = [bag("bag", "/bags/bag", 100, "2025-01-01")];
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 1, 1000);
            var playButton = null;
            tryVerify(function () {
                playButton = find("bagBrowserPlayButton_0");
                return playButton !== null;
            }, 1000);
            var transferButton = find("bagBrowserTransferButton_0");
            var deleteButton = find("bagBrowserDeleteButton_0");
            verify(playButton.visible, "Play button visible when playback is supported");
            verify(transferButton.visible, "Transfer button visible when transfer is supported");
            verify(deleteButton.visible, "Delete button visible when delete is supported");
            mockInterface.supportsTransfer = false;
            tryCompare(transferButton, "visible", false, 1000, "Transfer button should hide when transfer is unsupported");
            verify(playButton.visible, "Play button should stay visible");
            verify(deleteButton.visible, "Delete button should stay visible");
            mockInterface.supportsPlayback = false;
            mockInterface.supportsDelete = false;
            tryCompare(playButton, "visible", false, 1000, "Play button should hide when playback is unsupported");
            tryCompare(deleteButton, "visible", false, 1000, "Delete button should hide when delete is unsupported");
            mockInterface.supportsTransfer = true;
            tryCompare(transferButton, "visible", true, 1000, "Transfer button should reappear when re-enabled");
        }
        function test_bag_list_rendering() {
            mockInterface._mockBags = [bag("bag_001", "/bags/bag_001", 1024, "2025-01-01", "alice"), bag("bag_002", "/bags/bag_002", 2048, "2025-01-02", "bob")];
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 2, 1000, "Should have 2 bags in the list");
            compare(bagBrowser.bagModel.count, 2, "Should have 2 bags in model");
            compare(find("bagBrowserBagCountLabel").text, "2 bags");
            compare(find("bagBrowserEmptyStateLabel").visible, false, "Empty state hidden when bags exist");
            // Default sort: startTime descending
            tryVerify(function () {
                return bagNameAt(0) === "bag_002" && bagNameAt(1) === "bag_001";
            }, 1000, "Rows should show bag names sorted by date descending");
        }
        function test_click_row_shows_detail_panel() {
            mockInterface._mockBags = [bag("test_bag", "/bags/test_bag", 1024, "2025-01-01")];
            mockInterface._mockBagDetails["/bags/test_bag"] = {
                "info": {},
                "topics": [
                    {
                        "name": "/camera",
                        "type": "sensor_msgs/msg/Image",
                        "messageCount": 60,
                        "serializationFormat": "cdr"
                    },
                    {
                        "name": "/imu",
                        "type": "sensor_msgs/msg/Imu",
                        "messageCount": 40,
                        "serializationFormat": "cdr"
                    }
                ]
            };
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 1, 1000, "Should have 1 bag in the list");
            compare(bagBrowser.selectedIndex, -1, "No selection initially");
            compare(find("bagBrowserDetailPanel").visible, false, "Detail panel hidden without selection");
            clickRow(0);
            compare(bagBrowser.selectedIndex, 0, "Clicking a row should select it");
            tryCompare(find("bagBrowserDetailPanel"), "visible", true, 1000, "Detail panel should slide in");
            compare(find("bagBrowserDetailTitleLabel").text, "test_bag");
            var detailList = find("bagBrowserDetailListView");
            tryCompare(detailList, "count", 2, 1000, "Should have 2 topic details");
            compare(bagBrowser.detailModel.get(0).name, "/camera");
            compare(bagBrowser.detailModel.get(1).name, "/imu");
            tryVerify(function () {
                var first = find("bagBrowserDetailTopicName_0");
                var second = find("bagBrowserDetailTopicName_1");
                return first && second && first.text === "/camera" && second.text === "/imu";
            }, 1000, "Detail rows should show topic names");
            compare(find("bagBrowserDetailLoadingLabel").visible, false, "Loading label hidden once details arrived");
        }
        function test_click_selected_row_deselects() {
            mockInterface._mockBags = [bag("bag", "/bags/bag", 100, "2025-01-01")];
            mockInterface._mockBagDetails["/bags/bag"] = {
                "info": {},
                "topics": [
                    {
                        "name": "/a",
                        "type": "std_msgs/msg/String",
                        "messageCount": 1,
                        "serializationFormat": "cdr"
                    }
                ]
            };
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 1, 1000, "Should have 1 bag in the list");
            clickRow(0);
            tryCompare(bagBrowser, "selectedIndex", 0, 1000);
            tryCompare(bagBrowser.detailModel, "count", 1, 1000);
            clickRow(0);
            compare(bagBrowser.selectedIndex, -1, "Should be deselected");
            compare(bagBrowser.detailModel.count, 0, "Detail model should be cleared");
            tryCompare(find("bagBrowserDetailPanel"), "visible", false, 2000, "Detail panel should slide out");
        }
        function test_delete_bag_removes_entry() {
            mockInterface._mockBags = [bag("delete_me", "/bags/delete_me", 100, "2025-01-01"), bag("keep_me", "/bags/keep_me", 100, "2025-01-02")];
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 2, 1000, "Should have 2 bags in the list");
            var deleteButton = null;
            tryVerify(function () {
                deleteButton = find("bagBrowserDeleteButton_1");
                return deleteButton !== null;
            }, 1000);
            compare(bagNameAt(1), "delete_me");
            mouseClick(deleteButton);
            var dialog = find("bagBrowserDeleteConfirmDialog");
            tryCompare(dialog, "visible", true, 1000, "Delete confirmation should open");
            compare(dialog.bagName, "delete_me");
            compare(dialog.bagPath, "/bags/delete_me");
            compare(mockInterface._deleteBagCount, 0, "Nothing deleted before confirmation");
            var listCountBefore = mockInterface._listBagsCount;
            mouseClick(find("bagBrowserDeleteDialogConfirmButton"));
            compare(mockInterface._deleteBagCount, 1, "Delete should be called");
            compare(mockInterface._lastDeletedBag, "/bags/delete_me", "Should delete the correct bag");
            tryCompare(dialog, "visible", false, 1000, "Dialog should close after confirming");
            verify(mockInterface._listBagsCount > listCountBefore, "Browser should refresh after a successful delete");
            tryCompare(find("bagBrowserBagListView"), "count", 1, 1000, "Deleted bag should disappear");
            compare(bagBrowser.bagModel.get(0).name, "keep_me");
        }
        function test_delete_cancel_keeps_bag() {
            mockInterface._mockBags = [bag("keep_me", "/bags/keep_me", 100, "2025-01-01")];
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 1, 1000);
            var deleteButton = null;
            tryVerify(function () {
                deleteButton = find("bagBrowserDeleteButton_0");
                return deleteButton !== null;
            }, 1000);
            mouseClick(deleteButton);
            var dialog = find("bagBrowserDeleteConfirmDialog");
            tryCompare(dialog, "visible", true, 1000);
            mouseClick(find("bagBrowserDeleteDialogCancelButton"));
            tryCompare(dialog, "visible", false, 1000, "Dialog should close on cancel");
            compare(mockInterface._deleteBagCount, 0, "Cancel must not delete");
            compare(find("bagBrowserBagListView").count, 1);
        }
        function test_empty_state() {
            clickRefresh();
            tryCompare(bagBrowser.bagModel, "count", 0, 1000, "Model should be empty");
            compare(find("bagBrowserBagListView").count, 0);
            verify(find("bagBrowserEmptyStateLabel").visible, "Empty state label should be visible");
            compare(find("bagBrowserBagCountLabel").text, "0 bags");
        }
        function test_home_button_navigates_to_home_path() {
            var homeButton = find("bagBrowserHomeButton");
            compare(homeButton.enabled, false, "Home button disabled without a home path");
            bagBrowser.homePath = "~/default_bags/";
            compare(bagBrowser.homePath, "~/default_bags/", "homePath should be settable");
            tryCompare(homeButton, "enabled", true, 1000, "Home button enabled once a home path is set");
            mouseClick(homeButton);
            compare(bagBrowser.currentPath, "~/default_bags/", "Home should navigate to the home path");
            compare(find("bagBrowserPathField").text, "~/default_bags/");
            compare(mockInterface._lastListPath, "~/default_bags/", "Home should list bags in the home path");
        }
        function test_play_button_requests_playback() {
            mockInterface._mockBags = [bag("play_me", "/bags/play_me", 100, "2025-01-01")];
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 1, 1000, "Should have 1 bag in the list");
            var playButton = null;
            tryVerify(function () {
                playButton = find("bagBrowserPlayButton_0");
                return playButton !== null;
            }, 1000);
            mouseClick(playButton);
            compare(playSpy.count, 1, "playRequested signal should be emitted");
            compare(playSpy.signalArguments[0][0], "/bags/play_me");
            compare(playSpy.signalArguments[0][1], "play_me");
        }
        function test_recent_paths_are_capped() {
            for (var i = 0; i < 15; i++)
                scanPath("/path/" + i + "/");
            compare(bagBrowser.recentPaths.length, 10, "Should cap at 10 recent paths");
            compare(bagBrowser.recentPaths[0], "/path/14/", "Most recent should be first");
        }
        function test_recent_paths_are_tracked() {
            var recentCombo = find("bagBrowserRecentCombo");
            compare(recentCombo.visible, false, "Recent combo hidden without recent paths");
            scanPath("/path/a/");
            scanPath("/path/b/");
            scanPath("/path/c/");
            compare(bagBrowser.recentPaths.length, 3, "Should have 3 recent paths");
            compare(bagBrowser.recentPaths[0], "/path/c/", "Most recent should be first");
            compare(bagBrowser.recentPaths[2], "/path/a/", "Oldest should be last");
            tryCompare(recentCombo, "visible", true, 1000, "Recent combo shown once paths exist");
            // Scanning a known path moves it to the front
            scanPath("/path/a/");
            compare(bagBrowser.recentPaths.length, 3, "Should still have 3 (duplicate removed)");
            compare(bagBrowser.recentPaths[0], "/path/a/", "Duplicate should move to front");
        }
        function test_refresh_uses_current_path() {
            bagBrowser.setPath("/custom/bags/");
            mockInterface._mockBags = [bag("bag1", "/custom/bags/bag1", 100, "2025-01-01")];
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 1, 1000, "Should show bags from custom path");
            compare(mockInterface._lastListPath, "/custom/bags/", "listBags should be called with the current path");
        }
        function test_set_path_updates_path_field() {
            bagBrowser.setPath("/custom/path/");
            compare(bagBrowser.currentPath, "/custom/path/", "setPath should update currentPath");
            compare(find("bagBrowserPathField").text, "/custom/path/", "setPath should update the path field");
        }
        function test_sort_by_name_header() {
            mockInterface._mockBags = [bag("alpha_bag", "/bags/alpha", 100, "2025-01-01", "alice"), bag("beta_bag", "/bags/beta", 500, "2025-01-03", "bob"), bag("gamma_bag", "/bags/gamma", 200, "2025-01-02", "charlie")];
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 3, 1000, "Should have 3 bags in the list");

            // Default sort is startTime descending
            compare(bagBrowser.sortColumn, "startTime", "Default sort column should be startTime");
            compare(bagBrowser.sortAscending, false, "Default sort should be descending");
            verify(find("bagBrowserSortDate").text.indexOf("▼") >= 0, "Date header should show descending marker");
            tryVerify(function () {
                return bagNameAt(0) === "beta_bag";
            }, 1000, "Newest bag should be first");
            mouseClick(find("bagBrowserSortName"));
            compare(bagBrowser.sortColumn, "name");
            compare(bagBrowser.sortAscending, true, "Name should default to ascending");
            verify(find("bagBrowserSortName").text.indexOf("▲") >= 0, "Name header should show ascending marker");
            tryVerify(function () {
                return bagNameAt(0) === "alpha_bag" && bagNameAt(1) === "beta_bag" && bagNameAt(2) === "gamma_bag";
            }, 1000, "Rows should be sorted by name ascending");
            compare(bagBrowser.bagModel.get(0).name, "alpha_bag", "First bag should be alpha when sorted by name ascending");
            mouseClick(find("bagBrowserSortName"));
            compare(bagBrowser.sortAscending, false, "Should toggle to descending");
            tryVerify(function () {
                return bagNameAt(0) === "gamma_bag";
            }, 1000, "Rows should be sorted by name descending");
        }
        function test_sort_by_size_header() {
            mockInterface._mockBags = [bag("small", "/bags/small", 100, "2025-01-01"), bag("large", "/bags/large", 10000, "2025-01-01"), bag("medium", "/bags/medium", 5000, "2025-01-01")];
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 3, 1000, "Should have 3 bags in the list");
            mouseClick(find("bagBrowserSortSize"));
            compare(bagBrowser.sortColumn, "sizeBytes");
            // Numeric defaults to descending
            compare(bagBrowser.sortAscending, false);
            compare(bagBrowser.bagModel.get(0).name, "large", "Largest bag should be first in descending size sort");
            tryVerify(function () {
                return bagNameAt(0) === "large" && bagNameAt(1) === "medium" && bagNameAt(2) === "small";
            }, 1000, "Rows should be sorted by size descending");
        }
        function test_sort_persists_across_refresh() {
            mockInterface._mockBags = [bag("aaa", "/bags/aaa", 300, "2025-01-01", "a"), bag("bbb", "/bags/bbb", 100, "2025-01-02", "b")];
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 2, 1000, "Should have 2 bags in the list");
            mouseClick(find("bagBrowserSortName"));
            compare(bagBrowser.sortColumn, "name");
            compare(bagBrowser.sortAscending, true);
            clickRefresh();
            tryCompare(find("bagBrowserBagListView"), "count", 2, 1000, "Should still have 2 bags after refresh");

            // Sort settings should persist
            compare(bagBrowser.sortColumn, "name", "Sort column should persist");
            compare(bagBrowser.sortAscending, true, "Sort direction should persist");
            tryVerify(function () {
                return bagNameAt(0) === "aaa" && bagNameAt(1) === "bbb";
            }, 1000, "Refreshed rows should be sorted by name ascending");
        }

        name: "BagBrowserTest"
        when: windowShown
    }
}
