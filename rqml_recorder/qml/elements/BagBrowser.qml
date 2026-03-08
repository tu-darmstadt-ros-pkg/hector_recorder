import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RqmlRecorder
import "../utils.js" as Utils

/**
 * Browser pane for recorded bag files.
 * Shows a table of bags on the left. Clicking a row slides in a
 * detail panel on the right showing per-topic information.
 */
Rectangle {
    id: root
    color: palette.alternateBase
    radius: 4

    //! The RecorderInterface to use for service calls
    property var recorderInterface: null

    //! Bag list model populated from ListBags service
    property ListModel bagModel: ListModel {}

    //! Currently selected bag index (-1 = none)
    property int selectedIndex: -1

    //! Per-topic details for the selected bag
    property ListModel detailModel: ListModel {}

    signal statusMessage(string msg, bool isError)

    //! Cached hostname from GetRecorderInfo service
    property string _cachedHostname: ""

    onRecorderInterfaceChanged: {
        _cachedHostname = "";
        if (recorderInterface && recorderInterface.supportsTransfer) {
            recorderInterface.fetchRecorderInfo(function(info) {
                root._cachedHostname = info.hostname;
            });
        }
    }

    //! Current sort column key
    property string sortColumn: "startTime"
    //! true = ascending, false = descending
    property bool sortAscending: false

    // ========================================================================
    // Public API
    // ========================================================================

    function refresh() {
        if (!recorderInterface) return;
        recorderInterface.listBags("", function(bags) {
            bagModel.clear();
            for (let i = 0; i < bags.length; i++) {
                bagModel.append(bags[i]);
            }
            _sortBagModel();
            selectedIndex = -1;
            detailModel.clear();
        });
    }

    // ========================================================================
    // Layout
    // ========================================================================

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Recorded Bags"
                font.bold: true
                font.pixelSize: 13
            }

            Item { Layout.fillWidth: true }

            Label {
                text: bagModel.count + " bag" + (bagModel.count !== 1 ? "s" : "")
                color: palette.mid
                font.pixelSize: 11
            }

            Button {
                text: "\u21BB Refresh"
                font.pixelSize: 11
                flat: true
                onClicked: root.refresh()
            }
        }

        // Main content: bag list + detail panel side by side
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Left side: bag list
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Column headers (clickable for sorting)
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    color: palette.button
                    radius: 2

                    component SortableHeader: Label {
                        property string sortKey: ""
                        property string label: ""
                        text: label + (sortKey && root.sortColumn === sortKey
                              ? (root.sortAscending ? " \u25B2" : " \u25BC") : "")
                        font.bold: true
                        font.pixelSize: 11
                        color: root.sortColumn === sortKey ? palette.highlight : palette.text

                        MouseArea {
                            anchors.fill: parent
                            enabled: sortKey !== ""
                            cursorShape: sortKey ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: _toggleSort(sortKey)
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4

                        SortableHeader { label: "Name";       sortKey: "name";       Layout.preferredWidth: 200; Layout.fillWidth: true }
                        SortableHeader { label: "Date";       sortKey: "startTime";  Layout.preferredWidth: 140 }
                        SortableHeader { label: "Duration";   sortKey: "durationSecs"; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                        SortableHeader { label: "Size";       sortKey: "sizeBytes";  Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                        Label          { text: "Topics";     font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
                        SortableHeader { label: "Recorded By"; sortKey: "recordedBy"; Layout.preferredWidth: 120 }
                        Label          { text: "Actions";    font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 100; horizontalAlignment: Text.AlignHCenter }
                    }
                }

                // Bag list
                ListView {
                    id: bagListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: bagModel
                    clip: true
                    spacing: 1

                    delegate: Rectangle {
                        width: bagListView.width
                        height: 36
                        color: index === root.selectedIndex ? palette.highlight :
                               (bagRowMouse.containsMouse ? palette.midlight : palette.base)
                        radius: 2

                        MouseArea {
                            id: bagRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (root.selectedIndex === index) {
                                    root.selectedIndex = -1;
                                    root.detailModel.clear();
                                } else {
                                    root.selectedIndex = index;
                                    _loadDetails(model.path);
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 4

                            Label {
                                text: model.name
                                elide: Text.ElideRight
                                font.pixelSize: 12
                                Layout.preferredWidth: 200
                                Layout.fillWidth: true
                            }

                            Label {
                                text: model.startTime
                                font.pixelSize: 11
                                opacity: 0.7
                                Layout.preferredWidth: 140
                            }

                            Label {
                                text: _formatDuration(model.durationSecs)
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 70
                            }

                            Label {
                                text: _formatBytes(model.sizeBytes)
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 70
                            }

                            Label {
                                text: model.topicCount
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 50
                            }

                            Label {
                                text: model.recordedBy
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                opacity: 0.7
                                Layout.preferredWidth: 120
                            }

                            // Action buttons
                            RowLayout {
                                Layout.preferredWidth: 100
                                spacing: 4

                                Button {
                                    visible: root.recorderInterface && root.recorderInterface.supportsTransfer
                                    text: "\uD83D\uDCE5"  // inbox tray (download)
                                    font.pixelSize: 16
                                    flat: true
                                    padding: 2
                                    implicitWidth: visible ? 36 : 0
                                    implicitHeight: 36
                                    ToolTip.text: "Transfer to local machine"
                                    ToolTip.visible: hovered
                                    onClicked: {
                                        _startTransfer(model.path, model.name);
                                    }
                                }

                                Button {
                                    visible: root.recorderInterface && root.recorderInterface.supportsDelete
                                    text: "\uD83D\uDDD1"  // wastebasket (delete)
                                    font.pixelSize: 16
                                    flat: true
                                    padding: 2
                                    implicitWidth: visible ? 36 : 0
                                    implicitHeight: 36
                                    ToolTip.text: "Delete bag"
                                    ToolTip.visible: hovered
                                    onClicked: {
                                        deleteConfirmDialog.bagPath = model.path;
                                        deleteConfirmDialog.bagName = model.name;
                                        deleteConfirmDialog.open();
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty state
                Label {
                    Layout.fillWidth: true
                    Layout.fillHeight: bagModel.count === 0
                    visible: bagModel.count === 0
                    text: "No bags found. Click Refresh to scan."
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: palette.mid
                    font.italic: true
                }
            }

            // Right side: detail panel (slides in when a bag is selected)
            Rectangle {
                id: detailPanel
                Layout.fillHeight: true
                Layout.preferredWidth: root.selectedIndex >= 0 ? 414 : 0
                color: Qt.darker(palette.base, 1.05)
                clip: true
                visible: Layout.preferredWidth > 0

                Behavior on Layout.preferredWidth {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                // Subtle left border
                Rectangle {
                    width: 1
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    color: palette.mid
                    opacity: 0.3
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    // Panel header with bag name and close button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Label {
                            text: root.selectedIndex >= 0 && root.selectedIndex < bagModel.count
                                  ? bagModel.get(root.selectedIndex).name : ""
                            font.bold: true
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "\u2715"
                            font.pixelSize: 12
                            flat: true
                            padding: 2
                            implicitWidth: 24
                            implicitHeight: 24
                            onClicked: {
                                root.selectedIndex = -1;
                                root.detailModel.clear();
                            }
                        }
                    }

                    // Bag summary
                    Label {
                        property var _bag: root.selectedIndex >= 0 && root.selectedIndex < bagModel.count
                                           ? bagModel.get(root.selectedIndex) : null
                        text: _bag ? "Duration: " + _formatDuration(_bag.durationSecs)
                              + "  |  Messages: " + _bag.messageCount : ""
                        font.pixelSize: 11
                        opacity: 0.7
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: palette.mid
                        opacity: 0.3
                    }

                    // Topic detail table header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Label { text: "Topic"; font.bold: true; font.pixelSize: 12; Layout.fillWidth: true }
                        Label { text: "Type"; font.bold: true; font.pixelSize: 12; Layout.preferredWidth: 120 }
                        Label { text: "Msgs"; font.bold: true; font.pixelSize: 12; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
                    }

                    // Topic list
                    ListView {
                        id: detailListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.detailModel
                        clip: true
                        spacing: 1

                        delegate: RowLayout {
                            width: detailListView.width
                            spacing: 4

                            Label {
                                text: model.name
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                            Label {
                                text: model.type
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                opacity: 0.7
                                Layout.preferredWidth: 120
                            }
                            Label {
                                text: model.messageCount
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 50
                            }
                        }
                    }

                    // Loading indicator
                    Label {
                        visible: root.detailModel.count === 0 && root.selectedIndex >= 0
                        text: "Loading..."
                        font.pixelSize: 10
                        font.italic: true
                        color: palette.mid
                    }
                }
            }
        }

        // Transfer progress bar
        Rectangle {
            id: transferBar
            Layout.fillWidth: true
            height: 32
            color: palette.window
            radius: 4
            visible: bagTransfer.running

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 8

                ProgressBar {
                    Layout.fillWidth: true
                    from: 0; to: 100
                    value: bagTransfer.progress
                }

                Label {
                    text: bagTransfer.statusText
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.preferredWidth: 200
                }

                Button {
                    text: "Cancel"
                    font.pixelSize: 10
                    flat: true
                    onClicked: bagTransfer.cancel()
                }
            }
        }
    }

    // ========================================================================
    // Transfer
    // ========================================================================

    BagTransfer {
        id: bagTransfer

        onFinished: function(success, message, localPath) {
            root.statusMessage(
                success ? "Transfer complete: " + localPath : "Transfer failed: " + message,
                !success
            );
        }
    }

    // Transfer destination dialog
    Popup {
        id: transferDialog
        modal: true
        width: 420
        height: 180
        anchors.centerIn: parent
        padding: 16

        property string remotePath: ""
        property string bagName: ""

        background: Rectangle {
            color: palette.window
            border.color: palette.mid
            radius: 8
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: "Transfer \"" + transferDialog.bagName + "\""
                font.bold: true
            }

            Label {
                text: "From: " + (root._cachedHostname || "unknown")
                font.pixelSize: 11
                opacity: 0.7
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Label { text: "Local directory:" }
                TextField {
                    id: transferLocalDir
                    Layout.fillWidth: true
                    text: _getDefaultTransferDir()
                    placeholderText: "/home/user/bags/"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }

                Button {
                    text: "Cancel"
                    onClicked: transferDialog.close()
                }

                Button {
                    text: "Transfer"
                    highlighted: true
                    onClicked: {
                        let hostname = root._cachedHostname;
                        if (!hostname) {
                            root.statusMessage("Cannot transfer: recorder hostname unknown", true);
                            transferDialog.close();
                            return;
                        }
                        bagTransfer.start(hostname, transferDialog.remotePath, transferLocalDir.text);
                        transferDialog.close();
                    }
                }
            }
        }
    }

    // ========================================================================
    // Delete Confirmation
    // ========================================================================

    Popup {
        id: deleteConfirmDialog
        modal: true
        width: 380
        height: 140
        anchors.centerIn: parent
        padding: 16

        property string bagPath: ""
        property string bagName: ""

        background: Rectangle {
            color: palette.window
            border.color: Material.color(Material.Red)
            radius: 8
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: "Delete bag \"" + deleteConfirmDialog.bagName + "\"?"
                font.bold: true
                color: Material.color(Material.Red)
            }

            Label {
                text: "This will permanently remove the bag from the recorder's filesystem."
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                font.pixelSize: 11
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }

                Button {
                    text: "Cancel"
                    onClicked: deleteConfirmDialog.close()
                }

                Button {
                    text: "Delete"
                    Material.background: Material.Red
                    Material.foreground: "white"
                    onClicked: {
                        root.recorderInterface.deleteBag(deleteConfirmDialog.bagPath, function(success, msg) {
                            if (success) root.refresh();
                        });
                        deleteConfirmDialog.close();
                    }
                }
            }
        }
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    function _loadDetails(bagPath) {
        detailModel.clear();
        if (!recorderInterface) return;
        recorderInterface.getBagDetails(bagPath, function(info, topics) {
            detailModel.clear();
            for (let i = 0; i < topics.length; i++) {
                detailModel.append(topics[i]);
            }
        });
    }

    function _startTransfer(remotePath, bagName) {
        transferDialog.remotePath = remotePath;
        transferDialog.bagName = bagName;
        transferDialog.open();
    }

    function _getDefaultTransferDir() {
        return "/tmp/bags/";
    }

    function _toggleSort(column) {
        if (root.sortColumn === column) {
            root.sortAscending = !root.sortAscending;
        } else {
            root.sortColumn = column;
            // Default descending for size/date, ascending for text columns
            root.sortAscending = (column === "name" || column === "recordedBy");
        }
        _sortBagModel();
    }

    /// Sorts bagModel in-place using insertion sort (ListModel has no built-in sort)
    function _sortBagModel() {
        let n = bagModel.count;
        if (n < 2) return;

        selectedIndex = -1;
        detailModel.clear();

        for (let i = 1; i < n; i++) {
            let j = i;
            while (j > 0 && _compareBags(bagModel.get(j - 1), bagModel.get(j)) > 0) {
                bagModel.move(j, j - 1, 1);
                j--;
            }
        }
    }

    /// Returns positive if a should come after b in current sort order
    function _compareBags(a, b) {
        let key = root.sortColumn;
        let va = a[key], vb = b[key];

        let cmp;
        if (typeof va === "number") {
            cmp = va - vb;
        } else {
            cmp = String(va).localeCompare(String(vb));
        }
        return root.sortAscending ? cmp : -cmp;
    }

    function _formatBytes(bytes) { return Utils.formatBytes(bytes); }
    function _formatDuration(secs) { return Utils.formatDuration(secs); }
}
