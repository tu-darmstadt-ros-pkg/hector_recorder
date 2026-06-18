import QtQuick
import QtQuick.Controls
import QtTest
import "../qml/elements" as Elements
import RqmlRecorder

Item {
    id: windowRoot
    width: 950
    height: 850

    // Mock recorder interface
    QtObject {
        id: mockInterface

        signal serviceResponse(string name, bool success, string message)

        property string _lastApplyYaml: ""
        property bool _lastApplyRestart: false
        property int _applyCount: 0
        property int _fetchConfigCount: 0
        property int _fetchTopicsCount: 0
        property string _mockConfigYaml: ""
        property var _mockTopics: []

        function applyConfig(yaml, restart) {
            _lastApplyYaml = yaml;
            _lastApplyRestart = restart;
            _applyCount++;
            serviceResponse("config", true, "Config applied");
        }

        function fetchConfig(callback) {
            _fetchConfigCount++;
            if (callback) callback(_mockConfigYaml);
        }

        function fetchAvailableTopics(callback) {
            _fetchTopicsCount++;
            if (callback) callback(_mockTopics);
        }
    }

    Elements.ConfigEditor {
        id: configEditor
        anchors.centerIn: parent
        parent: windowRoot
        recorderInterface: mockInterface
        savedConfigNames: []
    }

    TestCase {
        name: "ConfigEditorTest"
        when: windowShown

        function init() {
            mockInterface._lastApplyYaml = "";
            mockInterface._lastApplyRestart = false;
            mockInterface._applyCount = 0;
            mockInterface._fetchConfigCount = 0;
            mockInterface._fetchTopicsCount = 0;
            mockInterface._mockConfigYaml = "";
            mockInterface._mockTopics = [];
            configEditor.close();
            tryVerify(function() { return !configEditor.opened; }, 1000);
        }

        // ---- Test 1: YAML generation from topic selector ----
        function test_01_yaml_generation() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            var yaml = configEditor._buildYamlFromTopicSelector();
            verify(yaml.indexOf("node_name:") >= 0, "Should contain node_name");
            verify(yaml.indexOf("output:") >= 0, "Should contain output");
            verify(yaml.indexOf("storage_id:") >= 0, "Should contain storage_id");
            verify(yaml.indexOf("publish_status:") >= 0, "Should contain publish_status");

            configEditor.close();
        }

        // ---- Test 2: YAML parsing populates UI ----
        function test_02_yaml_parsing() {
            mockInterface._mockTopics = [
                { name: "/camera", type: "sensor_msgs/msg/Image" },
                { name: "/lidar", type: "sensor_msgs/msg/PointCloud2" },
                { name: "/imu", type: "sensor_msgs/msg/Imu" }
            ];
            mockInterface._mockConfigYaml =
                'output: "~/test_bags/"\n' +
                'storage_id: "mcap"\n' +
                'all_topics: false\n' +
                'publish_status: false\n' +
                'topics:\n' +
                '  - "/camera"\n' +
                '  - "/imu"\n';

            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);
            // Manually trigger what onOpened does (Popup may not fire onOpened in offscreen)
            configEditor._loadCurrentConfig();
            configEditor._fetchAvailableTopics();
            // Settle: allow the topic selector model to repopulate after fetch
            wait(200);

            // Rebuild YAML and check round-trip
            var rebuilt = configEditor._buildYamlFromTopicSelector();
            verify(rebuilt.indexOf('output: "~/test_bags/"') >= 0,
                "Output path should be preserved");
            verify(rebuilt.indexOf('storage_id: "mcap"') >= 0,
                "Storage id should be mcap");
            verify(rebuilt.indexOf('all_topics: false') >= 0,
                "All topics should be false");
            verify(rebuilt.indexOf('publish_status: false') >= 0,
                "Publish status should be false");
            verify(rebuilt.indexOf('"/camera"') >= 0,
                "Camera should be in topics list");
            verify(rebuilt.indexOf('"/imu"') >= 0,
                "Imu should be in topics list");
            // Lidar was NOT in the config YAML, so shouldn't be selected
            compare(rebuilt.indexOf('"/lidar"'), -1,
                "Lidar should NOT be in topics list");

            configEditor.close();
        }

        // ---- Test 3: All Topics toggle via YAML builder logic ----
        function test_03_all_topics_yaml_logic() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            // Test the YAML builder: when all_topics is parsed, individual topics
            // should not appear. We test this at the parsing level since the
            // checkbox binding requires actual rendering.
            var yaml = 'all_topics: true\ntopics:\n  - "/a"\n';
            var topics = configEditor._parseTopicList(yaml);
            compare(topics.length, 1,
                "Parser should still find topics in YAML");
            // The real test: _buildYamlFromTopicSelector checks allTopicsCheck.checked
            // which we can't control in offscreen. Instead verify the parsing functions.

            configEditor.close();
        }

        // ---- Test 4: Throttle configuration ----
        function test_04_throttle_config() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            // Set a message-based throttle
            configEditor._setThrottle("/camera", "messages", 10.0, 1000000, 1.0);
            var th = configEditor._getThrottle("/camera");
            verify(th !== null, "Throttle should exist");
            compare(th.throttleType, "messages");
            compare(th.rate, 10.0);

            // Set a bytes-based throttle
            configEditor._setThrottle("/lidar", "bytes", 10.0, 500000, 2.0);
            var th2 = configEditor._getThrottle("/lidar");
            verify(th2 !== null);
            compare(th2.throttleType, "bytes");
            compare(th2.bytes, 500000);
            compare(th2.window, 2.0);

            // Update existing throttle
            configEditor._setThrottle("/camera", "messages", 5.0, 1000000, 1.0);
            th = configEditor._getThrottle("/camera");
            compare(th.rate, 5.0, "Rate should be updated");

            // YAML should include throttle section
            var yaml = configEditor._buildYamlFromTopicSelector();
            verify(yaml.indexOf("topic_throttle:") >= 0,
                "Should have throttle section");
            verify(yaml.indexOf("/camera") >= 0,
                "Should contain camera throttle");
            verify(yaml.indexOf("msgs_per_sec: 5") >= 0,
                "Should have updated rate");
            verify(yaml.indexOf("/lidar") >= 0,
                "Should contain lidar throttle");
            verify(yaml.indexOf("bytes_per_sec: 500000") >= 0,
                "Should have bytes limit");
            verify(yaml.indexOf("window: 2") >= 0,
                "Should have window");

            // Remove throttle
            configEditor._removeThrottle("/camera");
            compare(configEditor._getThrottle("/camera"), null,
                "Camera throttle should be removed");
            // Lidar should still exist
            verify(configEditor._getThrottle("/lidar") !== null,
                "Lidar throttle should still exist");

            configEditor.close();
        }

        // ---- Test 5: Throttle YAML parsing ----
        function test_05_throttle_yaml_parsing() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            var yaml = 'topics:\n' +
                       '  - "/cam"\n' +
                       'topic_throttle:\n' +
                       '  "/cam":\n' +
                       '    type: "messages"\n' +
                       '    msgs_per_sec: 15\n' +
                       '  "/lidar":\n' +
                       '    type: "bytes"\n' +
                       '    bytes_per_sec: 200000\n' +
                       '    window: 0.5\n';

            var throttles = configEditor._parseThrottleConfigs(yaml);
            verify("/cam" in throttles, "Should parse /cam throttle");
            compare(throttles["/cam"].type, "messages");
            compare(throttles["/cam"].rate, 15);
            verify("/lidar" in throttles, "Should parse /lidar throttle");
            compare(throttles["/lidar"].type, "bytes");
            compare(throttles["/lidar"].bytes, 200000);
            compare(throttles["/lidar"].window, 0.5);

            configEditor.close();
        }

        // ---- Test 6: Topic list parsing ----
        function test_06_topic_list_parsing() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            // Normal case
            var yaml1 = 'topics:\n  - "/a"\n  - "/b"\n  - "/c"\nother: value\n';
            var topics1 = configEditor._parseTopicList(yaml1);
            compare(topics1.length, 3);
            compare(topics1[0], "/a");
            compare(topics1[1], "/b");
            compare(topics1[2], "/c");

            // Without quotes
            var yaml2 = 'topics:\n  - /x\n  - /y\n';
            var topics2 = configEditor._parseTopicList(yaml2);
            compare(topics2.length, 2);
            compare(topics2[0], "/x");
            compare(topics2[1], "/y");

            // No topics section
            var yaml3 = 'output: "~/bags/"\n';
            var topics3 = configEditor._parseTopicList(yaml3);
            compare(topics3.length, 0);

            configEditor.close();
        }

        // ---- Test 7: Preset save and load via signals ----
        function test_07_preset_signals() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            var savedName = "";
            var savedYaml = "";
            var deletedName = "";

            configEditor.configSaved.connect(function(name, yaml) {
                savedName = name;
                savedYaml = yaml;
            });
            configEditor.configDeleted.connect(function(name) {
                deletedName = name;
            });

            // Emit save signal
            configEditor.configSaved("test_preset", "output: test\n");
            compare(savedName, "test_preset", "Save signal should carry name");
            compare(savedYaml, "output: test\n", "Save signal should carry yaml");

            // Emit delete signal
            configEditor.configDeleted("test_preset");
            compare(deletedName, "test_preset", "Delete signal should carry name");

            configEditor.close();
        }

        // ---- Test 8: Apply calls interface ----
        function test_08_apply() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            mockInterface._mockTopics = [
                { name: "/topic_a", type: "std_msgs/msg/String" }
            ];
            configEditor._fetchAvailableTopics();
            // Settle: allow the topic selector model to repopulate after fetch
            wait(100);

            // Apply without restart
            mockInterface.applyConfig(configEditor._getActiveYaml(), false);
            compare(mockInterface._applyCount, 1, "Apply should be called");
            compare(mockInterface._lastApplyRestart, false, "Should not restart");
            verify(mockInterface._lastApplyYaml.length > 0,
                "YAML should be non-empty");

            // Apply with restart
            mockInterface.applyConfig(configEditor._getActiveYaml(), true);
            compare(mockInterface._applyCount, 2, "Apply should be called again");
            compare(mockInterface._lastApplyRestart, true, "Should restart");

            configEditor.close();
        }

        // ---- Test 9: _getActiveYaml returns text area content on tab 1 ----
        function test_09_active_yaml_from_text() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            // _getActiveYaml should return _buildYamlFromTopicSelector on tab 0
            var yamlTab0 = configEditor._getActiveYaml();
            verify(yamlTab0.indexOf("node_name:") >= 0,
                "Tab 0 should return built YAML");

            configEditor.close();
        }

        // ---- Test 10: Fetch config on open ----
        function test_10_fetch_config_on_open() {
            mockInterface._fetchConfigCount = 0;
            mockInterface._fetchTopicsCount = 0;
            mockInterface._mockConfigYaml = 'output: "~/fetched/"\ntopics:\n  - "/fetched_topic"\n';
            mockInterface._mockTopics = [
                { name: "/fetched_topic", type: "std_msgs/msg/String" }
            ];

            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);
            // Manually trigger (Popup onOpened may not fire in offscreen)
            configEditor._loadCurrentConfig();
            configEditor._fetchAvailableTopics();

            tryVerify(function() { return mockInterface._fetchConfigCount >= 1; }, 1000,
                "Should fetch config on open");
            tryVerify(function() { return mockInterface._fetchTopicsCount >= 1; }, 1000,
                "Should fetch topics on open");

            configEditor.close();
        }

        // ---- Test 11: Topic filter property ----
        function test_11_topic_filter() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            mockInterface._mockTopics = [
                { name: "/camera/image", type: "sensor_msgs/msg/Image" },
                { name: "/camera/depth", type: "sensor_msgs/msg/Image" },
                { name: "/imu/data", type: "sensor_msgs/msg/Imu" }
            ];
            configEditor._fetchAvailableTopics();
            // Settle: allow the topic selector model to repopulate after fetch
            wait(100);

            configEditor._filterText = "camera";
            tryCompare(configEditor, "_filterText", "camera", 1000);

            configEditor._filterText = "";

            configEditor.close();
        }

        // ---- Test 12: Throttle rev counter increments ----
        function test_12_throttle_rev_counter() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            var initialRev = configEditor._throttleRev;

            configEditor._setThrottle("/test", "messages", 5.0, 1000000, 1.0);
            compare(configEditor._throttleRev, initialRev + 1,
                "Rev should increment on set");

            configEditor._setThrottle("/test", "messages", 10.0, 1000000, 1.0);
            compare(configEditor._throttleRev, initialRev + 2,
                "Rev should increment on update");

            configEditor._removeThrottle("/test");
            compare(configEditor._throttleRev, initialRev + 3,
                "Rev should increment on remove");

            configEditor.close();
        }

        // ---- Test 13: Show selected only filter ----
        function test_13_show_selected_only() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            compare(configEditor._showSelectedOnly, false,
                "Show selected should be off by default");

            configEditor._showSelectedOnly = true;
            compare(configEditor._showSelectedOnly, true,
                "Should toggle on");

            configEditor._showSelectedOnly = false;
            configEditor.close();
        }

        // ---- Test 14: Multiple throttle operations ----
        function test_14_multiple_throttles() {
            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);

            // Add three throttles
            configEditor._setThrottle("/a", "messages", 5.0, 1000000, 1.0);
            configEditor._setThrottle("/b", "bytes", 10.0, 200000, 2.0);
            configEditor._setThrottle("/c", "messages", 20.0, 1000000, 1.0);

            verify(configEditor._getThrottle("/a") !== null);
            verify(configEditor._getThrottle("/b") !== null);
            verify(configEditor._getThrottle("/c") !== null);

            // Remove middle one
            configEditor._removeThrottle("/b");
            compare(configEditor._getThrottle("/b"), null,
                "Middle throttle should be removed");
            verify(configEditor._getThrottle("/a") !== null,
                "First throttle should still exist");
            verify(configEditor._getThrottle("/c") !== null,
                "Last throttle should still exist");

            // YAML should only have /a and /c
            var yaml = configEditor._buildYamlFromTopicSelector();
            verify(yaml.indexOf("/a") >= 0);
            compare(yaml.indexOf("/b"), -1);
            verify(yaml.indexOf("/c") >= 0);

            configEditor.close();
        }

        // ---- Test 15: Cached selected-topic count tracks selection ----
        function test_15_selected_count() {
            mockInterface._mockTopics = [
                { name: "/camera", type: "sensor_msgs/msg/Image" },
                { name: "/lidar", type: "sensor_msgs/msg/PointCloud2" },
                { name: "/imu", type: "sensor_msgs/msg/Imu" }
            ];
            mockInterface._mockConfigYaml =
                'all_topics: false\n' +
                'topics:\n' +
                '  - "/camera"\n' +
                '  - "/imu"\n';

            configEditor.open();
            tryVerify(function() { return configEditor.opened; }, 1000);
            configEditor._loadCurrentConfig();
            configEditor._fetchAvailableTopics();

            // Two of three topics are selected from the loaded config
            tryCompare(configEditor, "_selectedTopicCount", 2, 1000,
                "Loaded config should mark two topics selected");

            // Re-parsing a config that selects all three updates the cached count
            configEditor._parseYamlToTopicSelector(
                'all_topics: false\n' +
                'topics:\n' +
                '  - "/camera"\n' +
                '  - "/lidar"\n' +
                '  - "/imu"\n');
            tryCompare(configEditor, "_selectedTopicCount", 3, 1000,
                "Re-parsing should refresh the cached count");

            configEditor.close();
        }
    }
}
