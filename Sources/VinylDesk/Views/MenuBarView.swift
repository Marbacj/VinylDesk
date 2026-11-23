import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var settings: AppSettings
    let bridge: AppleMusicBridge
    let loginItemManager: LoginItemManager
    let onResetPosition: () -> Void

    var body: some View {
        // Now playing header summary
        if let track = bridge.currentTrack, bridge.shouldShowWidget {
            Text("\(track.title) — \(track.artist)")
                .lineLimit(1)

            Button(bridge.playbackStatus == .playing ? "暂停播放" : "继续播放") {
                bridge.togglePlayPause()
            }

            Button("下一首") {
                bridge.nextTrack()
            }

            Button("上一首") {
                bridge.previousTrack()
            }

            Divider()
        } else {
            Text("Apple Music 未在播放")
            Button("打开 Apple Music") {
                bridge.openAppleMusic()
            }
            Divider()
        }

        // Display Mode
        Picker("显示形态", selection: $settings.displayMode) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }

        // Widget Size
        Picker("尺寸缩放", selection: $settings.widgetSize) {
            ForEach(WidgetSize.allCases, id: \.self) { size in
                Text(size.title).tag(size)
            }
        }

        // Window Layer
        Picker("窗口层级", selection: $settings.windowLayer) {
            ForEach(WindowLayerMode.allCases, id: \.self) { layer in
                Text(layer.title).tag(layer)
            }
        }

        Toggle("锁定位置", isOn: $settings.isPositionLocked)

        Divider()

        // Lyrics & Typography controls
        Toggle("显示歌词", isOn: Binding(
            get: { settings.showLyrics },
            set: { newValue in
                settings.showLyrics = newValue
                bridge.refreshLyricsForCurrentTrack()
            }
        ))

        Toggle("双语翻译歌词", isOn: Binding(
            get: { settings.showBilingualLyrics },
            set: { newValue in
                settings.showBilingualLyrics = newValue
                bridge.refreshLyricsForCurrentTrack()
            }
        ))
        .disabled(!settings.showLyrics)

        Picker("字体风格", selection: $settings.fontStyle) {
            ForEach(FontStyleOption.allCases, id: \.self) { style in
                Text(style.title).tag(style)
            }
        }

        Picker("歌词文字特效", selection: $settings.textEffect) {
            ForEach(TextEffectStyle.allCases, id: \.self) { effect in
                Text(effect.title).tag(effect)
            }
        }

        Divider()

        // System controls
        Toggle("开机自动启动", isOn: Binding(
            get: { loginItemManager.isEnabled },
            set: { newValue in
                loginItemManager.setEnabled(newValue)
            }
        ))

        Button("重置挂件位置") {
            onResetPosition()
        }

        Divider()

        Button("退出 VinylDesk") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
