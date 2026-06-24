import QtQuick

QtObject {
    id: root

    property string scanPath: ""

    signal serviceResponse(string serviceName, bool success, string message)

    // Mock data
    property var _mockBags: []
    property var _mockBagDetails: ({})
    property var _mockRecorderInfo: ({ hostname: "test-host", recordedBy: "test-user", configPath: "" })
    property var _mockCompletions: []
    property int _deleteBagCount: 0
    property string _lastDeletedBag: ""

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
        serviceResponse("delete_bag", true, "Deleted " + bagPath);
        if (callback) callback(true, "Deleted " + bagPath);
    }

    function fetchRecorderInfo(callback) {
        if (callback) callback(_mockRecorderInfo);
    }

    function completePath(partial) {
        return _mockCompletions;
    }
}
