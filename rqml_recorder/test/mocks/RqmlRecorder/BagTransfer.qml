import QtQuick

QtObject {
    id: root

    property bool running: false
    property double progress: 0.0
    property string statusText: ""
    property var bytesTransferred: 0
    property var bytesTotal: 0
    property double speed: 0.0
    property int etaSeconds: -1
    property string sourcePath: ""
    property string destPath: ""

    signal finished(bool success, string message, string localPath)

    // Mock tracking
    property int _startCount: 0
    property int _cancelCount: 0
    property string _lastHostname: ""
    property string _lastRemotePath: ""
    property string _lastLocalDir: ""

    function start(hostname, remotePath, localDir) {
        _startCount++;
        _lastHostname = hostname;
        _lastRemotePath = remotePath;
        _lastLocalDir = localDir;
        running = true;
        progress = 0.0;
        speed = 0.0;
        etaSeconds = -1;
        sourcePath = hostname + ":" + remotePath;
        destPath = localDir + "/" + remotePath.split("/").pop();
        statusText = "Starting transfer...";
    }

    function cancel() {
        _cancelCount++;
        statusText = "Cancelled";
        running = false;
    }

    // Test helpers to simulate transfer progress
    function _simulateProgress(pct, transferred, total, spd, eta) {
        progress = pct;
        bytesTransferred = transferred;
        bytesTotal = total;
        speed = spd || 0;
        etaSeconds = eta || -1;
        statusText = _formatSize(transferred) + " of " + _formatSize(total) +
            "  (" + Math.round(pct) + "%)";
        if (spd > 0)
            statusText += "  " + _formatSize(spd) + "/s";
        if (eta > 0)
            statusText += "  ~" + eta + "s remaining";
    }

    function _simulateFinishSuccess(localPath) {
        progress = 100.0;
        etaSeconds = 0;
        statusText = "Transfer complete — " + _formatSize(bytesTransferred);
        running = false;
        finished(true, "Transfer complete", localPath);
    }

    function _simulateFinishFailure(message) {
        progress = 0.0;
        speed = 0.0;
        etaSeconds = -1;
        statusText = message;
        running = false;
        finished(false, message, "");
    }

    function _formatSize(bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB";
        return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB";
    }
}
