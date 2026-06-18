import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RQml.Fonts
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

    //! Current browse path (set from outside or via path bar)
    property string currentPath: ""

    //! Default "home" path for the recorder (from config)
    property string homePath: ""

    //! Recent paths (persisted via context)
    property var recentPaths: []

    signal statusMessage(string msg, bool isError)
    signal playRequested(string bagPath, string bagName)

    //! Scanner for local path completion in transfer dialog
    property LocalBagScanner _pathScanner: LocalBagScanner {}

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
        let path = currentPath || "";
        recorderInterface.listBags(path, function(bags) {
            bagModel.clear();
            for (let i = 0; i < bags.length; i++) {
                bagModel.append(bags[i]);
            }
            _sortBagModel();
            selectedIndex = -1;
            detailModel.clear();
            Qt.callLater(function() { bagListView.forceLayout(); });
        });
    }

    function setPath(path) {
        currentPath = path;
        pathField.text = path;
    }

    function _addRecentPath(path) {
        if (!path || path === "") return;
        // Remove duplicates, add to front, keep max 10
        let paths = recentPaths.filter(function(p) { return p !== path; });
        paths.unshift(path);
        if (paths.length > 10) paths = paths.slice(0, 10);
        recentPaths = paths;
    }

    // ========================================================================
    // Layout
    // ========================================================================

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        // ---- Path Bar ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Label {
                text: "Path:"
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: pathField.implicitHeight
                z: 10

                TextField {
                    id: pathField
                    objectName: "bagBrowserPathField"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: root.currentPath
                    placeholderText: "~/bags/"
                    selectByMouse: true

                    onAccepted: {
                        pathCompletionPopup.close();
                        root.currentPath = text;
                        _addRecentPath(text);
                        root.refresh();
                    }

                    // Tab-completion: only fetch on Tab key (not on every keystroke)
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Tab) {
                            event.accepted = true;
                            if (pathCompletionPopup.visible &&
                                pathCompletionList.currentIndex >= 0 &&
                                pathCompletionList.currentIndex < pathCompletionModel.count) {
                                pathField.text = pathCompletionModel.get(pathCompletionList.currentIndex).path;
                                pathField.cursorPosition = pathField.text.length;
                            }
                            _updatePathCompletions();
                        } else if (pathCompletionPopup.visible) {
                            if (event.key === Qt.Key_Down) {
                                pathCompletionList.incrementCurrentIndex();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up) {
                                pathCompletionList.decrementCurrentIndex();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                pathCompletionPopup.close();
                                event.accepted = true;
                            }
                        }
                    }
                }

                // Path completion popup
                Popup {
                    id: pathCompletionPopup
                    objectName: "bagBrowserPathCompletionPopup"
                    y: pathField.height
                    width: pathField.width
                    height: Math.min(pathCompletionList.contentHeight + 8, 200)
                    padding: 4
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                    background: Rectangle {
                        color: palette.window
                        border.color: palette.mid
                        radius: 4
                    }

                    ListView {
                        id: pathCompletionList
                        objectName: "bagBrowserPathCompletionList"
                        anchors.fill: parent
                        model: pathCompletionModel
                        clip: true
                        currentIndex: 0

                        delegate: ItemDelegate {
                            objectName: "bagBrowserPathCompletionItem_" + index
                            width: pathCompletionList.width
                            height: 28
                            highlighted: index === pathCompletionList.currentIndex

                            contentItem: Label {
                                text: model.path
                                font.family: "monospace"
                                elide: Text.ElideMiddle
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                pathField.text = model.path;
                                pathField.cursorPosition = pathField.text.length;
                                pathField.forceActiveFocus();
                                _updatePathCompletions();
                            }
                        }
                    }
                }

                ListModel { id: pathCompletionModel }
            }

            // Recent paths dropdown
            ComboBox {
                id: recentCombo
                objectName: "bagBrowserRecentCombo"
                Layout.preferredWidth: 36
                visible: root.recentPaths.length > 0
                model: root.recentPaths
                displayText: "\u23F0" // clock icon
                font.pixelSize: 14

                onActivated: function(index) {
                    if (index >= 0 && index < root.recentPaths.length) {
                        pathField.text = root.recentPaths[index];
                        root.currentPath = pathField.text;
                        root.refresh();
                    }
                }

                ToolTip.text: "Recent paths"
                ToolTip.visible: hovered
            }

            Button {
                objectName: "bagBrowserHomeButton"
                text: "\u2302" // home
                font.pixelSize: 14
                flat: true
                implicitWidth: 32
                implicitHeight: 28
                enabled: root.homePath !== ""
                ToolTip.text: "Go to recorder default path"
                ToolTip.visible: hovered
                onClicked: {
                    pathField.text = root.homePath;
                    root.currentPath = root.homePath;
                    root.refresh();
                }
            }

            Button {
                objectName: "bagBrowserScanButton"
                text: "Scan"
                highlighted: true
                onClicked: {
                    root.currentPath = pathField.text;
                    _addRecentPath(pathField.text);
                    root.refresh();
                }
            }
        }

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Recorded Bags"
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Label {
                text: bagModel.count + " bag" + (bagModel.count !== 1 ? "s" : "")
                color: palette.mid
            }

            Button {
                objectName: "bagBrowserRefreshButton"
                text: "\u21BB Refresh"
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

                        SortableHeader { objectName: "bagBrowserSortName"; label: "Name";       sortKey: "name";       Layout.preferredWidth: 200; Layout.fillWidth: true }
                        SortableHeader { objectName: "bagBrowserSortDate"; label: "Date";       sortKey: "startTime";  Layout.preferredWidth: 140 }
                        SortableHeader { objectName: "bagBrowserSortDuration"; label: "Duration";   sortKey: "durationSecs"; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                        SortableHeader { objectName: "bagBrowserSortSize"; label: "Size";       sortKey: "sizeBytes";  Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                        Label          { text: "Topics";     font.bold: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
                        SortableHeader { objectName: "bagBrowserSortRecordedBy"; label: "Recorded by"; sortKey: "recordedBy"; Layout.preferredWidth: 120 }
                        Label          { text: "Actions";    font.bold: true; Layout.preferredWidth: 136; horizontalAlignment: Text.AlignHCenter }
                    }
                }

                // Bag list
                ListView {
                    id: bagListView
                    objectName: "bagBrowserBagListView"
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
                                Layout.preferredWidth: 200
                                Layout.fillWidth: true
                            }

                            Label {
                                text: model.startTime
                                opacity: 0.7
                                Layout.preferredWidth: 140
                            }

                            Label {
                                text: _formatDuration(model.durationSecs)
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 70
                            }

                            Label {
                                text: _formatBytes(model.sizeBytes)
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 70
                            }

                            Label {
                                text: model.topicCount
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 50
                            }

                            Label {
                                text: model.recordedBy || "unknown"
                                elide: Text.ElideRight
                                opacity: model.recordedBy ? 0.7 : 0.4
                                font.italic: !model.recordedBy
                                Layout.preferredWidth: 120
                            }

                            // Action buttons
                            RowLayout {
                                Layout.preferredWidth: 136
                                spacing: 4

                                Button {
                                    objectName: "bagBrowserPlayButton_" + index
                                    visible: root.recorderInterface && root.recorderInterface.supportsPlayback
                                    text: "\u25B6"  // play triangle
                                    font.pixelSize: 14
                                    flat: true
                                    padding: 2
                                    implicitWidth: visible ? 36 : 0
                                    implicitHeight: 36
                                    ToolTip.text: "Play bag"
                                    ToolTip.visible: hovered
                                    onClicked: {
                                        root.playRequested(model.path, model.name);
                                    }
                                }

                                Button {
                                    objectName: "bagBrowserTransferButton_" + index
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
                                    objectName: "bagBrowserDeleteButton_" + index
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
                    objectName: "bagBrowserEmptyStateLabel"
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
                Layout.preferredWidth: root.selectedIndex >= 0 ? 550 : 0
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
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Button {
                            objectName: "bagBrowserDetailCloseButton"
                            text: IconFont.iconClose
                            font.family: IconFont.name
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

                        Label { text: "Topic"; font.bold: true; Layout.fillWidth: true }
                        Label { text: "Type"; font.bold: true; Layout.preferredWidth: 220 }
                        Label { text: "Msgs"; font.bold: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
                    }

                    // Topic list
                    ListView {
                        id: detailListView
                        objectName: "bagBrowserDetailListView"
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
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                            Label {
                                text: model.type
                                elide: Text.ElideRight
                                opacity: 0.7
                                Layout.preferredWidth: 220
                            }
                            Label {
                                text: model.messageCount
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 50
                            }
                        }
                    }

                    // Loading indicator
                    Label {
                        objectName: "bagBrowserDetailLoadingLabel"
                        visible: root.detailModel.count === 0 && root.selectedIndex >= 0
                        text: "Loading..."
                        font.italic: true
                        color: palette.mid
                    }
                }
            }
        }

        // ---- Transfer Progress Panel ----
        Rectangle {
            id: transferBar
            Layout.fillWidth: true
            implicitHeight: transferBarContent.implicitHeight + 16
            color: palette.window
            radius: 4
            visible: bagTransfer.running || _transferJustFinished

            property bool _transferJustFinished: false
            Connections {
                target: bagTransfer
                function onFinished(success, message, localPath) {
                    if (success) {
                        transferBar._transferJustFinished = true;
                        transferFinishedTimer.restart();
                    }
                }
            }
            Timer {
                id: transferFinishedTimer
                interval: 5000
                onTriggered: transferBar._transferJustFinished = false
            }

            ColumnLayout {
                id: transferBarContent
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                // Source and destination
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: "Source:"
                        font.bold: true
                        opacity: 0.7
                    }
                    Label {
                        text: bagTransfer.sourcePath
                        font.family: "monospace"
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        opacity: 0.7
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: "Dest:"
                        font.bold: true
                        opacity: 0.7
                    }
                    Label {
                        text: bagTransfer.destPath
                        font.family: "monospace"
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        opacity: 0.7
                    }
                }

                // Progress bar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ProgressBar {
                        Layout.fillWidth: true
                        from: 0; to: 100
                        value: bagTransfer.progress
                    }

                    Label {
                        text: Math.round(bagTransfer.progress) + "%"
                        font.bold: true
                        Layout.preferredWidth: 40
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // Status: transferred/total, speed, ETA
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        text: bagTransfer.statusText
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Button {
                        objectName: "bagBrowserTransferCancelButton"
                        text: "Cancel"
                        flat: true
                        visible: bagTransfer.running
                        onClicked: bagTransfer.cancel()
                    }
                }
            }
        }
    }

    // ========================================================================
    // Transfer
    // ========================================================================

    BagTransfer {
        id: bagTransfer
        objectName: "bagBrowserBagTransfer"

        onFinished: function(success, message, localPath) {
            root.statusMessage(
                success ? "Transfer complete: " + localPath : "Transfer failed: " + message,
                !success
            );
            if (!success) {
                transferErrorDialog.command = bagTransfer.failureCommand;
                transferErrorDialog.output = bagTransfer.failureOutput;
                transferErrorDialog.open();
            }
        }
    }

    // ========================================================================
    // Transfer Error
    // ========================================================================

    Popup {
        id: transferErrorDialog
        objectName: "bagBrowserTransferErrorDialog"
        modal: true
        width: 560
        height: 320
        anchors.centerIn: parent
        padding: 16

        property string command: ""
        property string output: ""

        background: Rectangle {
            color: palette.window
            border.color: Material.color(Material.Red)
            radius: 8
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: "Transfer failed"
                font.bold: true
                color: Material.color(Material.Red)
            }

            Label {
                text: "Run the command in a terminal to retry and " +
                      "see the full error."
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                opacity: 0.8
            }

            // Copyable rsync command
            Label {
                text: "Command:"
                font.bold: true
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                TextField {
                    id: transferErrorCommandField
                    objectName: "bagBrowserTransferErrorCommandField"
                    Layout.fillWidth: true
                    text: transferErrorDialog.command
                    readOnly: true
                    selectByMouse: true
                    font.family: "monospace"
                }

                Button {
                    objectName: "bagBrowserTransferErrorCopyButton"
                    text: "Copy"
                    onClicked: {
                        transferErrorCommandField.selectAll();
                        transferErrorCommandField.copy();
                        transferErrorCommandField.deselect();
                        root.statusMessage("rsync command copied to clipboard", false);
                    }
                }
            }

            // Captured rsync/ssh output
            Label {
                text: "Output:"
                font.bold: true
                visible: transferErrorDialog.output !== ""
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: transferErrorDialog.output !== ""
                clip: true

                TextArea {
                    objectName: "bagBrowserTransferErrorOutput"
                    text: transferErrorDialog.output
                    readOnly: true
                    selectByMouse: true
                    font.family: "monospace"
                    wrapMode: TextArea.NoWrap
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }

                Button {
                    objectName: "bagBrowserTransferErrorCloseButton"
                    text: "Close"
                    onClicked: transferErrorDialog.close()
                }
            }
        }
    }

    // Transfer destination dialog
    Popup {
        id: transferDialog
        objectName: "bagBrowserTransferDialog"
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
                opacity: 0.7
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Label { text: "Local directory:" }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: transferLocalDir.implicitHeight

                    TextField {
                        id: transferLocalDir
                        objectName: "bagBrowserTransferLocalDirField"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        text: _getDefaultTransferDir()
                        placeholderText: "~/bags/"
                        selectByMouse: true

                        onTextEdited: transferCompletionTimer.restart()

                        Keys.onPressed: function(event) {
                            if (!transferCompletionPopup.visible) return;

                            if (event.key === Qt.Key_Down) {
                                transferCompletionList.incrementCurrentIndex();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up) {
                                transferCompletionList.decrementCurrentIndex();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                if (transferCompletionList.currentIndex >= 0 && transferCompletionList.currentIndex < transferCompletionModel.count) {
                                    transferLocalDir.text = transferCompletionModel.get(transferCompletionList.currentIndex).path;
                                    transferLocalDir.cursorPosition = transferLocalDir.text.length;
                                    transferCompletionTimer.restart();
                                    event.accepted = true;
                                }
                            } else if (event.key === Qt.Key_Escape) {
                                transferCompletionPopup.close();
                                event.accepted = true;
                            }
                        }

                        Timer {
                            id: transferCompletionTimer
                            interval: 150
                            onTriggered: _updateTransferCompletions()
                        }
                    }

                    Popup {
                        id: transferCompletionPopup
                        objectName: "bagBrowserTransferCompletionPopup"
                        y: transferLocalDir.height
                        width: transferLocalDir.width
                        height: Math.min(transferCompletionList.contentHeight + 8, 200)
                        padding: 4
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                        background: Rectangle {
                            color: palette.window
                            border.color: palette.mid
                            radius: 4
                        }

                        ListView {
                            id: transferCompletionList
                            objectName: "bagBrowserTransferCompletionList"
                            anchors.fill: parent
                            model: transferCompletionModel
                            clip: true
                            currentIndex: 0

                            delegate: ItemDelegate {
                                objectName: "bagBrowserTransferCompletionItem_" + index
                                width: transferCompletionList.width
                                height: 28
                                highlighted: index === transferCompletionList.currentIndex

                                contentItem: Label {
                                    text: model.path
                                    font.family: "monospace"
                                    elide: Text.ElideMiddle
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    transferLocalDir.text = model.path;
                                    transferLocalDir.cursorPosition = transferLocalDir.text.length;
                                    transferLocalDir.forceActiveFocus();
                                    transferCompletionTimer.restart();
                                }
                            }
                        }
                    }

                    ListModel {
                        id: transferCompletionModel
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }

                Button {
                    objectName: "bagBrowserTransferDialogCancelButton"
                    text: "Cancel"
                    onClicked: transferDialog.close()
                }

                Button {
                    objectName: "bagBrowserTransferDialogConfirmButton"
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
        objectName: "bagBrowserDeleteConfirmDialog"
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
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }

                Button {
                    objectName: "bagBrowserDeleteDialogCancelButton"
                    text: "Cancel"
                    onClicked: deleteConfirmDialog.close()
                }

                Button {
                    objectName: "bagBrowserDeleteDialogConfirmButton"
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
        return "~/bags/";
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

    function _updatePathCompletions() {
        // For local recorders, use scanner. For remote, this is a no-op
        // (user must use Tab to trigger, and only local scanner works)
        if (!recorderInterface || !recorderInterface.isLocal) {
            // Remote: could add a service call here later
            pathCompletionPopup.close();
            return;
        }
        let completions = _pathScanner.completePath(pathField.text);
        pathCompletionModel.clear();

        if (completions.length === 0) {
            pathCompletionPopup.close();
            return;
        }

        if (completions.length === 1 && completions[0] === pathField.text) {
            pathCompletionPopup.close();
            return;
        }

        for (let i = 0; i < completions.length; i++) {
            pathCompletionModel.append({ path: completions[i] });
        }

        pathCompletionList.currentIndex = 0;
        if (!pathCompletionPopup.visible)
            pathCompletionPopup.open();
    }

    function _updateTransferCompletions() {
        let completions = _pathScanner.completePath(transferLocalDir.text);
        transferCompletionModel.clear();

        if (completions.length === 0) {
            transferCompletionPopup.close();
            return;
        }

        if (completions.length === 1 && completions[0] === transferLocalDir.text) {
            transferCompletionPopup.close();
            return;
        }

        for (let i = 0; i < completions.length; i++) {
            transferCompletionModel.append({ path: completions[i] });
        }

        transferCompletionList.currentIndex = 0;
        if (!transferCompletionPopup.visible)
            transferCompletionPopup.open();
    }

    function _formatBytes(bytes) { return Utils.formatBytes(bytes); }
    function _formatDuration(secs) { return Utils.formatDuration(secs); }
}
