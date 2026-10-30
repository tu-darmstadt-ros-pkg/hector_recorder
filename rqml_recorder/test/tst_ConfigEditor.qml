import QtQuick
import QtQuick.Controls
import QtTest
import "../qml/elements" as Elements
import RQml.Recorder

Item {
    id: root

    property var editor: editorLoader.item ? editorLoader.item.editor : null
    property var savedConfigNames: []

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 850
    width: 950

    // Mock recorder interface
    QtObject {
        id: mockInterface

        property int applyCount: 0
        property int fetchConfigCount: 0
        property int fetchTopicsCount: 0
        property bool lastApplyRestart: false
        property string lastApplyYaml: ""
        property string mockConfigYaml: ""
        property var mockTopics: []

        signal serviceResponse(string name, bool success, string message)

        function applyConfig(yaml, restart) {
            lastApplyYaml = yaml;
            lastApplyRestart = restart;
            applyCount++;
            serviceResponse("config", true, "Config applied");
        }
        function fetchAvailableTopics(callback) {
            fetchTopicsCount++;
            if (callback)
                callback(mockTopics);
        }
        function fetchConfig(callback) {
            fetchConfigCount++;
            if (callback)
                callback(mockConfigYaml);
        }
        function reset() {
            applyCount = 0;
            fetchConfigCount = 0;
            fetchTopicsCount = 0;
            lastApplyYaml = "";
            lastApplyRestart = false;
            mockConfigYaml = "";
            mockTopics = [];
        }
    }
    Utils {
        id: helpers

    }
    Loader {
        id: editorLoader

        function reload() {
            sourceComponent = null;
            sourceComponent = editorComponent;
        }

        anchors.fill: parent
    }
    Component {
        id: editorComponent

        Item {
            property alias editor: configEditor

            anchors.fill: parent

            Elements.ConfigEditor {
                id: configEditor

                recorderInterface: mockInterface
                savedConfigNames: root.savedConfigNames
            }
        }
    }
    SignalSpy {
        id: savedSpy

        signalName: "configSaved"
        target: root.editor
    }
    SignalSpy {
        id: deletedSpy

        signalName: "configDeleted"
        target: root.editor
    }
    TestCase {
        function checkboxStates() {
            var listView = find("configEditorTopicListView");
            var states = [];
            for (var i = 0; i < listView.count; ++i)
                states.push(find("configEditorTopicCheckbox_" + i).checked);
            return states.join(",");
        }
        function clickTab(objectName) {
            var tab = find(objectName);
            verify(tab !== null, objectName + " should exist");
            mouseClick(tab);
            tryCompare(find("configEditorTabBar"), "currentIndex", objectName === "configEditorYamlEditorTab" ? 1 : 0, 1000);
        }
        function findReady(name) {
            // Delegates and popup contents are created asynchronously; wait until the item exists
            var item = null;
            tryVerify(function () {
                item = find(name);
                return item !== null;
            }, 1000, name + " should exist");
            return item;
        }
        function init() {
            mockInterface.reset();
            PresetStore.reset();
            root.savedConfigNames = [];
            editorLoader.reload();
            tryVerify(function () {
                return editorLoader.status === Loader.Ready && root.editor !== null;
            }, 2000, "Editor should be created");
            savedSpy.clear();
            deletedSpy.clear();
        }
        function openEditor(expectedTopicCount) {
            editor.open();
            tryCompare(editor, "opened", true, 1000, "Editor should open");
            tryCompare(findReady("configEditorTopicListView"), "count", expectedTopicCount || 0, 1000, "Topic list should be populated on open");
        }
        function openThrottlePopup(row) {
            var badge = findReady("configEditorThrottleBadge_" + row);
            verify(badge !== null, "Throttle badge should exist");
            mouseClick(badge);
            var popup = findReady("configEditorThrottlePopup");
            tryCompare(popup, "opened", true, 1000, "Throttle popup should open");
            return popup;
        }
        function setThrottle(row, typeIndex, value, windowValue) {
            var popup = openThrottlePopup(row);
            findReady("configEditorThrottleTypeCombo").currentIndex = typeIndex;
            findReady("configEditorThrottleValueField").text = value;
            if (windowValue !== undefined)
                findReady("configEditorThrottleWindowField").text = windowValue;
            mouseClick(findReady("configEditorThrottleOkButton"));
            tryCompare(popup, "visible", false, 1000, "Throttle popup should close on OK");
        }
        function test_all_topics_check_clears_selection() {
            mockInterface.mockTopics = [
                {
                    "name": "/a",
                    "type": "std_msgs/msg/String"
                },
                {
                    "name": "/b",
                    "type": "std_msgs/msg/String"
                }
            ];
            mockInterface.mockConfigYaml = 'all_topics: false\ntopics:\n  - "/a"\n  - "/b"\n';
            openEditor(2);
            compare(checkboxStates(), "true,true");
            mouseClick(findReady("configEditorAllTopicsCheck"));
            compare(findReady("configEditorAllTopicsCheck").checked, true);
            compare(checkboxStates(), "false,false", "Checking All Topics should deselect individual topics");
        }
        function test_all_topics_config_omits_individual_topics() {
            mockInterface.mockTopics = [
                {
                    "name": "/a",
                    "type": "std_msgs/msg/String"
                }
            ];
            mockInterface.mockConfigYaml = 'all_topics: true\ntopics:\n  - "/a"\n';
            openEditor(1);
            var allTopicsCheck = findReady("configEditorAllTopicsCheck");
            compare(allTopicsCheck.checked, true, "all_topics: true should check All Topics");
            compare(findReady("configEditorTopicCheckbox_0").checked, true, "Parser should still find topics in YAML");
            compare(findReady("configEditorTopicCheckbox_0").enabled, false, "Individual checkboxes are disabled with All Topics");
            compare(findReady("configEditorClearAllButton").enabled, false);
            compare(findReady("configEditorSelectionSummaryLabel").text, "All topics selected");
            var yaml = yamlEditorText();
            verify(yaml.indexOf("all_topics: true") >= 0, "YAML should contain all_topics: true");
            compare(yaml.indexOf('"/a"'), -1, "Individual topics should be omitted with All Topics");
        }
        function test_apply_calls_interface() {
            mockInterface.mockTopics = [
                {
                    "name": "/topic_a",
                    "type": "std_msgs/msg/String"
                }
            ];
            openEditor(1);

            // Apply without restart
            mouseClick(findReady("configEditorApplyButton"));
            compare(mockInterface.applyCount, 1, "Apply should be called");
            compare(mockInterface.lastApplyRestart, false, "Should not restart");
            verify(mockInterface.lastApplyYaml.indexOf("node_name:") >= 0, "Topic selector tab should apply built YAML");
            tryCompare(editor, "visible", false, 1000, "Apply should close the editor");
            compare(findReady("configEditorStatusLabel").text, "✓ Config applied", "Service response should be shown");

            // Apply with restart
            openEditor(1);
            mouseClick(findReady("configEditorApplyRestartButton"));
            compare(mockInterface.applyCount, 2, "Apply should be called again");
            compare(mockInterface.lastApplyRestart, true, "Should restart");
            tryCompare(editor, "visible", false, 1000);
        }
        function test_apply_uses_yaml_editor_text() {
            openEditor(0);
            clickTab("configEditorYamlEditorTab");
            findReady("configEditorConfigTextArea").text = "custom: yaml\n";
            mouseClick(findReady("configEditorApplyButton"));
            compare(mockInterface.lastApplyYaml, "custom: yaml\n", "YAML tab should apply the text area content");
        }
        function test_clear_all_deselects_topics() {
            mockInterface.mockTopics = [
                {
                    "name": "/a",
                    "type": "std_msgs/msg/String"
                },
                {
                    "name": "/b",
                    "type": "std_msgs/msg/String"
                }
            ];
            mockInterface.mockConfigYaml = 'all_topics: false\ntopics:\n  - "/a"\n  - "/b"\n';
            openEditor(2);
            compare(findReady("configEditorSelectionSummaryLabel").text, "2 of 2 topics selected");
            mouseClick(findReady("configEditorClearAllButton"));
            compare(checkboxStates(), "false,false");
            compare(findReady("configEditorSelectionSummaryLabel").text, "0 of 2 topics selected");
        }
        function test_close_button_closes_editor() {
            openEditor(0);
            mouseClick(findReady("configEditorCloseButton"));
            tryCompare(editor, "visible", false, 1000);
        }
        function test_default_yaml_contains_required_keys() {
            openEditor(0);
            verify(findReady("configEditorTopicEmptyStateLabel").visible, "Empty state should be shown without topics");
            var yaml = yamlEditorText();
            verify(yaml.indexOf("node_name:") >= 0, "Should contain node_name");
            verify(yaml.indexOf("output:") >= 0, "Should contain output");
            verify(yaml.indexOf("storage_id:") >= 0, "Should contain storage_id");
            verify(yaml.indexOf("publish_status:") >= 0, "Should contain publish_status");
        }
        function test_delete_preset_emits_signal() {
            root.savedConfigNames = ["test_preset"];
            openEditor(0);
            var presetCombo = findReady("configEditorPresetCombo");
            var deleteButton = findReady("configEditorDeleteButton");
            compare(presetCombo.count, 2, "Combo should list (Current) and the preset");
            compare(presetCombo.currentIndex, 0);
            compare(deleteButton.enabled, false, "(Current) cannot be deleted");
            presetCombo.currentIndex = 1;
            tryCompare(deleteButton, "enabled", true, 1000);
            mouseClick(deleteButton);
            compare(deletedSpy.count, 1, "configDeleted should be emitted");
            compare(deletedSpy.signalArguments[0][0], "test_preset", "Delete signal should carry name");
        }
        function test_load_saved_preset_applies_yaml() {
            mockInterface.mockTopics = [
                {
                    "name": "/a",
                    "type": "std_msgs/msg/String"
                },
                {
                    "name": "/b",
                    "type": "std_msgs/msg/String"
                }
            ];
            mockInterface.mockConfigYaml = 'output: "~/current/"\ntopics:\n  - "/a"\n';
            var presetYaml = 'output: "~/preset/"\n' + 'storage_id: "mcap"\n' + 'all_topics: false\n' + 'topics:\n' + '  - "/b"\n' + 'topic_throttle:\n' + '  "/b":\n' + '    type: "messages"\n' + '    msgs_per_sec: 7\n';
            verify(PresetStore.save("test_preset", presetYaml), "Preset should be saved");
            root.savedConfigNames = PresetStore.presetNames;
            openEditor(2);
            compare(checkboxStates(), "true,false", "Current config should be loaded on open");
            var presetCombo = findReady("configEditorPresetCombo");
            compare(presetCombo.count, 2, "Combo should list (Current) and the preset");
            presetCombo.currentIndex = 1;
            compare(presetCombo.currentText, "test_preset");
            mouseClick(findReady("configEditorLoadButton"));
            compare(checkboxStates(), "false,true", "Preset topics should be selected");
            compare(findReady("configEditorOutputField").text, "~/preset/");
            compare(findReady("configEditorStorageCombo").currentText, "mcap");
            tryCompare(findReady("configEditorThrottleBadgeLabel_1"), "text", "7 msg/s", 1000, "Preset throttle should be applied");
            compare(findReady("configEditorSelectionSummaryLabel").text, "1 of 2 topics selected, 1 throttled");
            var yaml = yamlEditorText();
            verify(yaml.indexOf('output: "~/preset/"') >= 0, "YAML tab should reflect the preset output");
            verify(yaml.indexOf('storage_id: "mcap"') >= 0, "YAML tab should reflect the preset storage");
            verify(yaml.indexOf('  - "/b"') >= 0, "YAML tab should contain the preset topic");
            compare(yaml.indexOf('  - "/a"'), -1, "YAML tab should not contain the previous topic");
            verify(yaml.indexOf("msgs_per_sec: 7") >= 0, "YAML tab should contain the preset throttle");
        }
        function test_loaded_config_populates_ui() {
            mockInterface.mockTopics = [
                {
                    "name": "/camera",
                    "type": "sensor_msgs/msg/Image"
                },
                {
                    "name": "/lidar",
                    "type": "sensor_msgs/msg/PointCloud2"
                },
                {
                    "name": "/imu",
                    "type": "sensor_msgs/msg/Imu"
                }
            ];
            mockInterface.mockConfigYaml = 'output: "~/test_bags/"\n' + 'storage_id: "mcap"\n' + 'all_topics: false\n' + 'publish_status: false\n' + 'topics:\n' + '  - "/camera"\n' + '  - "/imu"\n';
            openEditor(3);
            compare(findReady("configEditorOutputField").text, "~/test_bags/");
            compare(findReady("configEditorStorageCombo").currentText, "mcap");
            compare(findReady("configEditorAllTopicsCheck").checked, false);
            compare(findReady("configEditorPublishStatusCheck").checked, false);
            compare(checkboxStates(), "true,false,true", "Only /camera and /imu should be selected");

            // Rebuild YAML and check round-trip
            var rebuilt = yamlEditorText();
            verify(rebuilt.indexOf('output: "~/test_bags/"') >= 0, "Output path should be preserved");
            verify(rebuilt.indexOf('storage_id: "mcap"') >= 0, "Storage id should be mcap");
            verify(rebuilt.indexOf('all_topics: false') >= 0, "All topics should be false");
            verify(rebuilt.indexOf('publish_status: false') >= 0, "Publish status should be false");
            verify(rebuilt.indexOf('"/camera"') >= 0, "Camera should be in topics list");
            verify(rebuilt.indexOf('"/imu"') >= 0, "Imu should be in topics list");
            compare(rebuilt.indexOf('"/lidar"'), -1, "Lidar should NOT be in topics list");
        }
        function test_message_throttle_add_update_and_remove() {
            mockInterface.mockTopics = [
                {
                    "name": "/camera",
                    "type": "sensor_msgs/msg/Image"
                },
                {
                    "name": "/lidar",
                    "type": "sensor_msgs/msg/PointCloud2"
                }
            ];
            openEditor(2);
            compare(findReady("configEditorThrottleBadgeLabel_0").text, "⏱", "Unthrottled topic should show stopwatch");

            // Add a message-based throttle with the default popup values
            var popup = openThrottlePopup(0);
            compare(findReady("configEditorThrottleTypeCombo").currentIndex, 0, "New throttle defaults to messages");
            compare(findReady("configEditorThrottleValueField").text, "10");
            compare(findReady("configEditorThrottleRemoveButton").visible, false, "Remove hidden for new throttle");
            mouseClick(findReady("configEditorThrottleOkButton"));
            tryCompare(popup, "visible", false, 1000);
            tryCompare(findReady("configEditorThrottleBadgeLabel_0"), "text", "10 msg/s", 1000);

            // Add a bytes-based throttle
            setThrottle(1, 1, "500000", "2.0");
            tryCompare(findReady("configEditorThrottleBadgeLabel_1"), "text", "500 kB/s", 1000);
            compare(findReady("configEditorSelectionSummaryLabel").text, "0 of 2 topics selected, 2 throttled");

            // Update the existing throttle; popup is pre-filled with current values
            popup = openThrottlePopup(0);
            compare(findReady("configEditorThrottleTypeCombo").currentIndex, 0);
            compare(findReady("configEditorThrottleValueField").text, "10");
            compare(findReady("configEditorThrottleRemoveButton").visible, true, "Remove visible for existing throttle");
            findReady("configEditorThrottleValueField").text = "5";
            mouseClick(findReady("configEditorThrottleOkButton"));
            tryCompare(popup, "visible", false, 1000);
            tryCompare(findReady("configEditorThrottleBadgeLabel_0"), "text", "5 msg/s", 1000, "Badge should refresh after rate update");
            compare(findReady("configEditorSelectionSummaryLabel").text, "0 of 2 topics selected, 2 throttled", "Update should not add a rule");

            // Bytes throttle keeps its values
            popup = openThrottlePopup(1);
            compare(findReady("configEditorThrottleTypeCombo").currentIndex, 1);
            compare(findReady("configEditorThrottleValueField").text, "500000");
            compare(findReady("configEditorThrottleWindowField").text, "2");
            mouseClick(findReady("configEditorThrottleCancelButton"));
            tryCompare(popup, "visible", false, 1000);

            // YAML should include throttle section
            var yaml = yamlEditorText();
            verify(yaml.indexOf("topic_throttle:") >= 0, "Should have throttle section");
            verify(yaml.indexOf("/camera") >= 0, "Should contain camera throttle");
            verify(yaml.indexOf("msgs_per_sec: 5") >= 0, "Should have updated rate");
            verify(yaml.indexOf("/lidar") >= 0, "Should contain lidar throttle");
            verify(yaml.indexOf("bytes_per_sec: 500000") >= 0, "Should have bytes limit");
            verify(yaml.indexOf("window: 2") >= 0, "Should have window");

            // Remove camera throttle
            clickTab("configEditorTopicSelectorTab");
            popup = openThrottlePopup(0);
            mouseClick(findReady("configEditorThrottleRemoveButton"));
            tryCompare(popup, "visible", false, 1000);
            tryCompare(findReady("configEditorThrottleBadgeLabel_0"), "text", "⏱", 1000, "Camera throttle should be removed");
            compare(findReady("configEditorThrottleBadgeLabel_1").text, "500 kB/s", "Lidar throttle should still exist");
            compare(findReady("configEditorSelectionSummaryLabel").text, "0 of 2 topics selected, 1 throttled");
        }
        function test_open_fetches_config_and_topics() {
            mockInterface.mockConfigYaml = 'output: "~/fetched/"\ntopics:\n  - "/fetched_topic"\n';
            mockInterface.mockTopics = [
                {
                    "name": "/fetched_topic",
                    "type": "std_msgs/msg/String"
                }
            ];
            openEditor(1);
            tryVerify(function () {
                return mockInterface.fetchConfigCount >= 1;
            }, 1000, "Should fetch config on open");
            tryVerify(function () {
                return mockInterface.fetchTopicsCount >= 1;
            }, 1000, "Should fetch topics on open");
            compare(findReady("configEditorOutputField").text, "~/fetched/");
            compare(findReady("configEditorTopicNameLabel_0").text, "/fetched_topic");
            compare(findReady("configEditorTopicCheckbox_0").checked, true, "Topic from config should be selected");
            verify(!findReady("configEditorTopicEmptyStateLabel").visible, "Empty state should be hidden");
        }
        function test_remove_middle_throttle_keeps_others() {
            mockInterface.mockTopics = [
                {
                    "name": "/a",
                    "type": "std_msgs/msg/String"
                },
                {
                    "name": "/b",
                    "type": "std_msgs/msg/String"
                },
                {
                    "name": "/c",
                    "type": "std_msgs/msg/String"
                }
            ];
            openEditor(3);
            setThrottle(0, 0, "5");
            setThrottle(1, 1, "200000", "2.0");
            setThrottle(2, 0, "20");
            tryCompare(findReady("configEditorThrottleBadgeLabel_0"), "text", "5 msg/s", 1000);
            compare(findReady("configEditorThrottleBadgeLabel_1").text, "200 kB/s");
            compare(findReady("configEditorThrottleBadgeLabel_2").text, "20 msg/s");

            // Remove middle one
            var popup = openThrottlePopup(1);
            mouseClick(findReady("configEditorThrottleRemoveButton"));
            tryCompare(popup, "visible", false, 1000);
            tryCompare(findReady("configEditorThrottleBadgeLabel_1"), "text", "⏱", 1000, "Middle throttle should be removed");
            compare(findReady("configEditorThrottleBadgeLabel_0").text, "5 msg/s", "First throttle should still exist");
            compare(findReady("configEditorThrottleBadgeLabel_2").text, "20 msg/s", "Last throttle should still exist");

            // YAML should only have /a and /c
            var yaml = yamlEditorText();
            verify(yaml.indexOf('"/a":') >= 0, "YAML should contain /a throttle");
            compare(yaml.indexOf('"/b":'), -1, "YAML should not contain /b throttle");
            verify(yaml.indexOf('"/c":') >= 0, "YAML should contain /c throttle");
        }
        function test_save_preset_emits_signal() {
            openEditor(0);
            var saveButton = findReady("configEditorSaveButton");
            var nameField = findReady("configEditorPresetNameField");
            compare(saveButton.enabled, false, "Save should be disabled without a name");
            nameField.text = "test_preset";
            tryCompare(saveButton, "enabled", true, 1000);
            mouseClick(saveButton);
            compare(savedSpy.count, 1, "configSaved should be emitted");
            compare(savedSpy.signalArguments[0][0], "test_preset", "Save signal should carry name");
            verify(savedSpy.signalArguments[0][1].indexOf("node_name:") >= 0, "Save signal should carry yaml");
            compare(nameField.text, "", "Name field should be cleared after saving");

            // YAML tab saves the raw text
            clickTab("configEditorYamlEditorTab");
            findReady("configEditorConfigTextArea").text = "output: test\n";
            nameField.text = "raw_preset";
            mouseClick(saveButton);
            compare(savedSpy.count, 2);
            compare(savedSpy.signalArguments[1][1], "output: test\n", "Save signal should carry yaml");
        }
        function test_selected_count_tracks_selection() {
            mockInterface.mockTopics = [
                {
                    "name": "/camera",
                    "type": "sensor_msgs/msg/Image"
                },
                {
                    "name": "/lidar",
                    "type": "sensor_msgs/msg/PointCloud2"
                },
                {
                    "name": "/imu",
                    "type": "sensor_msgs/msg/Imu"
                }
            ];
            mockInterface.mockConfigYaml = 'all_topics: false\n' + 'topics:\n' + '  - "/camera"\n' + '  - "/imu"\n';
            openEditor(3);
            var summary = findReady("configEditorSelectionSummaryLabel");
            tryCompare(summary, "text", "2 of 3 topics selected", 1000, "Loaded config should mark two topics selected");

            // Re-loading a config that selects all three updates the count
            mockInterface.mockConfigYaml = 'all_topics: false\n' + 'topics:\n' + '  - "/camera"\n' + '  - "/lidar"\n' + '  - "/imu"\n';
            mouseClick(findReady("configEditorLoadButton"));
            tryCompare(summary, "text", "3 of 3 topics selected", 1000, "Re-parsing should refresh the count");

            // Toggling a checkbox updates the count
            mouseClick(findReady("configEditorTopicCheckbox_1"));
            tryCompare(summary, "text", "2 of 3 topics selected", 1000, "Unchecking should refresh the count");
        }
        function test_show_selected_only_toggle() {
            mockInterface.mockTopics = [
                {
                    "name": "/a",
                    "type": "std_msgs/msg/String"
                },
                {
                    "name": "/b",
                    "type": "std_msgs/msg/String"
                }
            ];
            mockInterface.mockConfigYaml = 'topics:\n  - "/b"\n';
            openEditor(2);
            var toggle = findReady("configEditorShowSelectedToggle");
            compare(toggle.checked, false, "Show selected should be off by default");
            compare(toggle.text, "Selected Only");
            compare(findReady("configEditorTopicRow_0").visible, true);
            mouseClick(toggle);
            compare(toggle.checked, true, "Should toggle on");
            compare(toggle.text, "Show All");
            tryCompare(findReady("configEditorTopicRow_0"), "visible", false, 1000, "Unselected topic should be hidden");
            compare(findReady("configEditorTopicRow_1").visible, true, "Selected topic should stay visible");
            mouseClick(toggle);
            tryCompare(findReady("configEditorTopicRow_0"), "visible", true, 1000);
        }
        function test_throttle_config_is_parsed_from_yaml() {
            mockInterface.mockTopics = [
                {
                    "name": "/cam",
                    "type": "sensor_msgs/msg/Image"
                },
                {
                    "name": "/lidar",
                    "type": "sensor_msgs/msg/PointCloud2"
                }
            ];
            mockInterface.mockConfigYaml = 'topics:\n' + '  - "/cam"\n' + 'topic_throttle:\n' + '  "/cam":\n' + '    type: "messages"\n' + '    msgs_per_sec: 15\n' + '  "/lidar":\n' + '    type: "bytes"\n' + '    bytes_per_sec: 200000\n' + '    window: 0.5\n';
            openEditor(2);
            tryCompare(findReady("configEditorThrottleBadgeLabel_0"), "text", "15 msg/s", 1000, "Should parse /cam throttle");
            compare(findReady("configEditorThrottleBadgeLabel_1").text, "200 kB/s", "Should parse /lidar throttle");
            var popup = openThrottlePopup(0);
            compare(findReady("configEditorThrottleTypeCombo").currentIndex, 0, "/cam should be messages");
            compare(findReady("configEditorThrottleValueField").text, "15");
            mouseClick(findReady("configEditorThrottleCancelButton"));
            tryCompare(popup, "visible", false, 1000);
            popup = openThrottlePopup(1);
            compare(findReady("configEditorThrottleTypeCombo").currentIndex, 1, "/lidar should be bytes");
            compare(findReady("configEditorThrottleValueField").text, "200000");
            compare(findReady("configEditorThrottleWindowField").text, "0.5");
            mouseClick(findReady("configEditorThrottleCancelButton"));
            tryCompare(popup, "visible", false, 1000);
        }
        function test_topic_filter_hides_non_matching_rows() {
            mockInterface.mockTopics = [
                {
                    "name": "/camera/image",
                    "type": "sensor_msgs/msg/Image"
                },
                {
                    "name": "/camera/depth",
                    "type": "sensor_msgs/msg/Image"
                },
                {
                    "name": "/imu/data",
                    "type": "sensor_msgs/msg/Imu"
                }
            ];
            openEditor(3);
            var filterField = findReady("configEditorTopicFilterField");
            filterField.text = "CAMERA";
            tryCompare(findReady("configEditorTopicRow_2"), "visible", false, 1000, "Non-matching topic should be hidden");
            compare(findReady("configEditorTopicRow_0").visible, true, "Filter should be case-insensitive");
            compare(findReady("configEditorTopicRow_1").visible, true);
            filterField.text = "";
            tryCompare(findReady("configEditorTopicRow_2"), "visible", true, 1000, "Clearing the filter shows all rows");
        }
        function test_topic_list_parsing_variants() {
            mockInterface.mockTopics = [
                {
                    "name": "/a",
                    "type": "std_msgs/msg/String"
                },
                {
                    "name": "/b",
                    "type": "std_msgs/msg/String"
                },
                {
                    "name": "/c",
                    "type": "std_msgs/msg/String"
                },
                {
                    "name": "/x",
                    "type": "std_msgs/msg/String"
                },
                {
                    "name": "/y",
                    "type": "std_msgs/msg/String"
                }
            ];
            openEditor(5);
            var loadButton = findReady("configEditorLoadButton");
            compare(findReady("configEditorPresetCombo").currentIndex, 0, "(Current) should be selected");

            // Quoted entries followed by another key
            mockInterface.mockConfigYaml = 'topics:\n  - "/a"\n  - "/b"\n  - "/c"\nother: value\n';
            mouseClick(loadButton);
            compare(checkboxStates(), "true,true,true,false,false");

            // Without quotes
            mockInterface.mockConfigYaml = 'topics:\n  - /x\n  - /y\n';
            mouseClick(loadButton);
            compare(checkboxStates(), "false,false,false,true,true");

            // No topics section
            mockInterface.mockConfigYaml = 'output: "~/bags/"\n';
            mouseClick(loadButton);
            compare(checkboxStates(), "false,false,false,false,false");
        }
        function yamlEditorText() {
            clickTab("configEditorYamlEditorTab");
            return findReady("configEditorConfigTextArea").text;
        }

        name: "ConfigEditorTest"
        when: windowShown
    }
}
