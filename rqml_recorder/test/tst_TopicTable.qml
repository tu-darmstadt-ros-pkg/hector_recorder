import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtTest
import "../qml/elements" as Elements

Item {
    id: root

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 600
    width: 800

    Utils {
        id: helpers

    }
    ListModel {
        id: topicModel

    }
    Elements.TopicTable {
        id: topicTable

        anchors.fill: parent
        model: topicModel
    }
    TestCase {
        function addSortFixture() {
            addTopic("/a", 10, 5.0, 100, 100, "std_msgs/msg/String", 1, false);
            addTopic("/c", 30, 15.0, 300, 300, "sensor_msgs/msg/Imu", 1, false);
            addTopic("/b", 20, 10.0, 200, 200, "geometry_msgs/msg/Twist", 1, false);
            tryCompare(find("topicTableListView"), "count", 3, 1000);
        }
        function addTopic(topic, msgCount, frequency, bandwidth, size, type, publisherCount, throttled) {
            topicModel.append({
                "topic": topic,
                "msgCount": msgCount,
                "frequency": frequency,
                "bandwidth": bandwidth,
                "size": size,
                "type": type,
                "publisherCount": publisherCount,
                "qosReliability": "",
                "throttled": throttled
            });
        }
        function init() {
            topicModel.clear();
            topicTable.sortColumn = "size";
            topicTable.sortAscending = false;
            tryCompare(find("topicTableListView"), "count", 0, 1000);
        }
        function rowTopics() {
            var topics = [];
            var listView = find("topicTableListView");
            for (var i = 0; i < listView.count; ++i) {
                var label = find("topicTableTopicLabel_" + i);
                topics.push(label ? label.text : null);
            }
            return topics.join(",");
        }
        function test_click_freq_header_sorts_descending() {
            addSortFixture();
            mouseClick(find("topicTableHeaderTopic"));
            mouseClick(find("topicTableHeaderFreq"));
            compare(topicTable.sortColumn, "freq");
            compare(topicTable.sortAscending, false, "Numeric columns should default to descending");
            compare(topicModel.get(topicTable.sortedIndices[0]).frequency, 15.0, "Highest frequency should be first");
            tryCompare(find("topicTableFreqLabel_0"), "text", "15.0 Hz", 1000);
        }
        function test_click_msgs_bandwidth_and_type_headers() {
            addTopic("/x", 10, 5.0, 100, 100, "a_type", 1, false);
            addTopic("/y", 20, 10.0, 200, 200, "b_type", 1, false);
            tryCompare(find("topicTableListView"), "count", 2, 1000);
            mouseClick(find("topicTableHeaderMsgs"));
            compare(topicTable.sortColumn, "msgs");
            compare(topicTable.sortAscending, false);
            tryVerify(function () {
                return rowTopics() === "/y,/x";
            }, 1000, "Highest message count should be first");
            mouseClick(find("topicTableHeaderBandwidth"));
            compare(topicTable.sortColumn, "bandwidth");
            compare(find("topicTableHeaderBandwidth").text, "BW ↓");
            tryVerify(function () {
                return rowTopics() === "/y,/x";
            }, 1000, "Highest bandwidth should be first");
            mouseClick(find("topicTableHeaderType"));
            compare(topicTable.sortColumn, "type");
            compare(topicTable.sortAscending, true, "Type should default ascending");
            compare(topicModel.get(topicTable.sortedIndices[0]).type, "a_type");
            tryCompare(find("topicTableTypeLabel_0"), "text", "a_type", 1000);
        }
        function test_click_topic_header_toggles_sort_direction() {
            addSortFixture();
            mouseClick(find("topicTableHeaderTopic"));
            compare(topicTable.sortColumn, "topic");
            compare(topicTable.sortAscending, true, "Topic should default to ascending");
            compare(find("topicTableHeaderTopic").text, "Topic ↑");
            compare(find("topicTableHeaderSize").text, "Size", "Inactive column should have no arrow");
            tryVerify(function () {
                return rowTopics() === "/a,/b,/c";
            }, 1000, "Rows should be ordered alphabetically");
            mouseClick(find("topicTableHeaderTopic"));
            compare(topicTable.sortAscending, false);
            compare(find("topicTableHeaderTopic").text, "Topic ↓");
            tryVerify(function () {
                return rowTopics() === "/c,/b,/a";
            }, 1000, "/c should be first in descending order");
        }
        function test_default_sort_is_size_descending() {
            addSortFixture();
            compare(topicTable.sortColumn, "size");
            compare(topicTable.sortAscending, false);
            compare(topicTable.sortedIndices[0], 1, "Largest size (300, /c) should be first");
            tryCompare(find("topicTableHeaderSize"), "text", "Size ↓", 1000);
            tryVerify(function () {
                return rowTopics() === "/c,/b,/a";
            }, 1000, "Rows should be ordered by size descending");
        }
        function test_dynamic_model_updates() {
            addTopic("/dynamic", 0, 0, 0, 0, "std_msgs/msg/String", 1, false);
            var listView = find("topicTableListView");
            tryCompare(listView, "count", 1, 1000);
            compare(topicTable.sortedIndices.length, 1);
            addTopic("/dynamic2", 5, 1.0, 50, 50, "std_msgs/msg/Int32", 1, false);
            tryCompare(listView, "count", 2, 1000, "Should have 2 entries after append");
            compare(topicTable.sortedIndices.length, 2);
            tryVerify(function () {
                return rowTopics() === "/dynamic2,/dynamic";
            }, 1000, "New larger topic should be sorted first");
        }
        function test_empty_model_shows_empty_state() {
            var listView = find("topicTableListView");
            var emptyLabel = find("topicTableEmptyStateLabel");
            verify(listView !== null);
            verify(emptyLabel !== null);
            compare(listView.count, 0, "Empty model should render no rows");
            compare(topicTable.sortedIndices.length, 0, "Sorted indices should be empty for empty model");
            verify(emptyLabel.visible, "Empty state label should be visible");
        }
        function test_format_helpers() {
            compare(topicTable.formatBytes(500), "500 B");
            compare(topicTable.formatBytes(1536), "1.5 KB");
            compare(topicTable.formatBytes(1572864), "1.5 MB");
            compare(topicTable.formatBytes(1610612736), "1.5 GB");
            compare(topicTable.formatBandwidth(500), "500 B/s");
            compare(topicTable.formatBandwidth(1500), "1.5 kB/s");
            compare(topicTable.formatBandwidth(1500000), "1.5 MB/s");
            compare(topicTable.formatFreq(30.0), "30.0 Hz");
            compare(topicTable.formatFreq(1500.0), "1.5 kHz");
        }
        function test_renders_rows_from_model() {
            addTopic("/camera", 100, 30.0, 15000, 500000, "sensor_msgs/msg/Image", 1, false);
            addTopic("/lidar", 50, 10.0, 5000, 200000, "sensor_msgs/msg/PointCloud2", 1, false);
            addTopic("/imu", 200, 100.0, 1000, 50000, "sensor_msgs/msg/Imu", 1, false);
            var listView = find("topicTableListView");
            tryCompare(listView, "count", 3, 1000, "Should render 3 rows");
            compare(topicTable.sortedIndices.length, 3, "Should have 3 sorted indices");
            verify(!find("topicTableEmptyStateLabel").visible, "Empty state should be hidden");
            tryCompare(find("topicTableTopicLabel_0"), "text", "/camera", 1000);
            compare(find("topicTableMsgsLabel_0").text, "100");
            compare(find("topicTableFreqLabel_0").text, "30.0 Hz");
            compare(find("topicTableBandwidthLabel_0").text, topicTable.formatBandwidth(15000));
            compare(find("topicTableSizeLabel_0").text, topicTable.formatBytes(500000));
            compare(find("topicTableTypeLabel_0").text, "sensor_msgs/msg/Image");
        }
        function test_row_labels_use_formatting() {
            addTopic("/fmt", 7, 1500.0, 1500000, 1572864, "std_msgs/msg/String", 1, false);
            tryCompare(find("topicTableListView"), "count", 1, 1000);
            tryCompare(find("topicTableSizeLabel_0"), "text", "1.5 MB", 1000);
            compare(find("topicTableBandwidthLabel_0").text, "1.5 MB/s");
            compare(find("topicTableFreqLabel_0").text, "1.5 kHz");
            compare(find("topicTableMsgsLabel_0").text, "7");
        }
        function test_special_topic_states_are_highlighted() {
            addTopic("/no_pub", 0, 0, 0, 0, "std_msgs/msg/String", 0, false);
            addTopic("/no_msgs", 0, 0, 0, 0, "std_msgs/msg/String", 1, false);
            addTopic("/throttled", 50, 10.0, 500, 500, "std_msgs/msg/String", 1, true);
            tryCompare(find("topicTableListView"), "count", 3, 1000, "Should have 3 entries");
            mouseClick(find("topicTableHeaderTopic"));
            tryVerify(function () {
                return rowTopics() === "/no_msgs,/no_pub,/throttled";
            }, 1000);
            var noMsgsRow = find("topicTableRow_0");
            var noPubRow = find("topicTableRow_1");
            verify(Qt.colorEqual(noPubRow.color, Qt.rgba(1, 0, 0, 0.08)), "Row without publishers should be tinted red");
            verify(Qt.colorEqual(noMsgsRow.color, Qt.rgba(1, 1, 0, 0.08)), "Row without messages should be tinted yellow");
            verify(Qt.colorEqual(find("topicTableTopicLabel_1").color, Material.color(Material.Red, Material.Shade200)), "Topic without publishers should be red");
            verify(Qt.colorEqual(find("topicTableTopicLabel_0").color, Material.color(Material.Orange, Material.Shade200)), "Topic without messages should be orange");
            var cyan = Material.color(Material.Cyan, Material.Shade200);
            verify(Qt.colorEqual(find("topicTableTopicLabel_2").color, cyan), "Throttled topic should be cyan");
            verify(Qt.colorEqual(find("topicTableFreqLabel_2").color, cyan), "Throttled frequency should be cyan");
            verify(Qt.colorEqual(find("topicTableBandwidthLabel_2").color, cyan), "Throttled bandwidth should be cyan");
        }

        name: "TopicTableTest"
        when: windowShown
    }
}
