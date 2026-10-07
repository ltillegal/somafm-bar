import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "io.github.ltillegal.somafm-bar"

  property bool opened: false
  property bool copied: false

  property bool playerRunning: false
  property bool playerPaused: false
  property bool playerMuted: false
  property string playerTitle: ""
  property string stationName: "SomaFM"
  property int playerVolume: 70
  property int reportedVolume: 70
  property int pendingVolume: -1
  property bool statusReady: false

  property var audioOutputs: []
  property string audioOutput: ""
  property string outputsBuffer: ""

  readonly property string playerPath: Qt.resolvedUrl("player").toString().replace(/^file:\/\//, "")
  readonly property string statusPath: Quickshell.env("XDG_RUNTIME_DIR") + "/somafm-bar/status.json"

  function singleLineText(value, limit) {
    return String(value || "").replace(/[\r\n\t]+/g, " ").slice(0, limit)
  }

  function safeTooltipText(value) {
    return root.singleLineText(value, 160).replace(/</g, "‹").replace(/>/g, "›")
  }

  function outputLabel(value) {
    var label = root.singleLineText(value, 80)
    return label.length > 30 ? label.slice(0, 29) + "…" : label
  }

  function applyPlayerState(raw) {
    try {
      if (typeof raw !== "string" || raw.length > 65536) return
      var state = JSON.parse(raw || "{}")
      root.playerRunning = state.running === true
      root.playerPaused = state.paused === true
      root.playerMuted = state.muted === true
      var nextVolume = Math.round(Number(state.volume === undefined ? 70 : state.volume))
      root.reportedVolume = isFinite(nextVolume)
        ? Math.max(0, Math.min(100, nextVolume)) : 70
      if (root.pendingVolume < 0) root.playerVolume = root.reportedVolume
      root.playerTitle = root.singleLineText(
        state.title || "", 160)
      root.audioOutput = root.singleLineText(state.output, 160)
      var station = root.singleLineText(state.station && state.station.name, 80)
      if (station !== "") root.stationName = station
    } catch (error) {
      return
    }
  }

  function refreshStatus() {
    if (statusProcess.running) return
    statusProcess.command = [root.playerPath, "status"]
    statusProcess.running = true
  }

  function runPlayerAction(action) {
    if (actionProcess.running) return
    actionProcess.command = [root.playerPath, action]
    actionProcess.running = true
  }

  function loadOutputs() {
    if (outputsProcess.running) return
    root.outputsBuffer = ""
    outputsProcess.command = [root.playerPath, "outputs"]
    outputsProcess.running = true
  }

  function selectOutput(id) {
    if (typeof id !== "string" || id === "") return
    if (id === root.audioOutput) return
    if (outputProcess.running) return
    outputProcess.command = [root.playerPath, "output", id]
    outputProcess.running = true
  }

  function changeVolume(delta) {
    var current = pendingVolume >= 0 ? pendingVolume : playerVolume
    pendingVolume = Math.max(0, Math.min(100, current + (delta > 0 ? 5 : -5)))
    playerVolume = pendingVolume
    flushVolume()
  }

  function flushVolume() {
    if (actionProcess.running || pendingVolume < 0) return
    actionProcess.submittedVolume = pendingVolume
    actionProcess.command = [playerPath, "volume", String(pendingVolume)]
    actionProcess.running = true
  }

  function open() {
    root.opened = true
    root.refreshStatus()
    root.loadOutputs()
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function copyTitle() {
    if (root.playerTitle === "") return
    Quickshell.execDetached(["wl-copy", root.playerTitle])
    root.copied = true
    closeTimer.restart()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    path: root.statusReady ? root.statusPath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyPlayerState(text())
    onFileChanged: reload()
  }

  Process {
    id: statusProcess
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) root.statusReady = true
    }
  }

  Process {
    id: actionProcess
    property int submittedVolume: -1
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) root.statusReady = true
      if (submittedVolume >= 0) {
        root.statusReady = true
        if (exitCode === 0) {
          root.reportedVolume = submittedVolume
          if (root.pendingVolume === submittedVolume) {
            root.pendingVolume = -1
            root.playerVolume = submittedVolume
          } else {
            Qt.callLater(root.flushVolume)
            return
          }
        } else {
          if (root.pendingVolume === submittedVolume) {
            root.pendingVolume = -1
            root.playerVolume = root.reportedVolume
          } else {
            Qt.callLater(root.flushVolume)
          }
        }
        submittedVolume = -1
      }
    }
  }

  Process {
    id: outputsProcess
    command: []
    stdout: SplitParser {
      onRead: function(line) { root.outputsBuffer += line }
    }
    onExited: function(exitCode) {
      var buffer = root.outputsBuffer
      root.outputsBuffer = ""
      if (exitCode !== 0) return
      var list = []
      try {
        var parsed = JSON.parse(buffer || "{}")
        var items = parsed && parsed.outputs
        if (items && typeof items.length === "number") {
          for (var i = 0; i < items.length; i++) {
            var item = items[i]
            if (!item || typeof item.id !== "string" || item.id === "") continue
            list.push({
              id: item.id,
              label: root.singleLineText(item.label || item.id, 80)
            })
          }
        }
      } catch (error) {
        return
      }
      root.audioOutputs = list
    }
  }

  Process {
    id: outputProcess
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) root.loadOutputs()
      root.refreshStatus()
    }
  }

  Component.onCompleted: {
    root.refreshStatus()
    root.loadOutputs()
  }

  Timer {
    id: closeTimer
    interval: 200
    onTriggered: {
      root.copied = false
      root.close()
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf001"
    active: root.playerRunning && !root.playerPaused
    tooltipText: root.playerRunning
      ? (root.playerPaused ? "Soma paused: " : "Soma playing: ")
        + root.safeTooltipText(root.playerTitle)
        + "  ·  " + root.playerVolume + "%"
      : root.stationName

    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton) {
        root.runPlayerAction("stop")
        return
      }
      if (mouseButton === Qt.MiddleButton) {
        root.runPlayerAction(root.playerRunning ? "toggle" : "play")
        return
      }
      root.toggle()
    }

    onWheelMoved: function(delta) {
      root.changeVolume(delta)
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(popupColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: popupColumn
        anchors.fill: parent
        spacing: Style.spacing.controlGap

        Row {
          id: titleRow
          width: popupColumn.width
          spacing: Style.spacing.controlGap

          Text {
            width: titleRow.width - copyButton.width - titleRow.spacing
            text: root.playerTitle !== "" ? root.playerTitle : root.stationName
            textFormat: Text.PlainText
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.WordWrap
          }

          PanelActionButton {
            id: copyButton
            iconText: root.copied ? "\uf00c" : "\uf0c5"
            tooltipText: root.copied ? "Copied" : "Copy title"
            enabled: root.playerTitle !== ""
            onClicked: root.copyTitle()
          }
        }

        Text {
          width: popupColumn.width
          text: root.playerRunning
            ? (root.playerPaused ? "Paused" : "Playing")
              + (root.playerMuted ? "  ·  muted" : "  ·  " + root.playerVolume + "%")
            : "Stopped — press Play to start"
          textFormat: Text.PlainText
          color: Color.foreground
          opacity: 0.65
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Row {
          spacing: Style.spacing.controlGap

          Button {
iconText: root.playerRunning && !root.playerPaused ? "\uf04c" : "\uf04b"
            text: root.playerRunning && !root.playerPaused ? "Pause" : "Play"
            active: root.playerRunning && !root.playerPaused
            onClicked: root.runPlayerAction(root.playerRunning ? "toggle" : "play")
          }

          Button {
            iconText: "\uf04d"
            text: "Stop"
            onClicked: root.runPlayerAction("stop")
          }
        }

        PanelSlider {
          id: volumeSlider
          width: popupColumn.width
          bar: root.bar
          value: root.playerVolume
          minimum: 0
          maximum: 100
          step: 5
          integer: true
          onMoved: function(value) {
            root.pendingVolume = value
            root.playerVolume = value
          }
          onReleased: root.flushVolume()
          onRightClicked: root.runPlayerAction(root.playerRunning ? "toggle" : "play")
        }

        Column {
          id: outputColumn
          width: popupColumn.width
          spacing: Style.spacing.controlGap
          visible: root.audioOutputs.length > 0

          Text {
            width: outputColumn.width
            text: "Output"
            textFormat: Text.PlainText
            color: Color.foreground
            opacity: 0.65
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Repeater {
            model: root.audioOutputs
            delegate: Button {
              width: outputColumn.width
              text: root.outputLabel(modelData.label)
              leftAlign: true
              selected: modelData.id === root.audioOutput
              tooltipText: root.safeTooltipText(modelData.label)
              onClicked: root.selectOutput(modelData.id)
            }
          }
        }
      }
    }
  }
}
