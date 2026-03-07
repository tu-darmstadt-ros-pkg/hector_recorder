import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RqmlRecorder

/**
 * Browser pane for recorded bag files.
 * Shows a table of bags with expandable per-topic details,
 * transfer (rsync pull) and delete functionality.
 */
Rectangle {
    id: root
    color: palette.alternateBase
    radius: 4

    //! The RecorderInterface to use for service calls
    property var recorderInterface: null

    //! Bag list model populated from ListBags service
    property ListModel bagModel: ListModel {}

    //! Currently expanded bag index (-1 = none)
    property int expandedIndex: -1

    //! Per-topic details for the expanded bag
    property ListModel detailModel: ListModel {}

    signal statusMessage(string msg, bool isError)

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
            expandedIndex = -1;
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

        // Column headers
        Rectangle {
            Layout.fillWidth: true
            height: 28
            color: palette.button
            radius: 2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 4

                Label { text: "Name";       font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 200; Layout.fillWidth: true }
                Label { text: "Date";       font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 140 }
                Label { text: "Size";       font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                Label { text: "Topics";     font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
                Label { text: "Recorded By"; font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 120 }
                Label { text: "Actions";    font.bold: true; font.pixelSize: 11; Layout.preferredWidth: 100; horizontalAlignment: Text.AlignHCenter }
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

            delegate: Column {
                width: bagListView.width

                // Main bag row
                Rectangle {
                    width: parent.width
                    height: 36
                    color: index === root.expandedIndex ? Qt.darker(palette.highlight, 1.8) :
                           (bagRowMouse.containsMouse ? palette.midlight : palette.base)
                    radius: 2

                    MouseArea {
                        id: bagRowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (root.expandedIndex === index) {
                                root.expandedIndex = -1;
                                root.detailModel.clear();
                            } else {
                                root.expandedIndex = index;
                                _loadDetails(model.path);
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4

                        // Expand indicator
                        Label {
                            text: index === root.expandedIndex ? "\u25BC" : "\u25B6"
                            font.pixelSize: 10
                            color: palette.mid
                            Layout.preferredWidth: 12
                        }

                        Label {
                            text: model.name
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            Layout.preferredWidth: 188
                            Layout.fillWidth: true
                        }

                        Label {
                            text: model.startTime
                            font.pixelSize: 11
                            color: palette.mid
                            Layout.preferredWidth: 140
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
                            color: palette.mid
                            Layout.preferredWidth: 120
                        }

                        // Action buttons
                        RowLayout {
                            Layout.preferredWidth: 100
                            spacing: 4

                            Button {
                                text: "\uD83D\uDCE5"  // inbox tray (download)
                                font.pixelSize: 16
                                flat: true
                                padding: 2
                                implicitWidth: 36
                                implicitHeight: 36
                                ToolTip.text: "Transfer to local machine"
                                ToolTip.visible: hovered
                                onClicked: {
                                    _startTransfer(model.path, model.name);
                                }
                            }

                            Button {
                                text: "\uD83D\uDDD1"  // wastebasket (delete)
                                font.pixelSize: 16
                                flat: true
                                padding: 2
                                implicitWidth: 36
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

                // Expanded detail section
                Rectangle {
                    width: parent.width
                    height: index === root.expandedIndex ? detailColumn.implicitHeight + 16 : 0
                    visible: index === root.expandedIndex
                    color: Qt.darker(palette.base, 1.1)
                    clip: true

                    Behavior on height { NumberAnimation { duration: 150 } }

                    ColumnLayout {
                        id: detailColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 2

                        // Duration info
                        Label {
                            property var _bag: index >= 0 && index < bagModel.count ? bagModel.get(index) : null
                            text: _bag ? "Duration: " + _formatDuration(_bag.durationSecs)
                                + "  |  Messages: " + _bag.messageCount : ""
                            font.pixelSize: 11
                            color: palette.mid
                        }

                        // Detail table header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Layout.topMargin: 4

                            Label { text: "Topic"; font.bold: true; font.pixelSize: 10; Layout.preferredWidth: 250; Layout.fillWidth: true }
                            Label { text: "Type"; font.bold: true; font.pixelSize: 10; Layout.preferredWidth: 200 }
                            Label { text: "Messages"; font.bold: true; font.pixelSize: 10; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight }
                        }

                        Repeater {
                            model: root.detailModel

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Label { text: model.name; font.pixelSize: 10; elide: Text.ElideMiddle; Layout.preferredWidth: 250; Layout.fillWidth: true }
                                Label { text: model.type; font.pixelSize: 10; elide: Text.ElideRight; color: palette.mid; Layout.preferredWidth: 200 }
                                Label { text: model.messageCount; font.pixelSize: 10; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 80 }
                            }
                        }

                        // Loading indicator
                        Label {
                            visible: root.detailModel.count === 0 && root.expandedIndex >= 0
                            text: "Loading..."
                            font.pixelSize: 10
                            font.italic: true
                            color: palette.mid
                        }
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
                text: "From: " + (root.recorderInterface && root.recorderInterface.status
                    ? root.recorderInterface.status.hostname : "unknown")
                font.pixelSize: 11
                color: palette.mid
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
                        let hostname = root.recorderInterface && root.recorderInterface.status
                            ? root.recorderInterface.status.hostname : "";
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

    function _formatBytes(bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB";
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB";
    }

    function _formatDuration(secs) {
        let s = Math.round(secs);
        let mins = Math.floor(s / 60);
        let hrs = Math.floor(mins / 60);
        return hrs + ":" + String(mins % 60).padStart(2, '0') + ":" + String(s % 60).padStart(2, '0');
    }
}
