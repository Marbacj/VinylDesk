import Foundation
import Observation
import SwiftUI

public enum DisplayMode: String, CaseIterable, Sendable {
    case vinyl
    case minimalCard
    case dynamicIsland

    public var title: String {
        switch self {
        case .vinyl: return "黑胶唱片摆件"
        case .minimalCard: return "极简桌面小挂件"
        case .dynamicIsland: return "灵动岛"
        }
    }

    public var iconName: String {
        switch self {
        case .vinyl: return "opticaldisc"
        case .minimalCard: return "rectangle.inset.filled"
        case .dynamicIsland: return "capsule.tophalf.filled"
        }
    }

    public var nextMode: DisplayMode {
        switch self {
        case .vinyl: return .minimalCard
        case .minimalCard: return .dynamicIsland
        case .dynamicIsland: return .vinyl
        }
    }
}

public enum WidgetSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    public var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    public var scaleFactor: CGFloat {
        switch self {
        case .small: return 0.84
        case .medium: return 1.0
        case .large: return 1.22
        }
    }
}

public enum WindowLayerMode: String, CaseIterable, Sendable {
    case desktop
    case floating

    public var title: String {
        switch self {
        case .desktop: return "贴桌面层"
        case .floating: return "悬浮置顶"
        }
    }
}

public enum FontStyleOption: String, CaseIterable, Sendable {
    case serif
    case sans
    case rounded

    public var title: String {
        switch self {
        case .serif: return "复古黑胶衬线"
        case .sans: return "现代极简无衬线"
        case .rounded: return "柔和圆体"
        }
    }

    public var design: Font.Design {
        switch self {
        case .serif: return .serif
        case .sans: return .default
        case .rounded: return .rounded
        }
    }
}

public enum TextEffectStyle: String, CaseIterable, Sendable {
    case cinemaSubtitle
    case ambientGlow
    case frostedPill

    public var title: String {
        switch self {
        case .cinemaSubtitle: return "电影字幕（无底框）"
        case .ambientGlow: return "封面流光柔晕"
        case .frostedPill: return "轻雾毛玻璃底框"
        }
    }
}

@MainActor
@Observable
public final class AppSettings {
    private enum Keys {
        static let displayMode = "vinyldesk.displayMode"
        static let widgetSize = "vinyldesk.widgetSize"
        static let windowLayer = "vinyldesk.windowLayer"
        static let isPositionLocked = "vinyldesk.isPositionLocked"
        static let showLyrics = "vinyldesk.showLyrics"
        static let showBilingualLyrics = "vinyldesk.showBilingualLyrics"
        static let fontStyle = "vinyldesk.fontStyle"
        static let textEffect = "vinyldesk.textEffect"
        static let windowOriginX = "vinyldesk.windowOriginX"
        static let windowOriginY = "vinyldesk.windowOriginY"
        static let hasSavedOrigin = "vinyldesk.hasSavedOrigin"
    }

    private let defaults: UserDefaults

    public var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    public var widgetSize: WidgetSize {
        didSet { defaults.set(widgetSize.rawValue, forKey: Keys.widgetSize) }
    }

    public var windowLayer: WindowLayerMode {
        didSet { defaults.set(windowLayer.rawValue, forKey: Keys.windowLayer) }
    }

    public var isPositionLocked: Bool {
        didSet { defaults.set(isPositionLocked, forKey: Keys.isPositionLocked) }
    }

    public var showLyrics: Bool {
        didSet { defaults.set(showLyrics, forKey: Keys.showLyrics) }
    }

    public var showBilingualLyrics: Bool {
        didSet { defaults.set(showBilingualLyrics, forKey: Keys.showBilingualLyrics) }
    }

    public var fontStyle: FontStyleOption {
        didSet { defaults.set(fontStyle.rawValue, forKey: Keys.fontStyle) }
    }

    public var textEffect: TextEffectStyle {
        didSet { defaults.set(textEffect.rawValue, forKey: Keys.textEffect) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawMode = defaults.string(forKey: Keys.displayMode),
           let mode = DisplayMode(rawValue: rawMode) {
            self.displayMode = mode
        } else {
            self.displayMode = .vinyl
        }

        if let rawSize = defaults.string(forKey: Keys.widgetSize),
           let size = WidgetSize(rawValue: rawSize) {
            self.widgetSize = size
        } else {
            self.widgetSize = .medium
        }

        if let rawLayer = defaults.string(forKey: Keys.windowLayer),
           let layer = WindowLayerMode(rawValue: rawLayer) {
            self.windowLayer = layer
        } else {
            self.windowLayer = .floating
        }

        self.isPositionLocked = defaults.bool(forKey: Keys.isPositionLocked)

        if defaults.object(forKey: Keys.showLyrics) == nil {
            self.showLyrics = true
        } else {
            self.showLyrics = defaults.bool(forKey: Keys.showLyrics)
        }

        self.showBilingualLyrics = defaults.bool(forKey: Keys.showBilingualLyrics)

        if let rawFont = defaults.string(forKey: Keys.fontStyle),
           let style = FontStyleOption(rawValue: rawFont) {
            self.fontStyle = style
        } else {
            self.fontStyle = .serif
        }

        if let rawEffect = defaults.string(forKey: Keys.textEffect),
           let effect = TextEffectStyle(rawValue: rawEffect) {
            self.textEffect = effect
        } else {
            self.textEffect = .cinemaSubtitle
        }
    }

    public var savedWindowTopLeft: CGPoint? {
        get {
            guard defaults.bool(forKey: Keys.hasSavedOrigin) else { return nil }
            return CGPoint(
                x: defaults.double(forKey: Keys.windowOriginX),
                y: defaults.double(forKey: Keys.windowOriginY)
            )
        }
        set {
            if let point = newValue {
                defaults.set(true, forKey: Keys.hasSavedOrigin)
                defaults.set(point.x, forKey: Keys.windowOriginX)
                defaults.set(point.y, forKey: Keys.windowOriginY)
            } else {
                defaults.set(false, forKey: Keys.hasSavedOrigin)
            }
        }
    }
}
