import AppKit
import Combine

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    enum OpenTrigger: String, CaseIterable, Identifiable {
        case hover, click
        var id: String { rawValue }
        var title: String { self == .hover ? "On hover" : "On click" }
    }

    enum Glance: String, CaseIterable, Identifiable {
        case context, quota, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .context: return "Context used"
            case .quota: return "Tightest usage limit"
            case .none: return "Nothing"
            }
        }
    }

    enum PanelWidth: String, CaseIterable, Identifiable {
        case compact, regular, wide
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var points: CGFloat {
            switch self {
            case .compact: return 500
            case .regular: return 580
            case .wide: return 680
            }
        }
    }

    enum Display: String, CaseIterable, Identifiable {
        case notch, primary
        var id: String { rawValue }
        var title: String { self == .notch ? "Built-in display (notch)" : "Primary display" }
    }

    private let defaults = UserDefaults.standard

    @Published var openOn: OpenTrigger { didSet { defaults.set(openOn.rawValue, forKey: "openOn") } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var closeDelay: Double { didSet { defaults.set(closeDelay, forKey: "closeDelay") } }
    @Published var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    @Published var glance: Glance { didSet { defaults.set(glance.rawValue, forKey: "glance") } }
    @Published var shrinkWhenIdle: Bool { didSet { defaults.set(shrinkWhenIdle, forKey: "shrinkWhenIdle") } }
    @Published var blink: Bool { didSet { defaults.set(blink, forKey: "blink") } }
    @Published var soundOnAsk: Bool { didSet { defaults.set(soundOnAsk, forKey: "soundOnAsk") } }
    @Published var width: PanelWidth { didSet { defaults.set(width.rawValue, forKey: "width") } }
    @Published var glassDarkness: Double { didSet { defaults.set(glassDarkness, forKey: "glassDarkness") } }
    @Published var display: Display { didSet { defaults.set(display.rawValue, forKey: "display") } }
    @Published var overFullScreen: Bool { didSet { defaults.set(overFullScreen, forKey: "overFullScreen") } }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "openOn": OpenTrigger.hover.rawValue, "hoverDelay": 0.08, "closeDelay": 0.3, "haptics": true,
            "glance": Glance.context.rawValue, "shrinkWhenIdle": true, "blink": true, "soundOnAsk": false,
            "width": PanelWidth.regular.rawValue, "glassDarkness": 0.3, "display": Display.notch.rawValue,
            "overFullScreen": true,
        ])
        openOn = OpenTrigger(rawValue: d.string(forKey: "openOn") ?? "") ?? .hover
        hoverDelay = d.double(forKey: "hoverDelay")
        closeDelay = d.double(forKey: "closeDelay")
        haptics = d.bool(forKey: "haptics")
        glance = Glance(rawValue: d.string(forKey: "glance") ?? "") ?? .context
        shrinkWhenIdle = d.bool(forKey: "shrinkWhenIdle")
        blink = d.bool(forKey: "blink")
        soundOnAsk = d.bool(forKey: "soundOnAsk")
        width = PanelWidth(rawValue: d.string(forKey: "width") ?? "") ?? .regular
        glassDarkness = d.double(forKey: "glassDarkness")
        display = Display(rawValue: d.string(forKey: "display") ?? "") ?? .notch
        overFullScreen = d.bool(forKey: "overFullScreen")
    }
}
