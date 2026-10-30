import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RQml.Fonts
import RQml.Recorder
import "../utils.js" as Utils

/**
 * Browser pane for recorded bag files.
 * Shows a table of bags on the left. Clicking a row slides in a
 * detail panel on the right showing per-topic information.
 */
Rectangle {
    id: root

    //! Cached hostname from GetRecorderInfo service
    property string _cachedHostname: ""

    //! Scanner for local path completion in transfer dialog
    property LocalBagScanner _pathScanner: LocalBagScanner {
    }

    //! Bag list model populated from ListBags service
    property ListModel bagModel: ListModel {
    }

    //! Current browse path (set from outside or via path bar)
    property string currentPath: ""

    //! Per-topic details for the selected bag
    property ListModel detailModel: ListModel {
    }

    //! Default "home" path for the recorder (from config)
    property string homePath: ""

    //! Recent paths (persisted via context)
    property var recentPaths: []

    //! The RecorderInterface to use for service calls
    property var recorderInterface: null

    //! Currently selected bag index (-1 = none)
    property int selectedIndex: -1

    //! Set to false to hide the built-in path bar (e.g. when the parent provides its own)
    property bool showPathBar: true
    //! true = ascending, false = descending
    property bool sortAscending: false

    //! Current sort column key
    property string sortColumn: "startTime"

    signal playRequested(string bagPath, string bagName)
    signal statusMessage(string msg, bool isError)

    function _addRecentPath(path) {
        if (!path || path === "")
            return;
        // Remove duplicates, add to front, keep max 10
        let paths = recentPaths.filter(function (p) {
            return p !== path;
        });
        paths.unshift(path);
        if (paths.length > 10)
            paths = paths.slice(0, 10);
        recentPaths = paths;
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
    function _formatBytes(bytes) {
        return Utils.formatBytes(bytes);
    }
    function _formatDuration(secs) {
        return Utils.formatDuration(secs);
    }
    function _getDefaultTransferDir() {
        return "~/bags/";
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    function _loadDetails(bagPath) {
        detailModel.clear();
        if (!recorderInterface)
            return;
        recorderInterface.getBagDetails(bagPath, function (info, topics) {
            detailModel.clear();
            for (let i = 0; i < topics.length; i++) {
                detailModel.append(topics[i]);
            }
        });
    }

    /// Sorts bagModel in-place using insertion sort (ListModel has no built-in sort)
    function _sortBagModel() {
        let n = bagModel.count;
        if (n < 2)
            return;

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
    function _startTransfer(remotePath, bagName) {
        transferDialog.remotePath = remotePath;
        transferDialog.bagName = bagName;
        transferDialog.open();
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
            pathCompletionModel.append({
                path: completions[i]
            });
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
            transferCompletionModel.append({
                path: completions[i]
            });
        }

        transferCompletionList.currentIndex = 0;
        if (!transferCompletionPopup.visible)
            transferCompletionPopup.open();
    }

    // ========================================================================
    // Public API
    // ========================================================================

    function refresh() {
        if (!recorderInterface)
            return;
        let path = currentPath || "";
        recorderInterface.listBags(path, function (bags) {
            bagModel.clear();
            for (let i = 0; i < bags.length; i++) {
                bagModel.append(bags[i]);
            }
            _sortBagModel();
            selectedIndex = -1;
            detailModel.clear();
            Qt.callLater(function () {
                bagListView.forceLayout();
            });
        });
    }
    function setPath(path) {
        currentPath = path;
        pathField.text = path;
    }

    color: palette.alternateBase
    radius: 4

    onRecorderInterfaceChanged: {
        _cachedHostname = "";
        if (recorderInterface && recorderInterface.supportsTransfer) {
            recorderInterface.fetchRecorderInfo(function (info) {
                root._cachedHostname = info.hostname;
            });
        }
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
            visible: root.showPathBar

            Label {
                text: "Path:"
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: pathField.implicitHeight
                z: 10

                TextField {
                    id: pathField

                    anchors.left: parent.left
                    anchors.right: parent.right
                    objectName: "bagBrowserPathField"
                    placeholderText: "~/bags/"
                    selectByMouse: true
                    text: root.currentPath

                    // Tab-completion: only fetch on Tab key (not on every keystroke)
                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Tab) {
                            event.accepted = true;
                            if (pathCompletionPopup.visible && pathCompletionList.currentIndex >= 0 && pathCompletionList.currentIndex < pathCompletionModel.count) {
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
                    onAccepted: {
                        pathCompletionPopup.close();
                        root.currentPath = text;
                        _addRecentPath(text);
                        root.refresh();
                    }
                }

                // Path completion popup
                Popup {
                    id: pathCompletionPopup

                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    height: Math.min(pathCompletionList.contentHeight + 8, 200)
                    objectName: "bagBrowserPathCompletionPopup"
                    padding: 4
                    width: pathField.width
                    y: pathField.height

                    background: Rectangle {
                        border.color: palette.mid
                        color: palette.window
                        radius: 4
                    }

                    ListView {
                        id: pathCompletionList

                        anchors.fill: parent
                        clip: true
                        currentIndex: 0
                        model: pathCompletionModel
                        objectName: "bagBrowserPathCompletionList"

                        delegate: ItemDelegate {
                            height: 28
                            highlighted: index === pathCompletionList.currentIndex
                            objectName: "bagBrowserPathCompletionItem_" + index
                            width: pathCompletionList.width

                            contentItem: Label {
                                elide: Text.ElideMiddle
                                font.family: "monospace"
                                text: model.path
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
                ListModel {
                    id: pathCompletionModel

                }
            }

            // Recent paths dropdown
            ComboBox {
                id: recentCombo

                Layout.preferredWidth: 36
                ToolTip.text: "Recent paths"
                ToolTip.visible: hovered
                displayText: "\u23F0" // clock icon
                font.pixelSize: 14
                model: root.recentPaths
                objectName: "bagBrowserRecentCombo"
                visible: root.recentPaths.length > 0

                onActivated: function (index) {
                    if (index >= 0 && index < root.recentPaths.length) {
                        pathField.text = root.recentPaths[index];
                        root.currentPath = pathField.text;
                        root.refresh();
                    }
                }
            }
            Button {
                ToolTip.text: "Go to recorder default path"
                ToolTip.visible: hovered
                enabled: root.homePath !== ""
                flat: true
                font.pixelSize: 14
                implicitHeight: 28
                implicitWidth: 32
                objectName: "bagBrowserHomeButton"
                text: "\u2302" // home

                onClicked: {
                    pathField.text = root.homePath;
                    root.currentPath = root.homePath;
                    root.refresh();
                }
            }
            Button {
                highlighted: true
                objectName: "bagBrowserScanButton"
                text: "Scan"

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
                font.bold: true
                text: "Recorded Bags"
            }
            Item {
                Layout.fillWidth: true
            }
            Label {
                color: palette.mid
                objectName: "bagBrowserBagCountLabel"
                text: bagModel.count + " bag" + (bagModel.count !== 1 ? "s" : "")
            }
            Button {
                flat: true
                objectName: "bagBrowserRefreshButton"
                text: "\u21BB Refresh"

                onClicked: root.refresh()
            }
        }

        // Main content: bag list + detail panel side by side
        RowLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            spacing: 0

            // Left side: bag list
            ColumnLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true
                spacing: 0

                // Column headers (clickable for sorting)
                Rectangle {
                    Layout.fillWidth: true
                    color: palette.button
                    height: 28
                    radius: 2

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4

                        SortableHeader {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 200
                            label: "Name"
                            objectName: "bagBrowserSortName"
                            sortKey: "name"
                        }
                        SortableHeader {
                            Layout.preferredWidth: 140
                            label: "Date"
                            objectName: "bagBrowserSortDate"
                            sortKey: "startTime"
                        }
                        SortableHeader {
                            Layout.preferredWidth: 70
                            horizontalAlignment: Text.AlignRight
                            label: "Duration"
                            objectName: "bagBrowserSortDuration"
                            sortKey: "durationSecs"
                        }
                        SortableHeader {
                            Layout.preferredWidth: 70
                            horizontalAlignment: Text.AlignRight
                            label: "Size"
                            objectName: "bagBrowserSortSize"
                            sortKey: "sizeBytes"
                        }
                        Label {
                            Layout.preferredWidth: 50
                            font.bold: true
                            horizontalAlignment: Text.AlignRight
                            text: "Topics"
                        }
                        SortableHeader {
                            Layout.preferredWidth: 120
                            label: "Recorded by"
                            objectName: "bagBrowserSortRecordedBy"
                            sortKey: "recordedBy"
                        }
                        Label {
                            Layout.preferredWidth: 136
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            text: "Actions"
                        }
                    }
                }

                // Bag list
                ListView {
                    id: bagListView

                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    clip: true
                    model: bagModel
                    objectName: "bagBrowserBagListView"
                    spacing: 1

                    delegate: Rectangle {
                        color: index === root.selectedIndex ? palette.highlight : (bagRowMouse.containsMouse ? palette.midlight : palette.base)
                        height: 36
                        objectName: "bagBrowserBagRow_" + index
                        radius: 2
                        width: bagListView.width

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
                                Layout.fillWidth: true
                                Layout.preferredWidth: 200
                                elide: Text.ElideRight
                                objectName: "bagBrowserBagNameLabel_" + index
                                text: model.name
                            }
                            Label {
                                Layout.preferredWidth: 140
                                opacity: 0.7
                                text: model.startTime
                            }
                            Label {
                                Layout.preferredWidth: 70
                                horizontalAlignment: Text.AlignRight
                                text: _formatDuration(model.durationSecs)
                            }
                            Label {
                                Layout.preferredWidth: 70
                                horizontalAlignment: Text.AlignRight
                                text: _formatBytes(model.sizeBytes)
                            }
                            Label {
                                Layout.preferredWidth: 50
                                horizontalAlignment: Text.AlignRight
                                text: model.topicCount
                            }
                            Label {
                                Layout.preferredWidth: 120
                                elide: Text.ElideRight
                                font.italic: !model.recordedBy
                                opacity: model.recordedBy ? 0.7 : 0.4
                                text: model.recordedBy || "unknown"
                            }

                            // Action buttons
                            RowLayout {
                                Layout.preferredWidth: 136
                                spacing: 4

                                Button {
                                    ToolTip.text: "Play bag"
                                    ToolTip.visible: hovered
                                    flat: true
                                    font.pixelSize: 14
                                    implicitHeight: 36
                                    implicitWidth: visible ? 36 : 0
                                    objectName: "bagBrowserPlayButton_" + index
                                    padding: 2
                                    text: "\u25B6"  // play triangle
                                    visible: root.recorderInterface && root.recorderInterface.supportsPlayback

                                    onClicked: {
                                        root.playRequested(model.path, model.name);
                                    }
                                }
                                Button {
                                    ToolTip.text: "Transfer to local machine"
                                    ToolTip.visible: hovered
                                    flat: true
                                    font.pixelSize: 16
                                    implicitHeight: 36
                                    implicitWidth: visible ? 36 : 0
                                    objectName: "bagBrowserTransferButton_" + index
                                    padding: 2
                                    text: "\uD83D\uDCE5"  // inbox tray (download)
                                    visible: root.recorderInterface && root.recorderInterface.supportsTransfer

                                    onClicked: {
                                        _startTransfer(model.path, model.name);
                                    }
                                }
                                Button {
                                    ToolTip.text: "Delete bag"
                                    ToolTip.visible: hovered
                                    flat: true
                                    font.pixelSize: 16
                                    implicitHeight: 36
                                    implicitWidth: visible ? 36 : 0
                                    objectName: "bagBrowserDeleteButton_" + index
                                    padding: 2
                                    text: "\uD83D\uDDD1"  // wastebasket (delete)
                                    visible: root.recorderInterface && root.recorderInterface.supportsDelete

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
                    Layout.fillHeight: bagModel.count === 0
                    Layout.fillWidth: true
                    color: palette.mid
                    font.italic: true
                    horizontalAlignment: Text.AlignHCenter
                    objectName: "bagBrowserEmptyStateLabel"
                    text: "No bags found. Click Refresh to scan."
                    verticalAlignment: Text.AlignVCenter
                    visible: bagModel.count === 0
                }
            }

            // Right side: detail panel (slides in when a bag is selected)
            Rectangle {
                id: detailPanel

                Layout.fillHeight: true
                Layout.preferredWidth: root.selectedIndex >= 0 ? 550 : 0
                clip: true
                color: Qt.darker(palette.base, 1.05)
                objectName: "bagBrowserDetailPanel"
                visible: Layout.preferredWidth > 0

                Behavior on Layout.preferredWidth {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                // Subtle left border
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.top: parent.top
                    color: palette.mid
                    opacity: 0.3
                    width: 1
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
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.bold: true
                            objectName: "bagBrowserDetailTitleLabel"
                            text: root.selectedIndex >= 0 && root.selectedIndex < bagModel.count ? bagModel.get(root.selectedIndex).name : ""
                        }
                        Button {
                            flat: true
                            font.family: IconFont.name
                            implicitHeight: 24
                            implicitWidth: 24
                            objectName: "bagBrowserDetailCloseButton"
                            padding: 2
                            text: IconFont.iconClose

                            onClicked: {
                                root.selectedIndex = -1;
                                root.detailModel.clear();
                            }
                        }
                    }

                    // Bag summary
                    Label {
                        property var _bag: root.selectedIndex >= 0 && root.selectedIndex < bagModel.count ? bagModel.get(root.selectedIndex) : null

                        opacity: 0.7
                        text: _bag ? "Duration: " + _formatDuration(_bag.durationSecs) + "  |  Messages: " + _bag.messageCount : ""
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        color: palette.mid
                        height: 1
                        opacity: 0.3
                    }

                    // Topic detail table header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Label {
                            Layout.fillWidth: true
                            font.bold: true
                            text: "Topic"
                        }
                        Label {
                            Layout.preferredWidth: 220
                            font.bold: true
                            text: "Type"
                        }
                        Label {
                            Layout.preferredWidth: 50
                            font.bold: true
                            horizontalAlignment: Text.AlignRight
                            text: "Msgs"
                        }
                    }

                    // Topic list
                    ListView {
                        id: detailListView

                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        clip: true
                        model: root.detailModel
                        objectName: "bagBrowserDetailListView"
                        spacing: 1

                        delegate: RowLayout {
                            spacing: 4
                            width: detailListView.width

                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                objectName: "bagBrowserDetailTopicName_" + index
                                text: model.name
                            }
                            Label {
                                Layout.preferredWidth: 220
                                elide: Text.ElideRight
                                opacity: 0.7
                                text: model.type
                            }
                            Label {
                                Layout.preferredWidth: 50
                                horizontalAlignment: Text.AlignRight
                                text: model.messageCount
                            }
                        }
                    }

                    // Loading indicator
                    Label {
                        color: palette.mid
                        font.italic: true
                        objectName: "bagBrowserDetailLoadingLabel"
                        text: "Loading..."
                        visible: root.detailModel.count === 0 && root.selectedIndex >= 0
                    }
                }
            }
        }

        // ---- Transfer Progress Panel ----
        Rectangle {
            id: transferBar

            property bool _transferJustFinished: false

            Layout.fillWidth: true
            color: palette.window
            implicitHeight: transferBarContent.implicitHeight + 16
            objectName: "bagBrowserTransferBar"
            radius: 4
            visible: bagTransfer.running || _transferJustFinished

            Connections {
                function onFinished(success, message, localPath) {
                    if (success) {
                        transferBar._transferJustFinished = true;
                        transferFinishedTimer.restart();
                    }
                }

                target: bagTransfer
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
                        font.bold: true
                        opacity: 0.7
                        text: "Source:"
                    }
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        font.family: "monospace"
                        opacity: 0.7
                        text: bagTransfer.sourcePath
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        font.bold: true
                        opacity: 0.7
                        text: "Dest:"
                    }
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        font.family: "monospace"
                        opacity: 0.7
                        text: bagTransfer.destPath
                    }
                }

                // Progress bar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ProgressBar {
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: bagTransfer.progress
                    }
                    Label {
                        Layout.preferredWidth: 40
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                        objectName: "bagBrowserTransferPercentLabel"
                        text: Math.round(bagTransfer.progress) + "%"
                    }
                }

                // Status: transferred/total, speed, ETA
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        objectName: "bagBrowserTransferStatusLabel"
                        text: bagTransfer.statusText
                    }
                    Button {
                        flat: true
                        objectName: "bagBrowserTransferCancelButton"
                        text: "Cancel"
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

        onFinished: function (success, message, localPath) {
            root.statusMessage(success ? "Transfer complete: " + localPath : "Transfer failed: " + message, !success);
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

        property string command: ""
        property string output: ""

        anchors.centerIn: parent
        height: 320
        modal: true
        objectName: "bagBrowserTransferErrorDialog"
        padding: 16
        width: 560

        background: Rectangle {
            border.color: Material.color(Material.Red)
            color: palette.window
            radius: 8
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                color: Material.color(Material.Red)
                font.bold: true
                text: "Transfer failed"
            }
            Label {
                Layout.fillWidth: true
                opacity: 0.8
                text: "Run the command in a terminal to retry and " + "see the full error."
                wrapMode: Text.Wrap
            }

            // Copyable rsync command
            Label {
                font.bold: true
                text: "Command:"
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                TextField {
                    id: transferErrorCommandField

                    Layout.fillWidth: true
                    font.family: "monospace"
                    objectName: "bagBrowserTransferErrorCommandField"
                    readOnly: true
                    selectByMouse: true
                    text: transferErrorDialog.command
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
                font.bold: true
                text: "Output:"
                visible: transferErrorDialog.output !== ""
            }
            ScrollView {
                Layout.fillHeight: true
                Layout.fillWidth: true
                clip: true
                visible: transferErrorDialog.output !== ""

                TextArea {
                    font.family: "monospace"
                    objectName: "bagBrowserTransferErrorOutput"
                    readOnly: true
                    selectByMouse: true
                    text: transferErrorDialog.output
                    wrapMode: TextArea.NoWrap
                }
            }
            RowLayout {
                Layout.fillWidth: true

                Item {
                    Layout.fillWidth: true
                }
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

        property string bagName: ""
        property string remotePath: ""

        anchors.centerIn: parent
        height: 180
        modal: true
        objectName: "bagBrowserTransferDialog"
        padding: 16
        width: 420

        background: Rectangle {
            border.color: palette.mid
            color: palette.window
            radius: 8
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                font.bold: true
                text: "Transfer \"" + transferDialog.bagName + "\""
            }
            Label {
                objectName: "bagBrowserTransferDialogHostLabel"
                opacity: 0.7
                text: "From: " + (root._cachedHostname || "unknown")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    text: "Local directory:"
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: transferLocalDir.implicitHeight

                    TextField {
                        id: transferLocalDir

                        anchors.left: parent.left
                        anchors.right: parent.right
                        objectName: "bagBrowserTransferLocalDirField"
                        placeholderText: "~/bags/"
                        selectByMouse: true
                        text: _getDefaultTransferDir()

                        Keys.onPressed: function (event) {
                            if (!transferCompletionPopup.visible)
                                return;

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
                        onTextEdited: transferCompletionTimer.restart()

                        Timer {
                            id: transferCompletionTimer

                            interval: 150

                            onTriggered: _updateTransferCompletions()
                        }
                    }
                    Popup {
                        id: transferCompletionPopup

                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                        height: Math.min(transferCompletionList.contentHeight + 8, 200)
                        objectName: "bagBrowserTransferCompletionPopup"
                        padding: 4
                        width: transferLocalDir.width
                        y: transferLocalDir.height

                        background: Rectangle {
                            border.color: palette.mid
                            color: palette.window
                            radius: 4
                        }

                        ListView {
                            id: transferCompletionList

                            anchors.fill: parent
                            clip: true
                            currentIndex: 0
                            model: transferCompletionModel
                            objectName: "bagBrowserTransferCompletionList"

                            delegate: ItemDelegate {
                                height: 28
                                highlighted: index === transferCompletionList.currentIndex
                                objectName: "bagBrowserTransferCompletionItem_" + index
                                width: transferCompletionList.width

                                contentItem: Label {
                                    elide: Text.ElideMiddle
                                    font.family: "monospace"
                                    text: model.path
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

                Item {
                    Layout.fillWidth: true
                }
                Button {
                    objectName: "bagBrowserTransferDialogCancelButton"
                    text: "Cancel"

                    onClicked: transferDialog.close()
                }
                Button {
                    highlighted: true
                    objectName: "bagBrowserTransferDialogConfirmButton"
                    text: "Transfer"

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

        property string bagName: ""
        property string bagPath: ""

        anchors.centerIn: parent
        height: 140
        modal: true
        objectName: "bagBrowserDeleteConfirmDialog"
        padding: 16
        width: 380

        background: Rectangle {
            border.color: Material.color(Material.Red)
            color: palette.window
            radius: 8
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                color: Material.color(Material.Red)
                font.bold: true
                text: "Delete bag \"" + deleteConfirmDialog.bagName + "\"?"
            }
            Label {
                Layout.fillWidth: true
                text: "This will permanently remove the bag from the recorder's filesystem."
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true

                Item {
                    Layout.fillWidth: true
                }
                Button {
                    objectName: "bagBrowserDeleteDialogCancelButton"
                    text: "Cancel"

                    onClicked: deleteConfirmDialog.close()
                }
                Button {
                    Material.background: Material.Red
                    Material.foreground: "white"
                    objectName: "bagBrowserDeleteDialogConfirmButton"
                    text: "Delete"

                    onClicked: {
                        root.recorderInterface.deleteBag(deleteConfirmDialog.bagPath, function (success, msg) {
                            if (success)
                                root.refresh();
                        });
                        deleteConfirmDialog.close();
                    }
                }
            }
        }
    }

    component SortableHeader: Label {
        property string label: ""
        property string sortKey: ""

        color: root.sortColumn === sortKey ? palette.highlight : palette.text
        font.bold: true
        text: label + (sortKey && root.sortColumn === sortKey ? (root.sortAscending ? " \u25B2" : " \u25BC") : "")

        MouseArea {
            anchors.fill: parent
            cursorShape: sortKey ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: sortKey !== ""

            onClicked: _toggleSort(sortKey)
        }
    }
}
