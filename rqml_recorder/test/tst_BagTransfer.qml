import QtQuick
import QtQuick.Controls
import QtTest
import "../qml/elements" as Elements
import RqmlRecorder

Item {
    id: windowRoot
    width: 800
    height: 600

    // Standalone BagTransfer mock for testing transfer lifecycle
    BagTransfer {
        id: transfer
    }

    // Mock interface for BagBrowser transfer dialog integration
    QtObject {
        id: mockInterface

        property bool supportsTransfer: true
        property bool supportsDelete: true
        property bool supportsPlayback: false

        property var _mockBags: []
        property var _recorderInfo: ({ hostname: "robot-pc", recordedBy: "user", configPath: "" })

        function listBags(path, callback) {
            if (callback) callback(_mockBags);
        }
        function getBagDetails(bagPath, callback) {
            if (callback) callback({}, []);
        }
        function deleteBag(bagPath, callback) {
            if (callback) callback(true, "Deleted");
        }
        function fetchRecorderInfo(callback) {
            if (callback) callback(_recorderInfo);
        }
    }

    // BagBrowser to test transfer dialog integration
    Elements.BagBrowser {
        id: bagBrowser
        anchors.fill: parent
        recorderInterface: mockInterface
    }

    Utils {
        id: helpers
    }

    TestCase {
        name: "BagTransferTest"
        when: windowShown

        function init() {
            transfer.running = false;
            transfer.progress = 0.0;
            transfer.statusText = "";
            transfer._startCount = 0;
            transfer._cancelCount = 0;
        }

        // ---- Test 1: Initial state ----
        function test_01_initial_state() {
            compare(transfer.running, false, "Should not be running initially");
            compare(transfer.progress, 0.0, "Progress should be 0");
            compare(transfer.statusText, "", "Status should be empty");
        }

        // ---- Test 2: Start updates state ----
        function test_02_start_updates_state() {
            transfer.start("robot-pc", "/remote/bags/test_bag", "~/bags/");

            tryCompare(transfer, "running", true, 1000, "Should be running after start");
            compare(transfer.progress, 0.0, "Progress should be 0 at start");
            compare(transfer.statusText, "Starting transfer...",
                "Status should show starting message");
            compare(transfer._startCount, 1, "Start should be called once");
            compare(transfer._lastHostname, "robot-pc", "Hostname should be recorded");
            compare(transfer._lastRemotePath, "/remote/bags/test_bag",
                "Remote path should be recorded");
            compare(transfer._lastLocalDir, "~/bags/", "Local dir should be recorded");
        }

        // ---- Test 3: Progress updates ----
        function test_03_progress_updates() {
            transfer.start("robot-pc", "/remote/bags/test_bag", "~/bags/");
            tryCompare(transfer, "running", true, 1000, "Should be running after start");

            // Simulate incremental progress with size, speed, ETA
            transfer._simulateProgress(25.0, 25000, 100000, 5000, 15);
            compare(transfer.progress, 25.0, "Progress should be 25%");
            verify(transfer.statusText.length > 0, "Status text should be updated");

            transfer._simulateProgress(50.0, 50000, 100000, 8000, 6);
            compare(transfer.progress, 50.0, "Progress should be 50%");

            transfer._simulateProgress(75.0, 75000, 100000, 10000, 2);
            compare(transfer.progress, 75.0, "Progress should be 75%");

            // Still running
            compare(transfer.running, true, "Should still be running during progress");
        }

        // ---- Test 4: Successful completion ----
        function test_04_successful_completion() {
            transfer.start("robot-pc", "/remote/bags/test_bag", "~/bags/");
            tryCompare(transfer, "running", true, 1000, "Should be running after start");

            var finishReceived = false;
            var finishSuccess = false;
            var finishLocalPath = "";
            transfer.finished.connect(function(success, message, localPath) {
                finishReceived = true;
                finishSuccess = success;
                finishLocalPath = localPath;
            });

            transfer._simulateFinishSuccess("/home/user/bags/test_bag");

            tryCompare(transfer, "running", false, 1000, "Should not be running after completion");
            compare(transfer.progress, 100.0, "Progress should be 100%");
            verify(transfer.statusText.indexOf("Transfer complete") >= 0,
                "Status should show completion");
            verify(finishReceived, "Finished signal should be emitted");
            verify(finishSuccess, "Should be successful");
            compare(finishLocalPath, "/home/user/bags/test_bag",
                "Local path should be returned");
        }

        // ---- Test 5: Failed transfer ----
        function test_05_failed_transfer() {
            transfer.start("robot-pc", "/remote/bags/test_bag", "~/bags/");
            tryCompare(transfer, "running", true, 1000, "Should be running after start");

            var finishReceived = false;
            var finishSuccess = true;
            var finishMessage = "";
            transfer.finished.connect(function(success, message, localPath) {
                finishReceived = true;
                finishSuccess = success;
                finishMessage = message;
            });

            transfer._simulateFinishFailure("Transfer failed (exit code 12)");

            tryCompare(transfer, "running", false, 1000, "Should not be running after failure");
            compare(transfer.progress, 0.0, "Progress should reset to 0 on failure");
            verify(transfer.statusText.indexOf("failed") >= 0 ||
                   transfer.statusText.indexOf("Transfer failed") >= 0,
                "Status should show failure message");
            verify(finishReceived, "Finished signal should be emitted");
            compare(finishSuccess, false, "Should not be successful");
            verify(finishMessage.length > 0, "Error message should be provided");
        }

        // ---- Test 6: Cancel ----
        function test_06_cancel() {
            transfer.start("robot-pc", "/remote/bags/test_bag", "~/bags/");
            tryCompare(transfer, "running", true, 1000, "Should be running after start");
            compare(transfer.running, true, "Should be running");

            transfer.cancel();
            tryCompare(transfer, "running", false, 1000, "Should not be running after cancel");
            compare(transfer.statusText, "Cancelled",
                "Status should show cancelled");
            compare(transfer._cancelCount, 1, "Cancel should be called once");
        }

        // ---- Test 7: Transfer dialog flow in BagBrowser ----
        function test_07_transfer_dialog_flow() {
            mockInterface._mockBags = [
                { name: "remote_bag", path: "/remote/bags/remote_bag", sizeBytes: 5000,
                  startTime: "2025-01-01", durationSecs: 60, topicCount: 3,
                  messageCount: 100, recordedBy: "robot", storageId: "sqlite3" }
            ];

            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 1, 1000, "Should have 1 bag");

            // Verify the BagBrowser has a BagTransfer component.
            // TODO(test-guidelines): expose objectName on BagBrowser's BagTransfer
            // to allow Utils.findChild lookup instead of duck-typing by property presence.
            var browserTransfer = null;
            for (var i = 0; i < bagBrowser.data.length; i++) {
                var obj = bagBrowser.data[i];
                if (obj && obj.running !== undefined && obj.start !== undefined &&
                    obj.cancel !== undefined && obj.progress !== undefined) {
                    browserTransfer = obj;
                    break;
                }
            }
            verify(browserTransfer !== null, "BagBrowser should have BagTransfer");
            compare(browserTransfer.running, false, "Transfer should not be running initially");

            // Simulate starting a transfer (as the dialog would)
            browserTransfer.start("robot-pc", "/remote/bags/remote_bag", "~/bags/");
            tryCompare(browserTransfer, "running", true, 1000, "Transfer should be running");

            // Simulate progress with size/speed/eta
            browserTransfer._simulateProgress(50.0, 50000000, 100000000, 10000000, 5);
            compare(browserTransfer.progress, 50.0, "Progress should update");

            // Complete
            browserTransfer._simulateFinishSuccess("/home/user/bags/remote_bag");
            tryCompare(browserTransfer, "running", false, 1000, "Transfer should be complete");
            compare(browserTransfer.progress, 100.0, "Progress should be 100%");
        }

        // ---- Test 7b: Failure shows copyable command + output ----
        function test_07b_failure_shows_error_dialog() {
            mockInterface._mockBags = [
                { name: "remote_bag", path: "/remote/bags/remote_bag", sizeBytes: 5000,
                  startTime: "2025-01-01", durationSecs: 60, topicCount: 3,
                  messageCount: 100, recordedBy: "robot", storageId: "sqlite3" }
            ];

            bagBrowser.refresh();
            tryCompare(bagBrowser.bagModel, "count", 1, 1000, "Should have 1 bag");

            var browserTransfer = null;
            for (var i = 0; i < bagBrowser.data.length; i++) {
                var obj = bagBrowser.data[i];
                if (obj && obj.running !== undefined && obj.start !== undefined &&
                    obj.failureCommand !== undefined) {
                    browserTransfer = obj;
                    break;
                }
            }
            verify(browserTransfer !== null, "BagBrowser should have BagTransfer");

            var errorDialog = helpers.findChild(bagBrowser, "bagBrowserTransferErrorDialog");
            verify(errorDialog !== null, "Error dialog should exist");
            verify(!errorDialog.visible, "Error dialog should be hidden initially");

            browserTransfer.start("robot-pc", "/remote/bags/remote_bag", "~/bags/");
            tryCompare(browserTransfer, "running", true, 1000, "Transfer should be running");

            var cmd = "rsync -a -z --info=progress2 --no-inc-recursive " +
                      "robot-pc:/remote/bags/remote_bag/ /home/user/bags/remote_bag/";
            browserTransfer._simulateFinishFailure(
                "Transfer failed (exit code 9)", cmd,
                "ssh: Host key verification failed.\nrsync error: unexplained error");

            tryCompare(errorDialog, "visible", true, 1000,
                "Error dialog should open on failure");
            compare(errorDialog.command, cmd, "Dialog should carry the rsync command");
            verify(errorDialog.output.indexOf("Host key verification") >= 0,
                "Dialog should carry the captured output");

            var cmdField = helpers.findChild(bagBrowser, "bagBrowserTransferErrorCommandField");
            verify(cmdField !== null, "Command field should exist");
            compare(cmdField.text, cmd, "Command field should show the command");
            verify(cmdField.readOnly, "Command field should be read-only");

            var copyButton = helpers.findChild(bagBrowser, "bagBrowserTransferErrorCopyButton");
            verify(copyButton !== null, "Copy button should exist");

            var closeButton = helpers.findChild(bagBrowser, "bagBrowserTransferErrorCloseButton");
            verify(closeButton !== null, "Close button should exist");
            closeButton.clicked();
            tryCompare(errorDialog, "visible", false, 1000,
                "Error dialog should close on Close");
        }

        // ---- Test 8: Source and dest paths ----
        function test_08_source_dest_paths() {
            transfer.start("robot-pc", "/remote/bags/test_bag", "~/bags/");
            tryCompare(transfer, "running", true, 1000, "Should be running after start");

            compare(transfer.sourcePath, "robot-pc:/remote/bags/test_bag",
                "Source path should include hostname");
            verify(transfer.destPath.length > 0,
                "Dest path should be set");
            verify(transfer.destPath.indexOf("test_bag") >= 0,
                "Dest path should include bag name");
        }

        // ---- Test 9: Speed and ETA ----
        function test_09_speed_and_eta() {
            transfer.start("robot-pc", "/remote/bags/test_bag", "~/bags/");
            tryCompare(transfer, "running", true, 1000, "Should be running after start");

            transfer._simulateProgress(50.0, 50000000, 100000000, 10000000, 5);

            compare(transfer.speed, 10000000, "Speed should be 10 MB/s");
            compare(transfer.etaSeconds, 5, "ETA should be 5 seconds");
            compare(transfer.bytesTransferred, 50000000,
                "Bytes transferred should be 50 MB");
            compare(transfer.bytesTotal, 100000000,
                "Bytes total should be 100 MB");

            // Status text should contain size info
            verify(transfer.statusText.indexOf("47.7 MB") >= 0 ||
                   transfer.statusText.indexOf("50") >= 0,
                "Status should show transferred amount");
            verify(transfer.statusText.indexOf("remaining") >= 0,
                "Status should show ETA");
        }

        // ---- Test 10: Progress with realistic increments ----
        function test_10_incremental_progress() {
            transfer.start("robot-pc", "/remote/bags/test_bag", "~/bags/");
            tryCompare(transfer, "running", true, 1000, "Should be running after start");

            // 10%
            transfer._simulateProgress(10.0, 10000000, 100000000, 5000000, 18);
            compare(transfer.progress, 10.0);

            // 50%
            transfer._simulateProgress(50.0, 50000000, 100000000, 8000000, 6);
            compare(transfer.progress, 50.0);
            compare(transfer.etaSeconds, 6);

            // 99%
            transfer._simulateProgress(99.0, 99000000, 100000000, 10000000, 0);
            compare(transfer.progress, 99.0);

            // Done
            transfer._simulateFinishSuccess("~/bags/test_bag");
            compare(transfer.progress, 100.0);
            compare(transfer.etaSeconds, 0);
        }
    }
}
