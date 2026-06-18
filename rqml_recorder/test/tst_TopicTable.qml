import QtQuick
import QtQuick.Controls
import QtTest
import "../qml/elements" as Elements

Item {
    id: windowRoot
    width: 800
    height: 600

    ListModel {
        id: topicModel
    }

    Elements.TopicTable {
        id: topicTable
        anchors.fill: parent
        model: topicModel
    }

    TestCase {
        name: "TopicTableTest"
        when: windowShown

        function init() {
            topicModel.clear();
            topicTable.sortColumn = "size";
            topicTable.sortAscending = false;
        }

        // ---- Test 1: Renders rows from model ----
        function test_01_renders_rows() {
            topicModel.append({
                topic: "/camera", msgCount: 100, frequency: 30.0,
                bandwidth: 15000, size: 500000, type: "sensor_msgs/msg/Image",
                publisherCount: 1, qosReliability: "reliable", throttled: false
            });
            topicModel.append({
                topic: "/lidar", msgCount: 50, frequency: 10.0,
                bandwidth: 5000, size: 200000, type: "sensor_msgs/msg/PointCloud2",
                publisherCount: 1, qosReliability: "best_effort", throttled: false
            });
            topicModel.append({
                topic: "/imu", msgCount: 200, frequency: 100.0,
                bandwidth: 1000, size: 50000, type: "sensor_msgs/msg/Imu",
                publisherCount: 1, qosReliability: "reliable", throttled: false
            });

            tryVerify(function() { return topicTable.sortedIndices.length === 3; }, 1000,
                "Should have 3 sorted indices");
        }

        // ---- Test 2: Sorting by column ----
        function test_02_sorting() {
            topicModel.append({
                topic: "/a", msgCount: 10, frequency: 5.0,
                bandwidth: 100, size: 100, type: "std_msgs/msg/String",
                publisherCount: 1, qosReliability: "", throttled: false
            });
            topicModel.append({
                topic: "/c", msgCount: 30, frequency: 15.0,
                bandwidth: 300, size: 300, type: "sensor_msgs/msg/Imu",
                publisherCount: 1, qosReliability: "", throttled: false
            });
            topicModel.append({
                topic: "/b", msgCount: 20, frequency: 10.0,
                bandwidth: 200, size: 200, type: "geometry_msgs/msg/Twist",
                publisherCount: 1, qosReliability: "", throttled: false
            });
            tryVerify(function() { return topicTable.sortedIndices.length === 3; }, 1000);

            // Default: size descending
            compare(topicTable.sortColumn, "size");
            compare(topicTable.sortAscending, false);
            compare(topicTable.sortedIndices[0], 1,
                "Largest size (300, /c) should be first");

            // Toggle to topic ascending
            topicTable._toggleSort("topic");
            compare(topicTable.sortColumn, "topic");
            compare(topicTable.sortAscending, true, "Topic should default to ascending");
            compare(topicModel.get(topicTable.sortedIndices[0]).topic, "/a",
                "First should be /a alphabetically");
            compare(topicModel.get(topicTable.sortedIndices[1]).topic, "/b",
                "Second should be /b");
            compare(topicModel.get(topicTable.sortedIndices[2]).topic, "/c",
                "Third should be /c");

            // Toggle topic to descending
            topicTable._toggleSort("topic");
            compare(topicTable.sortAscending, false);
            compare(topicModel.get(topicTable.sortedIndices[0]).topic, "/c",
                "First should be /c in descending");

            // Sort by frequency
            topicTable._toggleSort("freq");
            compare(topicTable.sortColumn, "freq");
            // Numeric columns default to descending
            compare(topicTable.sortAscending, false);
            compare(topicModel.get(topicTable.sortedIndices[0]).frequency, 15.0,
                "Highest frequency should be first");
        }

        // ---- Test 3: Formatting ----
        function test_03_formatting() {
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

        // ---- Test 4: Empty model ----
        function test_04_empty_model() {
            topicModel.clear();
            tryVerify(function() { return topicTable.sortedIndices.length === 0; }, 1000,
                "Sorted indices should be empty for empty model");
        }

        // ---- Test 5: Sort by all columns ----
        function test_05_all_sort_columns() {
            topicModel.append({
                topic: "/x", msgCount: 10, frequency: 5.0,
                bandwidth: 100, size: 100, type: "a_type",
                publisherCount: 1, qosReliability: "", throttled: false
            });
            topicModel.append({
                topic: "/y", msgCount: 20, frequency: 10.0,
                bandwidth: 200, size: 200, type: "b_type",
                publisherCount: 1, qosReliability: "", throttled: false
            });
            tryVerify(function() { return topicTable.sortedIndices.length === 2; }, 1000);

            // Sort by msgs
            topicTable._toggleSort("msgs");
            compare(topicTable.sortColumn, "msgs");

            // Sort by bandwidth
            topicTable._toggleSort("bandwidth");
            compare(topicTable.sortColumn, "bandwidth");

            // Sort by type (text column defaults ascending)
            topicTable._toggleSort("type");
            compare(topicTable.sortColumn, "type");
            compare(topicTable.sortAscending, true,
                "Type should default ascending");
            compare(topicModel.get(topicTable.sortedIndices[0]).type, "a_type");
        }

        // ---- Test 6: Model with special states ----
        function test_06_special_topic_states() {
            topicModel.clear();
            // No publishers
            topicModel.append({
                topic: "/no_pub", msgCount: 0, frequency: 0,
                bandwidth: 0, size: 0, type: "std_msgs/msg/String",
                publisherCount: 0, qosReliability: "", throttled: false
            });
            // No messages yet
            topicModel.append({
                topic: "/no_msgs", msgCount: 0, frequency: 0,
                bandwidth: 0, size: 0, type: "std_msgs/msg/String",
                publisherCount: 1, qosReliability: "", throttled: false
            });
            // Throttled
            topicModel.append({
                topic: "/throttled", msgCount: 50, frequency: 10.0,
                bandwidth: 500, size: 500, type: "std_msgs/msg/String",
                publisherCount: 1, qosReliability: "", throttled: true
            });

            tryVerify(function() { return topicTable.sortedIndices.length === 3; }, 1000,
                "Should have 3 entries");

            // Verify the data is correct in the model
            compare(topicModel.get(0).publisherCount, 0,
                "First topic should have no publishers");
            compare(topicModel.get(1).publisherCount, 1,
                "Second topic should have publishers");
            compare(topicModel.get(1).msgCount, 0,
                "Second topic should have no messages");
            compare(topicModel.get(2).throttled, true,
                "Third topic should be throttled");
        }

        // ---- Test 7: Dynamic model updates ----
        function test_07_dynamic_updates() {
            topicModel.clear();
            topicModel.append({
                topic: "/dynamic", msgCount: 0, frequency: 0,
                bandwidth: 0, size: 0, type: "std_msgs/msg/String",
                publisherCount: 1, qosReliability: "", throttled: false
            });
            tryVerify(function() { return topicTable.sortedIndices.length === 1; }, 1000);

            // Add another topic
            topicModel.append({
                topic: "/dynamic2", msgCount: 5, frequency: 1.0,
                bandwidth: 50, size: 50, type: "std_msgs/msg/Int32",
                publisherCount: 1, qosReliability: "", throttled: false
            });
            tryVerify(function() { return topicTable.sortedIndices.length === 2; }, 1000,
                "Should have 2 entries after append");
        }
    }
}
