import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RqmlRecorder
import "elements"

/**
 * RQML plugin for browsing and playing local rosbag2 files.
 * Combines bag browsing (BagBrowser) with embedded playback (BagPlayerEngine).
 */
Rectangle {
    id: root
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(700, 450)
    color: palette.base

    Component.onCompleted: {
        if (!context.bag_path)
            context.bag_path = "~/bags/";
        // Auto-scan on startup after layout is settled
        autoScanTimer.start();
    }

    Timer {
        id: autoScanTimer
        interval: 100
        onTriggered: bagBrowser.refresh()
    }

    // ========================================================================
    // Backend components
    // ========================================================================

    LocalBagScanner {
        id: scanner
        scanPath: context.bag_path || ""

        onServiceResponse: function(serviceName, success, message) {
            statusLabel.text = (success ? "\u2713 " : "\u2717 ") + message;
            statusLabel.color = success ? "green" : "red";
            statusResetTimer.restart();
        }
    }

    BagPlayerEngine {
        id: playerEngine

        onPlaybackFinished: {
            statusLabel.text = "\u2713 Playback finished: " + bagName;
            statusLabel.color = palette.mid;
            statusResetTimer.restart();
        }

        onErrorMessageChanged: {
            if (errorMessage) {
                statusLabel.text = "\u2717 " + errorMessage;
                statusLabel.color = "red";
                statusResetTimer.restart();
            }
        }
    }

    // ========================================================================
    // UI Layout
    // ========================================================================

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // --------------------------------------------------------------------
        // Path selector with autocomplete
        // --------------------------------------------------------------------

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            z: 10

            Label {
                text: "Bag Directory:"
                font.bold: true
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: pathField.implicitHeight

                TextField {
                    id: pathField
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: context.bag_path || ""
                    placeholderText: "~/bags/"
                    selectByMouse: true

                    onTextEdited: completionTimer.restart()

                    onAccepted: {
                        completionPopup.close();
                        _applyScan();
                    }

                    Keys.onPressed: function(event) {
                        if (!completionPopup.visible) return;

                        if (event.key === Qt.Key_Down) {
                            completionList.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            completionList.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (completionList.currentIndex >= 0 && completionList.currentIndex < completionModel.count) {
                                let selected = completionModel.get(completionList.currentIndex).path;
                                pathField.text = selected;
                                pathField.cursorPosition = pathField.text.length;
                                completionTimer.restart();
                                event.accepted = true;
                            }
                        } else if (event.key === Qt.Key_Escape) {
                            completionPopup.close();
                            event.accepted = true;
                        }
                    }

                    Timer {
                        id: completionTimer
                        interval: 150
                        onTriggered: _updateCompletions()
                    }
                }

                Popup {
                    id: completionPopup
                    y: pathField.height
                    width: pathField.width
                    height: Math.min(completionList.contentHeight + 8, 250)
                    padding: 4
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                    background: Rectangle {
                        color: palette.window
                        border.color: palette.mid
                        radius: 4

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -1
                            z: -1
                            radius: 5
                            color: "transparent"
                            border.color: Qt.rgba(0, 0, 0, 0.15)
                        }
                    }

                    ListView {
                        id: completionList
                        anchors.fill: parent
                        model: completionModel
                        clip: true
                        currentIndex: 0

                        delegate: ItemDelegate {
                            width: completionList.width
                            height: 28
                            highlighted: index === completionList.currentIndex

                            contentItem: Label {
                                text: model.path
                                font.pixelSize: 12
                                font.family: "monospace"
                                elide: Text.ElideMiddle
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                pathField.text = model.path;
                                pathField.cursorPosition = pathField.text.length;
                                pathField.forceActiveFocus();
                                completionTimer.restart();
                            }
                        }
                    }
                }

                ListModel {
                    id: completionModel
                }
            }

            Button {
                text: "Scan"
                highlighted: true
                onClicked: {
                    completionPopup.close();
                    _applyScan();
                }
            }
        }

        // --------------------------------------------------------------------
        // Playback Panel (visible when a bag is loaded/playing)
        // --------------------------------------------------------------------

        PlaybackPanel {
            id: playbackPanel
            Layout.fillWidth: true
            engine: playerEngine
        }

        // --------------------------------------------------------------------
        // Bag Browser
        // --------------------------------------------------------------------

        BagBrowser {
            id: bagBrowser
            Layout.fillWidth: true
            Layout.fillHeight: true
            recorderInterface: scanner

            onStatusMessage: function(msg, isError) {
                statusLabel.text = (isError ? "\u2717 " : "\u2713 ") + msg;
                statusLabel.color = isError ? "red" : "green";
                statusResetTimer.restart();
            }

            onPlayRequested: function(bagPath, bagName) {
                playerEngine.load(bagPath);
                // Auto-play after loading
                playerEngine.play([]);
                statusLabel.text = "\u25B6 Playing: " + bagName;
                statusLabel.color = palette.mid;
            }
        }

        // --------------------------------------------------------------------
        // Status bar
        // --------------------------------------------------------------------

        Label {
            id: statusLabel
            Layout.fillWidth: true
            color: palette.mid
            font.pixelSize: 11
            elide: Text.ElideMiddle
            text: "Select a directory and click Scan to browse bags."

            Timer {
                id: statusResetTimer
                interval: 5000
                onTriggered: {
                    statusLabel.text = "Scanning: " + (context.bag_path || "");
                    statusLabel.color = palette.mid;
                }
            }
        }
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    function _applyScan() {
        context.bag_path = pathField.text;
        bagBrowser.refresh();
    }

    function _updateCompletions() {
        let completions = scanner.completePath(pathField.text);
        completionModel.clear();

        if (completions.length === 0) {
            completionPopup.close();
            return;
        }

        if (completions.length === 1 && completions[0] === pathField.text) {
            completionPopup.close();
            return;
        }

        for (let i = 0; i < completions.length; i++) {
            completionModel.append({ path: completions[i] });
        }

        completionList.currentIndex = 0;
        if (!completionPopup.visible)
            completionPopup.open();
    }
}
