import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
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

    //! Signal when a config is saved locally
    signal configSaved(string name, string yaml)

    //! Signal when a config is deleted locally
    signal configDeleted(string name)

    //! Cached lowercase filter text (debounced)
    property string _filterText: ""

    //! Revision counter to force badge re-evaluation on throttle edits
    property int _throttleRev: 0

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
                        id: topicDelegate
                        width: topicListView.width
                        height: visible ? 36 : 0
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

                            // Throttle badge
                            Rectangle {
                                id: throttleBadge
                                // Reference throttleModel.count to re-evaluate when rules change
                                property var _th: { throttleModel.count; root._throttleRev; return root._getThrottle(model.topicName); }
                                Layout.preferredWidth: Math.max(badgeLabel.implicitWidth + 14, 28)
                                Layout.preferredHeight: 22
                                Layout.alignment: Qt.AlignVCenter
                                radius: 10
                                color: {
                                    if (!_th) return "transparent";
                                    return Qt.rgba(Material.color(Material.Orange).r,
                                                   Material.color(Material.Orange).g,
                                                   Material.color(Material.Orange).b, 0.2);
                                }
                                border.color: {
                                    if (badgeMouseArea.containsMouse)
                                        return Material.color(Material.Orange);
                                    return _th ? Qt.rgba(Material.color(Material.Orange).r,
                                                         Material.color(Material.Orange).g,
                                                         Material.color(Material.Orange).b, 0.6)
                                               : Qt.rgba(palette.mid.r, palette.mid.g, palette.mid.b, 0.4);
                                }
                                border.width: 1

                                Label {
                                    id: badgeLabel
                                    anchors.centerIn: parent
                                    font.pixelSize: 10
                                    font.bold: !!throttleBadge._th
                                    color: throttleBadge._th ? Material.color(Material.Orange) : palette.mid
                                    text: {
                                        let th = throttleBadge._th;
                                        if (!th) return "\u23F1"; // stopwatch
                                        if (th.throttleType === "messages")
                                            return th.rate + " msg/s";
                                        return (th.bytes / 1000).toFixed(0) + " kB/s";
                                    }
                                }

                                MouseArea {
                                    id: badgeMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root._openThrottlePopup(model.topicName, throttleBadge);
                                    }
                                }

                                ToolTip {
                                    visible: badgeMouseArea.containsMouse
                                    text: throttleBadge._th ? "Edit throttle" : "Add throttle"
                                }
                            }

                            Label {
                                text: model.topicType
                                color: palette.mid
                                font.pixelSize: 11
                                Layout.preferredWidth: 180
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
                        let s = count + " of " + topicListModel.count + " topics selected";
                        if (throttleModel.count > 0)
                            s += ", " + throttleModel.count + " throttled";
                        return s;
                    }
                }

                // Hidden model for throttle rules
                ListModel { id: throttleModel }

                // Throttle edit popup (reused for all topics)
                Popup {
                    id: throttlePopup
                    width: 280
                    height: throttlePopupContent.implicitHeight + 32
                    padding: 12
                    modal: false
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                    property string topicName: ""

                    background: Rectangle {
                        color: palette.window
                        border.color: palette.mid
                        radius: 6
                        layer.enabled: true
                    }

                    ColumnLayout {
                        id: throttlePopupContent
                        anchors.fill: parent
                        spacing: 8

                        Label {
                            text: throttlePopup.topicName
                            font.bold: true
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: 8
                            Label { text: "Type:" }
                            ComboBox {
                                id: popupTypeCombo
                                Layout.fillWidth: true
                                model: ["msgs/s", "bytes/s"]
                            }
                        }

                        RowLayout {
                            spacing: 8
                            Label { text: popupTypeCombo.currentIndex === 0 ? "Rate:" : "Limit:" }
                            TextField {
                                id: popupValueField
                                Layout.fillWidth: true
                                validator: DoubleValidator { bottom: 0 }
                            }
                            Label {
                                text: popupTypeCombo.currentIndex === 0 ? "msgs/s" : "B/s"
                                color: palette.mid
                                font.pixelSize: 11
                            }
                        }

                        RowLayout {
                            spacing: 8
                            visible: popupTypeCombo.currentIndex === 1
                            Label { text: "Window:" }
                            TextField {
                                id: popupWindowField
                                Layout.fillWidth: true
                                validator: DoubleValidator { bottom: 0.01 }
                            }
                            Label {
                                text: "s"
                                color: palette.mid
                                font.pixelSize: 11
                            }
                        }

                        RowLayout {
                            spacing: 8

                            Button {
                                text: "Remove"
                                flat: true
                                visible: root._getThrottle(throttlePopup.topicName) !== null
                                onClicked: {
                                    root._removeThrottle(throttlePopup.topicName);
                                    throttlePopup.close();
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Button {
                                text: "Cancel"
                                flat: true
                                onClicked: throttlePopup.close()
                            }

                            Button {
                                text: "OK"
                                highlighted: true
                                onClicked: {
                                    let type = popupTypeCombo.currentIndex === 0 ? "messages" : "bytes";
                                    let val = parseFloat(popupValueField.text) || 0;
                                    let win = parseFloat(popupWindowField.text) || 1.0;
                                    root._setThrottle(throttlePopup.topicName, type,
                                        type === "messages" ? val : 10.0,
                                        type === "bytes" ? val : 1000000,
                                        win);
                                    throttlePopup.close();
                                }
                            }
                        }
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
                    if (name === "config") {
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

    //! Look up throttle config for a topic, returns object or null
    function _getThrottle(topicName) {
        for (let i = 0; i < throttleModel.count; i++) {
            if (throttleModel.get(i).topic === topicName)
                return throttleModel.get(i);
        }
        return null;
    }

    //! Set or update throttle for a topic
    function _setThrottle(topicName, type, rate, bytes, window) {
        for (let i = 0; i < throttleModel.count; i++) {
            if (throttleModel.get(i).topic === topicName) {
                throttleModel.set(i, {
                    topic: topicName, throttleType: type,
                    rate: rate, bytes: bytes, window: window
                });
                _throttleRev++;
                return;
            }
        }
        throttleModel.append({
            topic: topicName, throttleType: type,
            rate: rate, bytes: bytes, window: window
        });
        _throttleRev++;
    }

    //! Remove throttle for a topic
    function _removeThrottle(topicName) {
        for (let i = 0; i < throttleModel.count; i++) {
            if (throttleModel.get(i).topic === topicName) {
                throttleModel.remove(i);
                _throttleRev++;
                return;
            }
        }
    }

    //! Open the throttle edit popup for a topic, anchored near the badge
    function _openThrottlePopup(topicName, anchor) {
        throttlePopup.topicName = topicName;
        let th = _getThrottle(topicName);
        if (th) {
            popupTypeCombo.currentIndex = th.throttleType === "bytes" ? 1 : 0;
            popupValueField.text = th.throttleType === "messages"
                ? String(th.rate) : String(th.bytes);
            popupWindowField.text = String(th.window);
        } else {
            popupTypeCombo.currentIndex = 0;
            popupValueField.text = "10";
            popupWindowField.text = "1.0";
        }
        // Position near the anchor — Popup coords are relative to its visual parent
        let parentItem = throttlePopup.parent;
        if (parentItem) {
            let pos = anchor.mapToItem(parentItem, 0, anchor.height);
            throttlePopup.x = pos.x - throttlePopup.width + anchor.width;
            throttlePopup.y = pos.y + 4;
        }
        throttlePopup.open();
    }

    //! Returns the YAML from the active tab (topic selector or text editor)
    function _getActiveYaml() {
        if (tabBar.currentIndex === 0) {
            return _buildYamlFromTopicSelector();
        }
        return configTextArea.text;
    }

    /**
     * Build a YAML config string from the current topic selector UI state.
     * Combines output path, storage_id, topic selections, and throttle rules.
     * @return {string} YAML config string
     */
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

        // Throttle configs
        if (throttleModel.count > 0) {
            lines.push("topic_throttle:");
            for (let k = 0; k < throttleModel.count; k++) {
                let item = throttleModel.get(k);
                lines.push("  \"" + item.topic + "\":");
                if (item.throttleType === "messages") {
                    lines.push("    type: \"messages\"");
                    lines.push("    msgs_per_sec: " + item.rate);
                } else {
                    lines.push("    type: \"bytes\"");
                    lines.push("    bytes_per_sec: " + item.bytes);
                    lines.push("    window: " + item.window);
                }
            }
        }

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

    /**
     * Parse a YAML config string and populate the topic selector UI.
     * Extracts: output path, storage_id, all_topics, publish_status,
     * topic selections, and throttle rules.
     * @param {string} yaml - YAML config text to parse
     */
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

        // Populate throttle rules
        let throttleMap = _parseThrottleConfigs(yaml);
        throttleModel.clear();
        for (let topic in throttleMap) {
            let th = throttleMap[topic];
            throttleModel.append({
                topic: topic,
                throttleType: th.type,
                rate: th.rate,
                bytes: th.bytes,
                window: th.window
            });
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

    /**
     * Parse the topic_throttle section from a YAML config string.
     * Recognizes 2-space-indented topic keys under "topic_throttle:",
     * each with type/msgs_per_sec/bytes_per_sec/window sub-keys.
     * @param {string} yaml - YAML config text
     * @return {Object} Map of topic name -> {type, rate, bytes, window}
     */
    function _parseThrottleConfigs(yaml) {
        let result = {};
        let lines = yaml.split("\n");
        let inThrottle = false;
        let currentTopic = "";

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i];

            if (line.match(/^topic_throttle:\s*$/)) {
                inThrottle = true;
                continue;
            }

            if (!inThrottle) continue;

            // New top-level key means we left the throttle section
            if (line.length > 0 && line[0] !== ' ' && line[0] !== '\t') {
                break;
            }

            // Topic name line (2-space indent): "  "/topic":"
            let topicMatch = line.match(/^\s{2}"?([^":]+)"?:\s*$/);
            if (topicMatch) {
                currentTopic = topicMatch[1];
                result[currentTopic] = { type: "messages", rate: 10.0, bytes: 1000000, window: 1.0 };
                continue;
            }

            if (!currentTopic) continue;

            // type
            let m = line.match(/^\s+type:\s*"?(\w+)"?/);
            if (m) { result[currentTopic].type = m[1]; continue; }

            // msgs_per_sec
            m = line.match(/^\s+msgs_per_sec:\s*([\d.]+)/);
            if (m) { result[currentTopic].rate = parseFloat(m[1]); continue; }

            // bytes_per_sec
            m = line.match(/^\s+bytes_per_sec:\s*([\d.]+)/);
            if (m) { result[currentTopic].bytes = parseFloat(m[1]); continue; }

            // window
            m = line.match(/^\s+window:\s*([\d.]+)/);
            if (m) { result[currentTopic].window = parseFloat(m[1]); continue; }
        }

        return result;
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
                let name = topics[j].name;
                topicListModel.append({
                    topicName: name,
                    topicType: topics[j].type,
                    selected: selectedSet[name] === true
                });
            }

            // Populate throttle rules from config YAML (only on first load,
            // i.e. when throttleModel is still empty)
            if (throttleModel.count === 0 && root.recorderInterface && root.recorderInterface.status) {
                let throttleMap = _parseThrottleConfigs(
                    root.recorderInterface.status.config_yaml || "");
                for (let topic in throttleMap) {
                    let th = throttleMap[topic];
                    throttleModel.append({
                        topic: topic,
                        throttleType: th.type,
                        rate: th.rate,
                        bytes: th.bytes,
                        window: th.window
                    });
                }
            }
        });
    }

    onOpened: {
        _loadCurrentConfig();
        _fetchAvailableTopics();
    }
}
