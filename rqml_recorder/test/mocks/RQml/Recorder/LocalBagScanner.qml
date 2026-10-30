import QtQuick

QtObject {
    id: root

    property int _deleteBagCount: 0
    property string _lastDeletedBag: ""
    property var _mockBagDetails: ({})

    // Mock data
    property var _mockBags: []
    property var _mockCompletions: []
    property var _mockRecorderInfo: ({
            hostname: "test-host",
            recordedBy: "test-user",
            configPath: ""
        })
    property string scanPath: ""
    readonly property bool supportsDelete: true
    readonly property bool supportsPlayback: true
    readonly property bool supportsTransfer: false

    signal serviceResponse(string serviceName, bool success, string message)

    function completePath(partial) {
        return _mockCompletions;
    }
    function deleteBag(bagPath, callback) {
        _deleteBagCount++;
        _lastDeletedBag = bagPath;
        serviceResponse("delete_bag", true, "Deleted " + bagPath);
        if (callback)
            callback(true, "Deleted " + bagPath);
    }
    function fetchRecorderInfo(callback) {
        if (callback)
            callback(_mockRecorderInfo);
    }
    function getBagDetails(bagPath, callback) {
        if (callback) {
            var details = _mockBagDetails[bagPath] || {
                info: {},
                topics: []
            };
            callback(details.info, details.topics);
        }
    }
    function listBags(path, callback) {
        if (callback)
            callback(_mockBags);
    }
}
