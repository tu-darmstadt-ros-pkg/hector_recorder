import QtQuick

QtObject {
    id: root

    property int _cancelCount: 0
    property string _lastHostname: ""
    property string _lastLocalDir: ""
    property string _lastRemotePath: ""

    // Mock tracking
    property int _startCount: 0
    property var bytesTotal: 0
    property var bytesTransferred: 0
    property string destPath: ""
    property int etaSeconds: -1
    property string failureCommand: ""
    property string failureOutput: ""
    property double progress: 0.0
    property bool running: false
    property string sourcePath: ""
    property double speed: 0.0
    property string statusText: ""

    signal finished(bool success, string message, string localPath)

    function _formatSize(bytes) {
        if (bytes < 1024)
            return bytes + " B";
        if (bytes < 1024 * 1024)
            return (bytes / 1024).toFixed(1) + " KB";
        if (bytes < 1024 * 1024 * 1024)
            return (bytes / (1024 * 1024)).toFixed(1) + " MB";
        return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB";
    }
    function _simulateFinishFailure(message, command, output) {
        progress = 0.0;
        speed = 0.0;
        etaSeconds = -1;
        statusText = message;
        failureCommand = command || "";
        failureOutput = output || "";
        running = false;
        finished(false, message, "");
    }
    function _simulateFinishSuccess(localPath) {
        progress = 100.0;
        etaSeconds = 0;
        statusText = "Transfer complete — " + _formatSize(bytesTransferred);
        running = false;
        finished(true, "Transfer complete", localPath);
    }

    // Test helpers to simulate transfer progress
    function _simulateProgress(pct, transferred, total, spd, eta) {
        progress = pct;
        bytesTransferred = transferred;
        bytesTotal = total;
        speed = spd || 0;
        etaSeconds = eta || -1;
        statusText = _formatSize(transferred) + " of " + _formatSize(total) + "  (" + Math.round(pct) + "%)";
        if (spd > 0)
            statusText += "  " + _formatSize(spd) + "/s";
        if (eta > 0)
            statusText += "  ~" + eta + "s remaining";
    }
    function cancel() {
        _cancelCount++;
        statusText = "Cancelled";
        running = false;
    }
    function start(hostname, remotePath, localDir) {
        _startCount++;
        _lastHostname = hostname;
        _lastRemotePath = remotePath;
        _lastLocalDir = localDir;
        running = true;
        progress = 0.0;
        speed = 0.0;
        etaSeconds = -1;
        failureCommand = "";
        failureOutput = "";
        sourcePath = hostname + ":" + remotePath;
        destPath = localDir + "/" + remotePath.split("/").pop();
        statusText = "Starting transfer...";
    }
}
