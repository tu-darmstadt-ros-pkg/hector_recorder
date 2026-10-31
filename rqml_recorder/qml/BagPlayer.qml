import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RQml.Recorder
import "elements"

/**
 * RQML plugin for browsing and playing local rosbag2 files.
 * Combines bag browsing (BagBrowser) with embedded playback (BagPlayerEngine).
 */
Rectangle {
    id: root

    property var kddockwidgets_min_size: Qt.size(700, 450)

    // ========================================================================
    // Helpers
    // ========================================================================

    function _applyScan() {
        context.bag_path = pathField.text;
        bagBrowser.currentPath = pathField.text;
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
            completionModel.append({
                path: completions[i]
            });
        }

        completionList.currentIndex = 0;
        if (!completionPopup.visible)
            completionPopup.open();
    }

    anchors.fill: parent
    color: palette.base

    Component.onCompleted: {
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

        objectName: "bagPlayerScanner"
        scanPath: context.bag_path ?? "~/bags/"

        onServiceResponse: function (serviceName, success, message) {
            statusLabel.text = (success ? "\u2713 " : "\u2717 ") + message;
            statusLabel.color = success ? Material.color(Material.Green) : Material.color(Material.Red);
            statusResetTimer.restart();
        }
    }
    BagPlayerEngine {
        id: playerEngine

        objectName: "bagPlayerEngine"

        onErrorMessageChanged: {
            if (errorMessage) {
                statusLabel.text = "\u2717 " + errorMessage;
                statusLabel.color = Material.color(Material.Red);
                statusResetTimer.restart();
            }
        }
        onPlaybackFinished: {
            statusLabel.text = "\u2713 Playback finished: " + bagName;
            statusLabel.color = palette.mid;
            statusResetTimer.restart();
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
                font.bold: true
                text: "Bag Directory:"
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: pathField.implicitHeight

                TextField {
                    id: pathField

                    anchors.left: parent.left
                    anchors.right: parent.right
                    objectName: "bagPlayerPathField"
                    placeholderText: "~/bags/"
                    selectByMouse: true
                    text: context.bag_path ?? "~/bags/"

                    Keys.onPressed: function (event) {
                        if (!completionPopup.visible)
                            return;

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
                    onAccepted: {
                        completionPopup.close();
                        _applyScan();
                    }
                    onTextEdited: completionTimer.restart()

                    Timer {
                        id: completionTimer

                        interval: 150

                        onTriggered: _updateCompletions()
                    }
                }
                Popup {
                    id: completionPopup

                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    height: Math.min(completionList.contentHeight + 8, 250)
                    objectName: "bagPlayerCompletionPopup"
                    padding: 4
                    width: pathField.width
                    y: pathField.height

                    background: Rectangle {
                        border.color: palette.mid
                        color: palette.window
                        radius: 4

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -1
                            border.color: Qt.rgba(0, 0, 0, 0.15)
                            color: "transparent"
                            radius: 5
                            z: -1
                        }
                    }

                    ListView {
                        id: completionList

                        anchors.fill: parent
                        clip: true
                        currentIndex: 0
                        model: completionModel
                        objectName: "bagPlayerCompletionList"

                        delegate: ItemDelegate {
                            height: 28
                            highlighted: index === completionList.currentIndex
                            objectName: "bagPlayerCompletionItem_" + index
                            width: completionList.width

                            contentItem: Label {
                                elide: Text.ElideMiddle
                                font.family: "monospace"
                                text: model.path
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
                highlighted: true
                objectName: "bagPlayerScanButton"
                text: "Scan"

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
            objectName: "bagPlayerPlaybackPanel"
        }

        // --------------------------------------------------------------------
        // Bag Browser
        // --------------------------------------------------------------------

        BagBrowser {
            id: bagBrowser

            Layout.fillHeight: true
            Layout.fillWidth: true
            currentPath: context.bag_path ?? "~/bags/"
            objectName: "bagPlayerBagBrowser"
            recorderInterface: scanner
            showPathBar: false

            onPlayRequested: function (bagPath, bagName) {
                playerEngine.load(bagPath);
                // Auto-play after loading
                playerEngine.play([]);
                statusLabel.text = "\u25B6 Playing: " + bagName;
                statusLabel.color = palette.mid;
            }
            onStatusMessage: function (msg, isError) {
                statusLabel.text = (isError ? "\u2717 " : "\u2713 ") + msg;
                statusLabel.color = isError ? Material.color(Material.Red) : Material.color(Material.Green);
                statusResetTimer.restart();
            }
        }

        // --------------------------------------------------------------------
        // Status bar
        // --------------------------------------------------------------------

        Label {
            id: statusLabel

            Layout.fillWidth: true
            color: palette.mid
            elide: Text.ElideMiddle
            objectName: "bagPlayerStatusLabel"
            text: "Select a directory and click Scan to browse bags."

            Timer {
                id: statusResetTimer

                interval: 5000

                onTriggered: {
                    statusLabel.text = "Scanning: " + (context.bag_path ?? "~/bags/");
                    statusLabel.color = palette.mid;
                }
            }
        }
    }
}
