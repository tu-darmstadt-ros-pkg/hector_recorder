import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Elements
import RQml.Fonts
import RqmlRecorder

/**
 * Dialog for editing and managing recorder configurations.
 * Supports two modes: YAML text editor and interactive topic selector.
 * Presets are saved/loaded as YAML files in ~/.ros/hector_recorder_presets/.
 */
Popup {
    id: root
    modal: true
    width: Math.min(parent.width * 0.9, 950)
    height: Math.min(parent.height * 0.95, 850)
    anchors.centerIn: parent
    padding: 16

    //! The RecorderInterface to send config to
    property var recorderInterface: null

    //! Saved config names array (from PresetStore)
    property var savedConfigNames: []

    //! Path for saving to recorder filesystem
    property string remoteFilePath: ""

    //! Signal when a config is saved locally
    signal configSaved(string name, string yaml)

    //! Signal when a config is deleted locally
    signal configDeleted(string name)

    //! Cached lowercase filter text (debounced)
    property string _filterText: ""

    background: Rectangle {
        color: palette.window
        border.color: palette.mid
        radius: 8
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ---- Header ----
        RowLayout {
            Layout.fillWidth: true

            Label {
                text: "Configuration Editor"
                font.bold: true
                font.pixelSize: 16
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "\u2715"
                flat: true
                onClicked: root.close()
            }
        }

        // ---- Preset Selector ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "Preset:" }

            ComboBox {
                id: presetCombo
                Layout.fillWidth: true
                model: {
                    let names = Array.from(root.savedConfigNames || []);
                    names.unshift("(Current)");
                    return names;
                }

                onActivated: function(index) {
                    if (index === 0) {
                        _loadCurrentConfig();
                    } else {
                        let name = model[index];
                        let yaml = PresetStore.load(name);
                        configTextArea.text = yaml;
                        _parseYamlToTopicSelector(yaml);
                    }
                }
            }

            Button {
                text: "Load"
                onClicked: {
                    if (presetCombo.currentIndex === 0) {
                        _loadCurrentConfig();
                    } else if (presetCombo.currentIndex > 0) {
                        let name = presetCombo.model[presetCombo.currentIndex];
                        let yaml = PresetStore.load(name);
                        configTextArea.text = yaml;
                        _parseYamlToTopicSelector(yaml);
                    }
                }
            }

            Button {
                text: "Delete"
                enabled: presetCombo.currentIndex > 0
                onClicked: {
                    let name = presetCombo.model[presetCombo.currentIndex];
                    root.configDeleted(name);
                }
            }
        }

        // ---- Tab Bar ----
        TabBar {
            id: tabBar
            Layout.fillWidth: true

            TabButton { text: "Topic Selector" }
            TabButton { text: "YAML Editor" }

            onCurrentIndexChanged: {
                // Sync YAML text when switching to YAML tab from topic selector
                if (currentIndex === 1) {
                    configTextArea.text = _buildYamlFromTopicSelector();
                }
            }
        }

        // ---- Tab Content ----
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // ================================================================
            // Tab 0: Topic Selector
            // ================================================================
            ColumnLayout {
                spacing: 8

                // ---- Settings Row ----
                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: 12
                    rowSpacing: 6

                    Label { text: "Output:" }
                    TextField {
                        id: outputField
                        Layout.fillWidth: true
                        Layout.columnSpan: 3
                        placeholderText: "~/bags/"
                        text: "~/bags/"
                    }

                    Label { text: "Storage:" }
                    ComboBox {
                        id: storageCombo
                        model: ["sqlite3", "mcap"]
                        currentIndex: 0
                    }

                    CheckBox {
                        id: allTopicsCheck
                        text: "All Topics"
                        checked: false
                        onCheckedChanged: {
                            if (checked) {
                                // Uncheck all individual topics when "all" is selected
                                for (let i = 0; i < topicListModel.count; i++) {
                                    topicListModel.setProperty(i, "selected", false);
                                }
                            }
                        }
                    }

                    CheckBox {
                        id: publishStatusCheck
                        text: "Publish Status"
                        checked: true
                    }
                }

                // ---- Topic List Header ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: "Available Topics"
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    TextField {
                        id: topicFilter
                        Layout.preferredWidth: 200
                        placeholderText: "Filter topics..."
                        onTextChanged: filterDebounce.restart()
                    }

                    // Debounced filter to avoid per-keystroke re-evaluation of all delegates
                    Timer {
                        id: filterDebounce
                        interval: 150
                        onTriggered: root._filterText = topicFilter.text.toLowerCase()
                    }

                    Button {
                        text: "Refresh"
                        onClicked: _fetchAvailableTopics()
                    }
                }

                // ---- Topic List ----
                ListView {
                    id: topicListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: ListModel { id: topicListModel }

                    delegate: Rectangle {
                        width: topicListView.width
                        height: visible ? 30 : 0
                        visible: {
                            return root._filterText.length === 0 ||
                                   model.topicName.toLowerCase().indexOf(root._filterText) >= 0;
                        }
                        color: model.index % 2 === 0 ? "transparent" : Qt.rgba(0.5, 0.5, 0.5, 0.05)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            CheckBox {
                                checked: model.selected
                                enabled: !allTopicsCheck.checked
                                onClicked: {
                                    topicListModel.setProperty(model.index, "selected", checked);
                                }
                            }

                            Label {
                                text: model.topicName
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                opacity: allTopicsCheck.checked ? 0.5 : 1.0
                            }

                            Label {
                                text: model.topicType
                                color: palette.mid
                                font.pixelSize: 11
                                Layout.preferredWidth: 200
                                elide: Text.ElideRight
                                opacity: allTopicsCheck.checked ? 0.5 : 1.0
                            }
                        }
                    }

                    ScrollBar.vertical: ScrollBar {}
                }

                // ---- Selection Summary ----
                Label {
                    Layout.fillWidth: true
                    color: palette.mid
                    font.pixelSize: 11
                    text: {
                        if (allTopicsCheck.checked) return "All topics selected";
                        let count = 0;
                        for (let i = 0; i < topicListModel.count; i++) {
                            if (topicListModel.get(i).selected) count++;
                        }
                        return count + " of " + topicListModel.count + " topics selected";
                    }
                }
            }

            // ================================================================
            // Tab 1: YAML Editor
            // ================================================================
            ColumnLayout {
                spacing: 8

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    TextArea {
                        id: configTextArea
                        font.family: "monospace"
                        font.pixelSize: 12
                        wrapMode: TextArea.WrapAnywhere
                        selectByMouse: true
                        text: root.recorderInterface && root.recorderInterface.status
                            ? root.recorderInterface.status.config_yaml || ""
                            : ""
                    }
                }
            }
        }

        // ---- Save Preset Row ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "Save as:" }

            TextField {
                id: presetNameField
                Layout.fillWidth: true
                placeholderText: "Preset name"
            }

            Button {
                text: "Save Preset"
                enabled: presetNameField.text.length > 0
                onClicked: {
                    let yaml = _getActiveYaml();
                    root.configSaved(presetNameField.text, yaml);
                    presetNameField.text = "";
                }
            }
        }

        // ---- Remote Save Row ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label { text: "Save to recorder:" }

            TextField {
                id: remotePathField
                Layout.fillWidth: true
                placeholderText: "/path/on/recorder/config.yaml"
                text: root.remoteFilePath
            }

            Button {
                text: "Save to File"
                enabled: remotePathField.text.length > 0 && root.recorderInterface
                onClicked: {
                    root.recorderInterface.saveConfigToFile(
                        _getActiveYaml(), remotePathField.text);
                }
            }
        }

        // ---- Action Buttons ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            Button {
                text: "Apply"
                highlighted: true
                enabled: root.recorderInterface
                onClicked: {
                    root.recorderInterface.applyConfig(_getActiveYaml(), false);
                    root.close();
                }
            }

            Button {
                text: "Apply & Restart"
                enabled: root.recorderInterface
                onClicked: {
                    root.recorderInterface.applyConfig(_getActiveYaml(), true);
                    root.close();
                }
            }
        }

        // ---- Status ----
        Label {
            id: statusLabel
            Layout.fillWidth: true
            color: palette.mid
            font.pixelSize: 11
            wrapMode: Text.Wrap

            Connections {
                target: root.recorderInterface
                function onServiceResponse(name, success, message) {
                    if (name === "config" || name === "save_config") {
                        statusLabel.text = (success ? "\u2713 " : "\u2717 ") + message;
                        statusLabel.color = success ? "green" : "red";
                    }
                }
            }
        }
    }

    // ========================================================================
    // Internal Functions
    // ========================================================================

    //! Returns the YAML from the active tab (topic selector or text editor)
    function _getActiveYaml() {
        if (tabBar.currentIndex === 0) {
            return _buildYamlFromTopicSelector();
        }
        return configTextArea.text;
    }

    //! Build YAML string from the topic selector UI
    function _buildYamlFromTopicSelector() {
        let lines = [];
        lines.push("node_name: \"hector_recorder\"");
        lines.push("output: \"" + outputField.text + "\"");
        lines.push("storage_id: \"" + storageCombo.currentText + "\"");

        if (allTopicsCheck.checked) {
            lines.push("all_topics: true");
        } else {
            lines.push("all_topics: false");
            let selected = [];
            for (let i = 0; i < topicListModel.count; i++) {
                if (topicListModel.get(i).selected) {
                    selected.push(topicListModel.get(i).topicName);
                }
            }
            if (selected.length > 0) {
                lines.push("topics:");
                for (let j = 0; j < selected.length; j++) {
                    lines.push("  - \"" + selected[j] + "\"");
                }
            }
        }

        lines.push("rmw_serialization_format: \"cdr\"");
        lines.push("publish_status: " + (publishStatusCheck.checked ? "true" : "false"));
        lines.push("publish_status_topic: \"recorder_status\"");

        return lines.join("\n") + "\n";
    }

    //! Load current config from the recorder status into both views
    function _loadCurrentConfig() {
        if (root.recorderInterface && root.recorderInterface.status) {
            let yaml = root.recorderInterface.status.config_yaml || "";
            configTextArea.text = yaml;
            _parseYamlToTopicSelector(yaml);
        }
    }

    //! Simple YAML parser to populate the topic selector from a YAML string
    function _parseYamlToTopicSelector(yaml) {
        let lines = yaml.split("\n");

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();

            // output
            let m = line.match(/^output:\s*"?([^"]*)"?$/);
            if (m) { outputField.text = m[1]; continue; }

            // storage_id
            m = line.match(/^storage_id:\s*"?([^"]*)"?$/);
            if (m) {
                let idx = storageCombo.find(m[1]);
                if (idx >= 0) storageCombo.currentIndex = idx;
                continue;
            }

            // all_topics
            m = line.match(/^all_topics:\s*(true|false)$/);
            if (m) { allTopicsCheck.checked = (m[1] === "true"); continue; }

            // publish_status
            m = line.match(/^publish_status:\s*(true|false)$/);
            if (m) { publishStatusCheck.checked = (m[1] === "true"); continue; }
        }

        // Parse topic list from YAML and select matching topics
        let yamlTopics = _parseTopicList(yaml);
        for (let j = 0; j < topicListModel.count; j++) {
            let name = topicListModel.get(j).topicName;
            topicListModel.setProperty(j, "selected",
                yamlTopics.indexOf(name) >= 0);
        }
    }

    //! Extract the topics list from a YAML string
    function _parseTopicList(yaml) {
        let topics = [];
        let lines = yaml.split("\n");
        let inTopics = false;
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i];
            if (line.match(/^topics:\s*$/)) {
                inTopics = true;
                continue;
            }
            if (inTopics) {
                let m = line.match(/^\s+-\s+"?([^"]*)"?\s*$/);
                if (m) {
                    topics.push(m[1]);
                } else {
                    inTopics = false;
                }
            }
        }
        return topics;
    }

    //! Fetch available topics from the recorder and populate the list
    function _fetchAvailableTopics() {
        if (!root.recorderInterface) return;
        root.recorderInterface.fetchAvailableTopics(function(topics) {
            // Remember current selections
            let selectedSet = {};
            for (let i = 0; i < topicListModel.count; i++) {
                if (topicListModel.get(i).selected) {
                    selectedSet[topicListModel.get(i).topicName] = true;
                }
            }

            // Also get topics from current YAML config
            if (root.recorderInterface.status) {
                let configTopics = _parseTopicList(
                    root.recorderInterface.status.config_yaml || "");
                for (let k = 0; k < configTopics.length; k++) {
                    selectedSet[configTopics[k]] = true;
                }
            }

            topicListModel.clear();
            for (let j = 0; j < topics.length; j++) {
                topicListModel.append({
                    topicName: topics[j].name,
                    topicType: topics[j].type,
                    selected: selectedSet[topics[j].name] === true
                });
            }
        });
    }

    onOpened: {
        _loadCurrentConfig();
        _fetchAvailableTopics();
    }
}
