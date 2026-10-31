pragma Singleton
import QtQuick

QtObject {
    id: root

    // In-memory storage
    property var _presets: ({})
    property var presetNames: []

    function _updateNames() {
        presetNames = Object.keys(_presets);
    }
    function load(name) {
        return _presets[name] || "";
    }
    function remove(name) {
        delete _presets[name];
        _updateNames();
        return true;
    }
    function reset() {
        _presets = {};
        presetNames = [];
    }
    function save(name, yaml) {
        _presets[name] = yaml;
        _updateNames();
        return true;
    }
}
