import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RQml.Elements
import RQml.Fonts
import RQml.Recorder

/**
 * Dialog for editing and managing recorder configurations.
 * Supports two modes: YAML text editor and interactive topic selector.
 * Presets are saved/loaded as YAML files in ~/.ros/hector_recorder_presets/.
 */
Popup {
    id: root

    //! Cached config YAML fetched on dialog open
    property string _cachedConfigYaml: ""

    //! Cached lowercase filter text (debounced)
    property string _filterText: ""

    //! Cached count of selected topics (recomputed on every selection mutation)
    property int _selectedTopicCount: 0

    //! When true, only show selected topics in the list
    property bool _showSelectedOnly: false

    //! Revision counter to force badge re-evaluation on throttle edits
    property int _throttleRev: 0

    //! The RecorderInterface to send config to
    property var recorderInterface: null

    //! Saved config names array (from PresetStore)
    property var savedConfigNames: []

    //! Signal when a config is deleted locally
    signal configDeleted(string name)

    //! Signal when a config is saved locally
    signal configSaved(string name, string yaml)

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

    //! Fetch available topics from the recorder and populate the list
    function _fetchAvailableTopics() {
        if (!root.recorderInterface)
            return;
        root.recorderInterface.fetchAvailableTopics(function (topics) {
            // Remember current selections
            let selectedSet = {};
            for (let i = 0; i < topicListModel.count; i++) {
                if (topicListModel.get(i).selected) {
                    selectedSet[topicListModel.get(i).topicName] = true;
                }
            }

            // Also get topics from cached config YAML
            if (root._cachedConfigYaml) {
                let configTopics = _parseTopicList(root._cachedConfigYaml);
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
            _updateSelectedCount();

            // Populate throttle rules from config YAML (only on first load,
            // i.e. when throttleModel is still empty)
            if (throttleModel.count === 0 && root._cachedConfigYaml) {
                let throttleMap = _parseThrottleConfigs(root._cachedConfigYaml);
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

    //! Returns the YAML from the active tab (topic selector or text editor)
    function _getActiveYaml() {
        if (tabBar.currentIndex === 0) {
            return _buildYamlFromTopicSelector();
        }
        return configTextArea.text;
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

    //! Load current config from the recorder via GetConfig service
    function _loadCurrentConfig() {
        if (!root.recorderInterface)
            return;
        root.recorderInterface.fetchConfig(function (yaml) {
            root._cachedConfigYaml = yaml;
            configTextArea.text = yaml;
            _parseYamlToTopicSelector(yaml);
        });
    }

    //! Open the throttle edit popup for a topic, anchored near the badge
    function _openThrottlePopup(topicName, anchor) {
        throttlePopup.topicName = topicName;
        let th = _getThrottle(topicName);
        if (th) {
            popupTypeCombo.currentIndex = th.throttleType === "bytes" ? 1 : 0;
            popupValueField.text = th.throttleType === "messages" ? String(th.rate) : String(th.bytes);
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

            if (!inThrottle)
                continue;

            // New top-level key means we left the throttle section
            if (line.length > 0 && line[0] !== ' ' && line[0] !== '\t') {
                break;
            }

            // Topic name line (2-space indent): "  "/topic":"
            let topicMatch = line.match(/^\s{2}"?([^":]+)"?:\s*$/);
            if (topicMatch) {
                currentTopic = topicMatch[1];
                result[currentTopic] = {
                    type: "messages",
                    rate: 10.0,
                    bytes: 1000000,
                    window: 1.0
                };
                continue;
            }

            if (!currentTopic)
                continue;

            // type
            let m = line.match(/^\s+type:\s*"?(\w+)"?/);
            if (m) {
                result[currentTopic].type = m[1];
                continue;
            }

            // msgs_per_sec
            m = line.match(/^\s+msgs_per_sec:\s*([\d.]+)/);
            if (m) {
                result[currentTopic].rate = parseFloat(m[1]);
                continue;
            }

            // bytes_per_sec
            m = line.match(/^\s+bytes_per_sec:\s*([\d.]+)/);
            if (m) {
                result[currentTopic].bytes = parseFloat(m[1]);
                continue;
            }

            // window
            m = line.match(/^\s+window:\s*([\d.]+)/);
            if (m) {
                result[currentTopic].window = parseFloat(m[1]);
                continue;
            }
        }

        return result;
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
            if (m) {
                outputField.text = m[1];
                continue;
            }

            // storage_id
            m = line.match(/^storage_id:\s*"?([^"]*)"?$/);
            if (m) {
                let idx = storageCombo.find(m[1]);
                if (idx >= 0)
                    storageCombo.currentIndex = idx;
                continue;
            }

            // all_topics
            m = line.match(/^all_topics:\s*(true|false)$/);
            if (m) {
                allTopicsCheck.checked = (m[1] === "true");
                continue;
            }

            // publish_status
            m = line.match(/^publish_status:\s*(true|false)$/);
            if (m) {
                publishStatusCheck.checked = (m[1] === "true");
                continue;
            }
        }

        // Parse topic list from YAML and select matching topics
        let yamlTopics = _parseTopicList(yaml);
        for (let j = 0; j < topicListModel.count; j++) {
            let name = topicListModel.get(j).topicName;
            topicListModel.setProperty(j, "selected", yamlTopics.indexOf(name) >= 0);
        }
        _updateSelectedCount();

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

    //! Set or update throttle for a topic
    function _setThrottle(topicName, type, rate, bytes, window) {
        for (let i = 0; i < throttleModel.count; i++) {
            if (throttleModel.get(i).topic === topicName) {
                throttleModel.set(i, {
                    topic: topicName,
                    throttleType: type,
                    rate: rate,
                    bytes: bytes,
                    window: window
                });
                _throttleRev++;
                return;
            }
        }
        throttleModel.append({
            topic: topicName,
            throttleType: type,
            rate: rate,
            bytes: bytes,
            window: window
        });
        _throttleRev++;
    }
    function _updateSelectedCount() {
        let count = 0;
        for (let i = 0; i < topicListModel.count; i++) {
            if (topicListModel.get(i).selected)
                count++;
        }
        root._selectedTopicCount = count;
    }

    anchors.centerIn: parent
    height: Math.min(parent.height * 0.95, 850)
    modal: true
    objectName: "configEditorDialog"
    padding: 16
    width: Math.min(parent.width * 0.9, 950)

    background: Rectangle {
        border.color: palette.mid
        color: palette.window
        radius: 8
    }

    onOpened: {
        _loadCurrentConfig();
        _fetchAvailableTopics();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ---- Header ----
        RowLayout {
            Layout.fillWidth: true

            Label {
                font.bold: true
                font.pixelSize: 16
                text: "Configuration Editor"
            }
            Item {
                Layout.fillWidth: true
            }
            Button {
                flat: true
                font.family: IconFont.name
                objectName: "configEditorCloseButton"
                text: IconFont.iconClose

                onClicked: root.close()
            }
        }

        // ---- Preset Selector ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Preset:"
            }
            ComboBox {
                id: presetCombo

                Layout.fillWidth: true
                model: {
                    let names = Array.from(root.savedConfigNames || []);
                    names.unshift("(Current)");
                    return names;
                }
                objectName: "configEditorPresetCombo"

                onActivated: function (index) {
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
                objectName: "configEditorLoadButton"
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
                enabled: presetCombo.currentIndex > 0
                objectName: "configEditorDeleteButton"
                text: "Delete"

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
            objectName: "configEditorTabBar"

            onCurrentIndexChanged: {
                // Sync YAML text when switching to YAML tab from topic selector
                if (currentIndex === 1) {
                    configTextArea.text = _buildYamlFromTopicSelector();
                }
            }

            TabButton {
                objectName: "configEditorTopicSelectorTab"
                text: "Topic Selector"
            }
            TabButton {
                objectName: "configEditorYamlEditorTab"
                text: "YAML Editor"
            }
        }

        // ---- Tab Content ----
        StackLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            currentIndex: tabBar.currentIndex

            // ================================================================
            // Tab 0: Topic Selector
            // ================================================================
            ColumnLayout {
                spacing: 8

                // ---- Settings Row ----
                GridLayout {
                    Layout.fillWidth: true
                    columnSpacing: 12
                    columns: 4
                    rowSpacing: 6

                    Label {
                        text: "Output:"
                    }
                    TextField {
                        id: outputField

                        Layout.columnSpan: 3
                        Layout.fillWidth: true
                        objectName: "configEditorOutputField"
                        placeholderText: "~/bags/"
                        text: "~/bags/"
                    }
                    Label {
                        text: "Storage:"
                    }
                    ComboBox {
                        id: storageCombo

                        currentIndex: 0
                        model: ["sqlite3", "mcap"]
                        objectName: "configEditorStorageCombo"
                    }
                    CheckBox {
                        id: allTopicsCheck

                        checked: false
                        objectName: "configEditorAllTopicsCheck"
                        text: "All Topics"

                        onCheckedChanged: {
                            if (checked) {
                                // Uncheck all individual topics when "all" is selected
                                for (let i = 0; i < topicListModel.count; i++) {
                                    topicListModel.setProperty(i, "selected", false);
                                }
                                root._updateSelectedCount();
                            }
                        }
                    }
                    CheckBox {
                        id: publishStatusCheck

                        checked: true
                        objectName: "configEditorPublishStatusCheck"
                        text: "Publish Status"
                    }
                }

                // ---- Topic List Header ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        font.bold: true
                        text: "Available Topics"
                    }
                    Button {
                        enabled: !allTopicsCheck.checked
                        flat: true
                        objectName: "configEditorClearAllButton"
                        text: "Clear All"

                        onClicked: {
                            for (let i = 0; i < topicListModel.count; i++) {
                                topicListModel.setProperty(i, "selected", false);
                            }
                            root._updateSelectedCount();
                        }
                    }
                    Button {
                        id: showSelectedBtn

                        checkable: true
                        checked: root._showSelectedOnly
                        flat: true
                        objectName: "configEditorShowSelectedToggle"
                        text: root._showSelectedOnly ? "Show All" : "Selected Only"

                        onToggled: root._showSelectedOnly = checked
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    TextField {
                        id: topicFilter

                        Layout.preferredWidth: 200
                        objectName: "configEditorTopicFilterField"
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
                        objectName: "configEditorRefreshButton"
                        text: "Refresh"

                        onClicked: _fetchAvailableTopics()
                    }
                }

                // ---- Topic List ----
                ListView {
                    id: topicListView

                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    clip: true
                    objectName: "configEditorTopicListView"

                    ScrollBar.vertical: ScrollBar {
                    }
                    delegate: Rectangle {
                        id: topicDelegate

                        color: model.index % 2 === 0 ? "transparent" : Qt.rgba(0.5, 0.5, 0.5, 0.05)
                        height: visible ? 36 : 0
                        objectName: "configEditorTopicRow_" + index
                        visible: {
                            if (root._showSelectedOnly && !model.selected)
                                return false;
                            return root._filterText.length === 0 || model.topicName.toLowerCase().indexOf(root._filterText) >= 0;
                        }
                        width: topicListView.width

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            CheckBox {
                                checked: model.selected
                                enabled: !allTopicsCheck.checked
                                objectName: "configEditorTopicCheckbox_" + index

                                onClicked: {
                                    topicListModel.setProperty(model.index, "selected", checked);
                                    root._updateSelectedCount();
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                objectName: "configEditorTopicNameLabel_" + index
                                opacity: allTopicsCheck.checked ? 0.5 : 1.0
                                text: model.topicName
                            }

                            // Throttle badge
                            Rectangle {
                                id: throttleBadge

                                // Reference throttleModel.count to re-evaluate when rules change
                                property var _th: {
                                    throttleModel.count;
                                    root._throttleRev;
                                    return root._getThrottle(model.topicName);
                                }

                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredHeight: 22
                                Layout.preferredWidth: Math.max(badgeLabel.implicitWidth + 14, 28)
                                border.color: {
                                    if (badgeMouseArea.containsMouse)
                                        return Material.color(Material.Orange);
                                    return _th ? Qt.rgba(Material.color(Material.Orange).r, Material.color(Material.Orange).g, Material.color(Material.Orange).b, 0.6) : Qt.rgba(palette.mid.r, palette.mid.g, palette.mid.b, 0.4);
                                }
                                border.width: 1
                                color: {
                                    if (!_th)
                                        return "transparent";
                                    return Qt.rgba(Material.color(Material.Orange).r, Material.color(Material.Orange).g, Material.color(Material.Orange).b, 0.2);
                                }
                                objectName: "configEditorThrottleBadge_" + index
                                radius: 10

                                Label {
                                    id: badgeLabel

                                    anchors.centerIn: parent
                                    color: throttleBadge._th ? Material.color(Material.Orange) : palette.text
                                    font.bold: !!throttleBadge._th
                                    objectName: "configEditorThrottleBadgeLabel_" + index
                                    opacity: throttleBadge._th ? 1.0 : 0.5
                                    text: {
                                        let th = throttleBadge._th;
                                        if (!th)
                                            return "\u23F1"; // stopwatch
                                        if (th.throttleType === "messages")
                                            return th.rate + " msg/s";
                                        return (th.bytes / 1000).toFixed(0) + " kB/s";
                                    }
                                }
                                MouseArea {
                                    id: badgeMouseArea

                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true

                                    onClicked: {
                                        root._openThrottlePopup(model.topicName, throttleBadge);
                                    }
                                }
                                ToolTip {
                                    text: throttleBadge._th ? "Edit throttle" : "Add throttle"
                                    visible: badgeMouseArea.containsMouse
                                }
                            }
                            Label {
                                Layout.preferredWidth: 180
                                elide: Text.ElideRight
                                opacity: allTopicsCheck.checked ? 0.4 : 0.7
                                text: model.topicType
                            }
                        }
                    }
                    model: ListModel {
                        id: topicListModel

                    }

                    Label {
                        anchors.centerIn: parent
                        color: palette.mid
                        horizontalAlignment: Text.AlignHCenter
                        objectName: "configEditorTopicEmptyStateLabel"
                        text: !recorderInterface ? "No recorder connected." : "No topics available. Click Refresh to discover topics."
                        visible: topicListModel.count === 0
                        width: parent.width - 32
                        wrapMode: Text.Wrap
                    }
                }

                // ---- Selection Summary ----
                Label {
                    Layout.fillWidth: true
                    color: palette.mid
                    objectName: "configEditorSelectionSummaryLabel"
                    text: {
                        if (allTopicsCheck.checked)
                            return "All topics selected";
                        let s = root._selectedTopicCount + " of " + topicListModel.count + " topics selected";
                        if (throttleModel.count > 0)
                            s += ", " + throttleModel.count + " throttled";
                        return s;
                    }
                }

                // Hidden model for throttle rules
                ListModel {
                    id: throttleModel

                }

                // Throttle edit popup (reused for all topics)
                Popup {
                    id: throttlePopup

                    property string topicName: ""

                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    height: throttlePopupContent.implicitHeight + 32
                    modal: false
                    objectName: "configEditorThrottlePopup"
                    padding: 12
                    width: 280

                    background: Rectangle {
                        border.color: palette.mid
                        color: palette.window
                        layer.enabled: true
                        radius: 6
                    }

                    ColumnLayout {
                        id: throttlePopupContent

                        anchors.fill: parent
                        spacing: 8

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            font.bold: true
                            text: throttlePopup.topicName
                        }
                        RowLayout {
                            spacing: 8

                            Label {
                                text: "Type:"
                            }
                            ComboBox {
                                id: popupTypeCombo

                                Layout.fillWidth: true
                                model: ["msgs/s", "bytes/s"]
                                objectName: "configEditorThrottleTypeCombo"
                            }
                        }
                        RowLayout {
                            spacing: 8

                            Label {
                                text: popupTypeCombo.currentIndex === 0 ? "Rate:" : "Limit:"
                            }
                            TextField {
                                id: popupValueField

                                Layout.fillWidth: true
                                objectName: "configEditorThrottleValueField"

                                validator: DoubleValidator {
                                    bottom: 0
                                }
                            }
                            Label {
                                color: palette.mid
                                text: popupTypeCombo.currentIndex === 0 ? "msgs/s" : "B/s"
                            }
                        }
                        RowLayout {
                            spacing: 8
                            visible: popupTypeCombo.currentIndex === 1

                            Label {
                                text: "Window:"
                            }
                            TextField {
                                id: popupWindowField

                                Layout.fillWidth: true
                                objectName: "configEditorThrottleWindowField"

                                validator: DoubleValidator {
                                    bottom: 0.01
                                }
                            }
                            Label {
                                color: palette.mid
                                text: "s"
                            }
                        }
                        RowLayout {
                            spacing: 8

                            Button {
                                flat: true
                                objectName: "configEditorThrottleRemoveButton"
                                text: "Remove"
                                visible: root._getThrottle(throttlePopup.topicName) !== null

                                onClicked: {
                                    root._removeThrottle(throttlePopup.topicName);
                                    throttlePopup.close();
                                }
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Button {
                                flat: true
                                objectName: "configEditorThrottleCancelButton"
                                text: "Cancel"

                                onClicked: throttlePopup.close()
                            }
                            Button {
                                highlighted: true
                                objectName: "configEditorThrottleOkButton"
                                text: "OK"

                                onClicked: {
                                    let type = popupTypeCombo.currentIndex === 0 ? "messages" : "bytes";
                                    let val = parseFloat(popupValueField.text) || 0;
                                    let win = parseFloat(popupWindowField.text) || 1.0;
                                    root._setThrottle(throttlePopup.topicName, type, type === "messages" ? val : 10.0, type === "bytes" ? val : 1000000, win);
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
                    Layout.fillHeight: true
                    Layout.fillWidth: true

                    TextArea {
                        id: configTextArea

                        font.family: "monospace"
                        objectName: "configEditorConfigTextArea"
                        selectByMouse: true
                        text: ""
                        wrapMode: TextArea.WrapAnywhere
                    }
                }
            }
        }

        // ---- Save Preset Row ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Save as:"
            }
            TextField {
                id: presetNameField

                Layout.fillWidth: true
                objectName: "configEditorPresetNameField"
                placeholderText: "Preset name"
            }
            Button {
                enabled: presetNameField.text.length > 0
                objectName: "configEditorSaveButton"
                text: "Save Preset"

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

            Item {
                Layout.fillWidth: true
            }
            Button {
                enabled: root.recorderInterface
                highlighted: true
                objectName: "configEditorApplyButton"
                text: "Apply"

                onClicked: {
                    root.recorderInterface.applyConfig(_getActiveYaml(), false);
                    root.close();
                }
            }
            Button {
                enabled: root.recorderInterface
                objectName: "configEditorApplyRestartButton"
                text: "Apply & Restart"

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
            objectName: "configEditorStatusLabel"
            wrapMode: Text.Wrap

            Connections {
                function onServiceResponse(name, success, message) {
                    if (name === "config") {
                        statusLabel.text = (success ? "\u2713 " : "\u2717 ") + message;
                        statusLabel.color = success ? Material.color(Material.Green) : Material.color(Material.Red);
                    }
                }

                target: root.recorderInterface
            }
        }
    }
}
