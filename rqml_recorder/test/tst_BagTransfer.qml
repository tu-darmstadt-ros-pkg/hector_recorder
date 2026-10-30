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

    // Mock interface for BagBrowser transfer integration
    QtObject {
        id: mockInterface

        property var _mockBags: []
        property var _recorderInfo: ({
                "hostname": "robot-pc",
                "recordedBy": "user",
                "configPath": ""
            })
        property bool supportsDelete: true
        property bool supportsPlayback: false
        property bool supportsTransfer: true

        function deleteBag(bagPath, callback) {
            if (callback)
                callback(true, "Deleted");
        }
        function fetchRecorderInfo(callback) {
            if (callback)
                callback(_recorderInfo);
        }
        function getBagDetails(bagPath, callback) {
            if (callback)
                callback({}, []);
        }
        function listBags(path, callback) {
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
        id: finishedSpy

        signalName: "finished"
    }
    SignalSpy {
        id: statusSpy

        signalName: "statusMessage"
        target: bagBrowser
    }
    TestCase {
        id: testCase

        property var transfer: null

        function init() {
            mockInterface._recorderInfo = {
                "hostname": "robot-pc",
                "recordedBy": "user",
                "configPath": ""
            };
            mockInterface._mockBags = [
                {
                    "name": "remote_bag",
                    "path": "/remote/bags/remote_bag",
                    "sizeBytes": 5000,
                    "startTime": "2025-01-01",
                    "durationSecs": 60,
                    "topicCount": 3,
                    "messageCount": 100,
                    "recordedBy": "robot",
                    "storageId": "sqlite3"
                }
            ];
            // Re-assign the interface so the browser re-fetches the recorder hostname
            bagBrowser.recorderInterface = null;
            bagBrowser.recorderInterface = mockInterface;
            transfer = find("bagBrowserBagTransfer");
            verify(transfer !== null, "BagBrowser should own a BagTransfer");
            transfer.running = false;
            transfer.progress = 0.0;
            transfer.statusText = "";
            transfer.bytesTransferred = 0;
            transfer.bytesTotal = 0;
            transfer.speed = 0.0;
            transfer.etaSeconds = -1;
            transfer.sourcePath = "";
            transfer.destPath = "";
            transfer.failureCommand = "";
            transfer.failureOutput = "";
            transfer._startCount = 0;
            transfer._cancelCount = 0;
            transfer._lastHostname = "";
            transfer._lastRemotePath = "";
            transfer._lastLocalDir = "";
            find("bagBrowserTransferBar")._transferJustFinished = false;
            find("bagBrowserTransferDialog").close();
            find("bagBrowserTransferErrorDialog").close();
            tryVerify(function () {
                return !find("bagBrowserTransferDialog").visible && !find("bagBrowserTransferErrorDialog").visible;
            }, 1000);
            finishedSpy.target = transfer;
            finishedSpy.clear();
            statusSpy.clear();
            mouseClick(find("bagBrowserRefreshButton"));
            tryCompare(find("bagBrowserBagListView"), "count", 1, 1000, "Should have 1 bag");
        }
        function openTransferDialog() {
            var transferButton = null;
            tryVerify(function () {
                transferButton = find("bagBrowserTransferButton_0");
                return transferButton !== null && transferButton.visible;
            }, 1000, "Transfer button should be visible");
            mouseClick(transferButton);
            var dialog = find("bagBrowserTransferDialog");
            tryCompare(dialog, "visible", true, 1000, "Transfer dialog should open");
            return dialog;
        }
        function startTransfer() {
            var dialog = openTransferDialog();
            mouseClick(find("bagBrowserTransferDialogConfirmButton"));
            tryCompare(transfer, "running", true, 1000, "Should be running after start");
            tryCompare(dialog, "visible", false, 1000, "Transfer dialog should close after confirming");
        }
        function test_cancel_button_stops_transfer() {
            startTransfer();
            var cancelButton = find("bagBrowserTransferCancelButton");
            tryCompare(cancelButton, "visible", true, 1000, "Cancel button visible while running");
            mouseClick(cancelButton);
            tryCompare(transfer, "running", false, 1000, "Should not be running after cancel");
            compare(transfer.statusText, "Cancelled", "Status should show cancelled");
            compare(transfer._cancelCount, 1, "Cancel should be called once");
            tryCompare(find("bagBrowserTransferBar"), "visible", false, 1000, "Transfer bar hides after cancel");
        }
        function test_dialog_cancel_does_not_start_transfer() {
            var dialog = openTransferDialog();
            mouseClick(find("bagBrowserTransferDialogCancelButton"));
            tryCompare(dialog, "visible", false, 1000, "Dialog should close on cancel");
            compare(transfer._startCount, 0, "Cancel must not start a transfer");
            compare(transfer.running, false);
        }
        function test_failed_transfer() {
            startTransfer();
            transfer._simulateFinishFailure("Transfer failed (exit code 12)");
            tryCompare(transfer, "running", false, 1000, "Should not be running after failure");
            compare(transfer.progress, 0.0, "Progress should reset to 0 on failure");
            verify(transfer.statusText.indexOf("Transfer failed") >= 0, "Status should show failure message");
            compare(finishedSpy.count, 1, "Finished signal should be emitted");
            compare(finishedSpy.signalArguments[0][0], false, "Should not be successful");
            verify(finishedSpy.signalArguments[0][1].length > 0, "Error message should be provided");
            var lastStatus = statusSpy.signalArguments[statusSpy.count - 1];
            compare(lastStatus[0], "Transfer failed: Transfer failed (exit code 12)");
            compare(lastStatus[1], true, "Failure should be reported as error");
            tryCompare(find("bagBrowserTransferBar"), "visible", false, 1000, "Transfer bar hides after failure");
        }
        function test_failure_shows_error_dialog() {
            var errorDialog = find("bagBrowserTransferErrorDialog");
            verify(errorDialog !== null, "Error dialog should exist");
            verify(!errorDialog.visible, "Error dialog should be hidden initially");
            startTransfer();
            var cmd = "rsync -a -z --info=progress2 --no-inc-recursive " + "robot-pc:/remote/bags/remote_bag/ /home/user/bags/remote_bag/";
            transfer._simulateFinishFailure("Transfer failed (exit code 9)", cmd, "ssh: Host key verification failed.\nrsync error: unexplained error");
            tryCompare(errorDialog, "visible", true, 1000, "Error dialog should open on failure");
            compare(errorDialog.command, cmd, "Dialog should carry the rsync command");
            verify(errorDialog.output.indexOf("Host key verification") >= 0, "Dialog should carry the captured output");
            var cmdField = find("bagBrowserTransferErrorCommandField");
            verify(cmdField !== null, "Command field should exist");
            compare(cmdField.text, cmd, "Command field should show the command");
            verify(cmdField.readOnly, "Command field should be read-only");
            var outputArea = find("bagBrowserTransferErrorOutput");
            verify(outputArea !== null, "Output area should exist");
            verify(outputArea.text.indexOf("Host key verification") >= 0, "Output area should show the captured output");
            var copyButton = find("bagBrowserTransferErrorCopyButton");
            verify(copyButton !== null, "Copy button should exist");
            var closeButton = find("bagBrowserTransferErrorCloseButton");
            verify(closeButton !== null, "Close button should exist");
            mouseClick(closeButton);
            tryCompare(errorDialog, "visible", false, 1000, "Error dialog should close on Close");
        }
        function test_incremental_progress() {
            startTransfer();
            transfer._simulateProgress(10.0, 10000000, 100000000, 5000000, 18);
            compare(transfer.progress, 10.0);
            transfer._simulateProgress(50.0, 50000000, 100000000, 8000000, 6);
            compare(transfer.progress, 50.0);
            compare(transfer.etaSeconds, 6);
            transfer._simulateProgress(99.0, 99000000, 100000000, 10000000, 0);
            compare(transfer.progress, 99.0);
            tryCompare(find("bagBrowserTransferPercentLabel"), "text", "99%", 1000);
            transfer._simulateFinishSuccess("~/bags/test_bag");
            compare(transfer.progress, 100.0);
            compare(transfer.etaSeconds, 0);
        }
        function test_initial_state() {
            compare(transfer.running, false, "Should not be running initially");
            compare(transfer.progress, 0.0, "Progress should be 0");
            compare(transfer.statusText, "", "Status should be empty");
            compare(find("bagBrowserTransferBar").visible, false, "Transfer bar hidden while idle");
        }
        function test_progress_updates() {
            startTransfer();
            transfer._simulateProgress(25.0, 25000, 100000, 5000, 15);
            compare(transfer.progress, 25.0, "Progress should be 25%");
            verify(transfer.statusText.length > 0, "Status text should be updated");
            tryCompare(find("bagBrowserTransferPercentLabel"), "text", "25%", 1000);
            compare(find("bagBrowserTransferStatusLabel").text, transfer.statusText, "Status label shows transfer status");
            transfer._simulateProgress(50.0, 50000, 100000, 8000, 6);
            compare(transfer.progress, 50.0, "Progress should be 50%");
            transfer._simulateProgress(75.0, 75000, 100000, 10000, 2);
            compare(transfer.progress, 75.0, "Progress should be 75%");
            tryCompare(find("bagBrowserTransferPercentLabel"), "text", "75%", 1000);
            compare(transfer.running, true, "Should still be running during progress");
            verify(find("bagBrowserTransferBar").visible, "Transfer bar visible during progress");
        }
        function test_speed_and_eta() {
            startTransfer();
            transfer._simulateProgress(50.0, 50000000, 100000000, 10000000, 5);
            compare(transfer.speed, 10000000, "Speed should be 10 MB/s");
            compare(transfer.etaSeconds, 5, "ETA should be 5 seconds");
            compare(transfer.bytesTransferred, 50000000, "Bytes transferred should be 50 MB");
            compare(transfer.bytesTotal, 100000000, "Bytes total should be 100 MB");
            var statusLabel = find("bagBrowserTransferStatusLabel");
            tryVerify(function () {
                return statusLabel.text.indexOf("47.7 MB") >= 0;
            }, 1000, "Status should show transferred amount");
            verify(statusLabel.text.indexOf("remaining") >= 0, "Status should show ETA");
        }
        function test_start_without_hostname_reports_error() {
            mockInterface._recorderInfo = {
                "hostname": "",
                "recordedBy": "user",
                "configPath": ""
            };
            bagBrowser.recorderInterface = null;
            bagBrowser.recorderInterface = mockInterface;
            var dialog = openTransferDialog();
            compare(find("bagBrowserTransferDialogHostLabel").text, "From: unknown");
            mouseClick(find("bagBrowserTransferDialogConfirmButton"));
            tryCompare(dialog, "visible", false, 1000, "Dialog should close");
            compare(transfer._startCount, 0, "Transfer must not start without hostname");
            compare(statusSpy.count, 1);
            compare(statusSpy.signalArguments[0][0], "Cannot transfer: recorder hostname unknown");
            compare(statusSpy.signalArguments[0][1], true);
        }
        function test_successful_completion() {
            startTransfer();
            transfer._simulateFinishSuccess("/home/user/bags/test_bag");
            tryCompare(transfer, "running", false, 1000, "Should not be running after completion");
            compare(transfer.progress, 100.0, "Progress should be 100%");
            verify(transfer.statusText.indexOf("Transfer complete") >= 0, "Status should show completion");
            compare(finishedSpy.count, 1, "Finished signal should be emitted");
            verify(finishedSpy.signalArguments[0][0], "Should be successful");
            compare(finishedSpy.signalArguments[0][2], "/home/user/bags/test_bag", "Local path should be returned");
            var lastStatus = statusSpy.signalArguments[statusSpy.count - 1];
            compare(lastStatus[0], "Transfer complete: /home/user/bags/test_bag");
            compare(lastStatus[1], false);
            verify(find("bagBrowserTransferBar").visible, "Transfer bar stays visible briefly after success");
            compare(find("bagBrowserTransferCancelButton").visible, false, "Cancel hidden once finished");
            compare(find("bagBrowserTransferErrorDialog").visible, false, "No error dialog on success");
        }
        function test_transfer_dialog_flow() {
            var dialog = openTransferDialog();
            compare(dialog.bagName, "remote_bag");
            compare(dialog.remotePath, "/remote/bags/remote_bag");
            compare(find("bagBrowserTransferDialogHostLabel").text, "From: robot-pc");
            compare(find("bagBrowserTransferLocalDirField").text, "~/bags/", "Local dir defaults to ~/bags/");
            compare(transfer.running, false, "Transfer should not be running before confirming");
            mouseClick(find("bagBrowserTransferDialogConfirmButton"));
            tryCompare(transfer, "running", true, 1000, "Should be running after start");
            tryCompare(dialog, "visible", false, 1000, "Dialog should close after confirming");
            compare(transfer.progress, 0.0, "Progress should be 0 at start");
            compare(transfer.statusText, "Starting transfer...", "Status should show starting message");
            compare(transfer._startCount, 1, "Start should be called once");
            compare(transfer._lastHostname, "robot-pc", "Hostname should be recorded");
            compare(transfer._lastRemotePath, "/remote/bags/remote_bag", "Remote path should be recorded");
            compare(transfer._lastLocalDir, "~/bags/", "Local dir should be recorded");
            compare(transfer.sourcePath, "robot-pc:/remote/bags/remote_bag", "Source path should include hostname");
            verify(transfer.destPath.length > 0, "Dest path should be set");
            verify(transfer.destPath.indexOf("remote_bag") >= 0, "Dest path should include bag name");
            tryCompare(find("bagBrowserTransferBar"), "visible", true, 1000, "Transfer bar visible while running");
            verify(find("bagBrowserTransferCancelButton").visible, "Cancel button visible while running");
            transfer._simulateProgress(50.0, 50000000, 100000000, 10000000, 5);
            compare(transfer.progress, 50.0, "Progress should update");
            tryCompare(find("bagBrowserTransferPercentLabel"), "text", "50%", 1000);
            transfer._simulateFinishSuccess("/home/user/bags/remote_bag");
            tryCompare(transfer, "running", false, 1000, "Transfer should be complete");
            compare(transfer.progress, 100.0, "Progress should be 100%");
        }

        name: "BagTransferTest"
        when: windowShown
    }
}
