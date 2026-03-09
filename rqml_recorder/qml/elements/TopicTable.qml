import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import "../utils.js" as Utils

/**
 * Sortable table displaying per-topic recording statistics.
 * Matches the columns from hector_recorder's TUI: Topic, Msgs, Freq, Bandwidth, Size, Type.
 */
Rectangle {
    id: root
    color: palette.alternateBase
    radius: 4

    //! The ListModel to display (from RecorderInterface.topicsModel)
    property var model: null

    //! Current sort column and direction
    property string sortColumn: "size"
    property bool sortAscending: false

    //! Sorted indices
    property var sortedIndices: []

    onModelChanged: _resort()

    // ========================================================================
    // Sorting
    // ========================================================================

    function _resort() {
        if (!model || model.count === 0) {
            sortedIndices = [];
            return;
        }

        let indices = [];
        for (let i = 0; i < model.count; i++) indices.push(i);

        let col = sortColumn;
        let asc = sortAscending;

        indices.sort(function(a, b) {
            let va, vb;
            switch (col) {
                case "topic":
                    va = model.get(a).topic || "";
                    vb = model.get(b).topic || "";
                    return asc ? va.localeCompare(vb) : vb.localeCompare(va);
                case "msgs": va = model.get(a).msgCount; vb = model.get(b).msgCount; break;
                case "freq": va = model.get(a).frequency; vb = model.get(b).frequency; break;
                case "bandwidth": va = model.get(a).bandwidth; vb = model.get(b).bandwidth; break;
                case "size": va = model.get(a).size; vb = model.get(b).size; break;
                case "type":
                    va = model.get(a).type || "";
                    vb = model.get(b).type || "";
                    return asc ? va.localeCompare(vb) : vb.localeCompare(va);
                default: va = model.get(a).size; vb = model.get(b).size;
            }
            return asc ? va - vb : vb - va;
        });

        sortedIndices = indices;
    }

    // Re-sort when model count changes
    Connections {
        target: root.model
        function onCountChanged() { root._resort(); }
    }

    // Re-sort periodically to pick up value changes
    Timer {
        interval: 1000
        running: root.model && root.model.count > 0
        repeat: true
        onTriggered: root._resort()
    }

    function _toggleSort(col) {
        if (sortColumn === col) {
            sortAscending = !sortAscending;
        } else {
            sortColumn = col;
            sortAscending = col === "topic" || col === "type";
        }
        _resort();
    }

    // ========================================================================
    // Formatting Helpers
    // ========================================================================

    function formatBytes(bytes) { return Utils.formatBytes(bytes); }
    function formatBandwidth(bps) { return Utils.formatBandwidth(bps); }
    function formatFreq(hz) { return Utils.formatFreq(hz); }

    // ========================================================================
    // UI
    // ========================================================================

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 0

        // Header Row
        Rectangle {
            Layout.fillWidth: true
            height: 28
            color: palette.button
            radius: 2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 20
                spacing: 8

                // Sortable header labels
                Label {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 200
                    text: "Topic" + (root.sortColumn === "topic" ? (root.sortAscending ? " \u2191" : " \u2193") : "")
                    font.bold: true
                    ToolTip.text: "Topic name (click to sort)"
                    ToolTip.visible: headerTopicMa.containsMouse
                    MouseArea { id: headerTopicMa; anchors.fill: parent; hoverEnabled: true; onClicked: root._toggleSort("topic") }
                }

                Label {
                    Layout.preferredWidth: 60
                    text: "Msgs" + (root.sortColumn === "msgs" ? (root.sortAscending ? " \u2191" : " \u2193") : "")
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    ToolTip.text: "Total messages recorded"
                    ToolTip.visible: headerMsgsMa.containsMouse
                    MouseArea { id: headerMsgsMa; anchors.fill: parent; hoverEnabled: true; onClicked: root._toggleSort("msgs") }
                }

                Label {
                    Layout.preferredWidth: 70
                    text: "Freq" + (root.sortColumn === "freq" ? (root.sortAscending ? " \u2191" : " \u2193") : "")
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    ToolTip.text: "Message frequency (Hz)"
                    ToolTip.visible: headerFreqMa.containsMouse
                    MouseArea { id: headerFreqMa; anchors.fill: parent; hoverEnabled: true; onClicked: root._toggleSort("freq") }
                }

                Label {
                    Layout.preferredWidth: 80
                    text: "BW" + (root.sortColumn === "bandwidth" ? (root.sortAscending ? " \u2191" : " \u2193") : "")
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    ToolTip.text: "Bandwidth (bytes/sec)"
                    ToolTip.visible: headerBwMa.containsMouse
                    MouseArea { id: headerBwMa; anchors.fill: parent; hoverEnabled: true; onClicked: root._toggleSort("bandwidth") }
                }

                Label {
                    Layout.preferredWidth: 70
                    text: "Size" + (root.sortColumn === "size" ? (root.sortAscending ? " \u2191" : " \u2193") : "")
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    ToolTip.text: "Total recorded data size"
                    ToolTip.visible: headerSizeMa.containsMouse
                    MouseArea { id: headerSizeMa; anchors.fill: parent; hoverEnabled: true; onClicked: root._toggleSort("size") }
                }

                Label {
                    Layout.preferredWidth: 140
                    text: "Type" + (root.sortColumn === "type" ? (root.sortAscending ? " \u2191" : " \u2193") : "")
                    font.bold: true
                    ToolTip.text: "ROS message type"
                    ToolTip.visible: headerTypeMa.containsMouse
                    MouseArea { id: headerTypeMa; anchors.fill: parent; hoverEnabled: true; onClicked: root._toggleSort("type") }
                }
            }
        }

        // Topic List
        ListView {
            id: topicListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.sortedIndices
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true

            ScrollBar.vertical: ScrollBar {
                policy: topicListView.contentHeight > topicListView.height
                    ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }

            delegate: Rectangle {
                id: delegateRoot
                required property int index
                required property var modelData

                width: topicListView.width
                height: 28

                property var rowData: root.model ? root.model.get(modelData) : null

                color: {
                    if (!rowData) return palette.base;
                    if (rowData.publisherCount === 0) return Qt.rgba(1, 0, 0, 0.08);
                    if (rowData.msgCount === 0) return Qt.rgba(1, 1, 0, 0.08);
                    return index % 2 === 0 ? palette.base : palette.alternateBase;
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 20
                    spacing: 8

                    Label {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 200
                        text: rowData && rowData.topic !== undefined ? rowData.topic : ""
                        elide: Text.ElideMiddle
                        color: {
                            if (!rowData) return palette.text;
                            if (rowData.throttled) return Material.color(Material.Cyan, Material.Shade200);
                            if (rowData.publisherCount === 0) return Material.color(Material.Red, Material.Shade200);
                            if (rowData.msgCount === 0) return Material.color(Material.Orange, Material.Shade200);
                            return palette.text;
                        }
                    }

                    Label {
                        Layout.preferredWidth: 60
                        text: rowData && rowData.msgCount !== undefined ? String(rowData.msgCount) : ""
                        horizontalAlignment: Text.AlignRight
                    }

                    Label {
                        Layout.preferredWidth: 70
                        text: rowData && rowData.frequency !== undefined ? root.formatFreq(rowData.frequency) : ""
                        horizontalAlignment: Text.AlignRight
                        color: rowData && rowData.throttled ? Material.color(Material.Cyan, Material.Shade200) : palette.text
                    }

                    Label {
                        Layout.preferredWidth: 80
                        text: rowData && rowData.bandwidth !== undefined ? root.formatBandwidth(rowData.bandwidth) : ""
                        horizontalAlignment: Text.AlignRight
                        color: rowData && rowData.throttled ? Material.color(Material.Cyan, Material.Shade200) : palette.text
                    }

                    Label {
                        Layout.preferredWidth: 70
                        text: rowData && rowData.size !== undefined ? root.formatBytes(rowData.size) : ""
                        horizontalAlignment: Text.AlignRight
                    }

                    Label {
                        Layout.preferredWidth: 140
                        text: rowData && rowData.type !== undefined ? rowData.type : ""
                        elide: Text.ElideRight
                    }
                }
            }

            // Empty state
            Label {
                anchors.centerIn: parent
                visible: topicListView.count === 0
                text: "No topics being recorded"
                color: palette.mid
            }
        }
    }
}
