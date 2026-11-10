import SwiftUI

enum Tone {
    static let working = Color(red: 0.38, green: 0.66, blue: 1.0)
    static let waiting = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let idle = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let muted = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.08)

    static func of(_ agent: Agent) -> Color {
        if agent.needsInput { return waiting }
        if agent.isWorking { return working }
        if agent.state == "idle" { return idle }
        return .gray
    }

    static func meter(_ fraction: Double) -> Color {
        fraction < 0.6 ? idle : fraction < 0.85 ? .yellow : .red
    }
}

enum Motion {
    private static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static var open: Animation { reduced ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.84) }
    static var close: Animation { reduced ? .easeOut(duration: 0.18) : .spring(duration: 0.3, bounce: 0) }
    static var content: Animation { reduced ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.1) }
    static var reveal: Animation { reduced ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2).delay(0.06) }
    static var conceal: Animation { .easeIn(duration: 0.12) }
    static var peek: Animation { reduced ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.86) }
}

struct BlurReveal: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.97, anchor: .top)
            .offset(y: shown ? 0 : -6)
    }
}

extension AnyTransition {
    static var blurReveal: AnyTransition {
        .modifier(active: BlurReveal(shown: false), identity: BlurReveal(shown: true))
    }
}

struct GlassSurface<S: Shape>: View {
    let shape: S
    let shown: Bool
    let darkness: Double

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                if shown {
                    Color.clear
                        .glassEffect(.regular.tint(darkness > 0 ? Color.black.opacity(darkness) : nil), in: shape)
                        .glassEffectTransition(.materialize)
                }
            }
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.black.opacity(darkness)))
                .opacity(shown ? 1 : 0)
        }
    }
}

extension View {
    func controlSurface<S: InsettableShape>(_ shape: S, fill: Color = Color.white.opacity(0.08)) -> some View {
        background(shape.fill(fill).overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)))
    }
}

struct NotchRoot: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: NotchUI
    let onSize: (CGSize) -> Void
    @ObservedObject private var prefs = Preferences.shared
    @State private var expandedHeight: CGFloat = 0

    private var wings: Bool { store.isActive || !prefs.shrinkWhenIdle }

    private var size: CGSize {
        guard ui.expanded else {
            let closed = wings ? ui.geometry.collapsedSize : ui.geometry.compactSize
            return ui.peeking ? CGSize(width: closed.width + 8, height: closed.height + 4) : closed
        }
        return CGSize(width: prefs.width.points,
                      height: max(expandedHeight, ui.geometry.notchHeight + 40))
    }

    var body: some View {
        ZStack(alignment: .top) {
            panel
            ExpandedView(store: store, ui: ui)
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { expandedHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, height in
                            if ui.expanded {
                                withAnimation(Motion.content) { expandedHeight = height }
                            } else {
                                expandedHeight = height
                            }
                        }
                })
                .modifier(BlurReveal(shown: ui.expanded))
                .animation(ui.expanded ? Motion.reveal : Motion.conceal, value: ui.expanded)
                .allowsHitTesting(ui.expanded)
                .accessibilityHidden(!ui.expanded)
            CollapsedBar(store: store, geometry: ui.geometry, wings: wings)
                .opacity(ui.expanded ? 0 : (store.live ? 1 : 0.45))
                .animation(.easeInOut(duration: ui.expanded ? 0.12 : 0.28), value: ui.expanded)
                .allowsHitTesting(!ui.expanded)
                .contentShape(Rectangle())
                .onTapGesture { ui.requestExpand() }
                .contextMenu {
                    Button("Settings…") { SettingsWindow.shared.show() }
                    Divider()
                    Button("Quit Agent Notch") { NSApp.terminate(nil) }
                }
        }
        .animation(Motion.content, value: wings)
        .animation(Motion.content, value: prefs.width)
        .animation(Motion.peek, value: ui.peeking)
        .frame(width: NotchGeometry.canvasWidth, height: ui.canvasHeight, alignment: .top)
        .onAppear { onSize(size) }
        .onChange(of: size) { _, next in onSize(next) }
        .environment(\.colorScheme, .dark)
    }

    private var panel: some View {
        let shape = NotchShape(ear: NotchGeometry.ear, radius: ui.expanded ? 26 : 9)
        return ZStack(alignment: .top) {
            GlassSurface(shape: shape, shown: ui.expanded, darkness: prefs.glassDarkness)
            VStack(spacing: 0) {
                Color.black.frame(height: ui.geometry.notchHeight)
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
                Spacer(minLength: 0)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .opacity(ui.expanded ? 1 : 0)
            shape.fill(Color.black).opacity(ui.expanded ? 0 : 1)
        }
        .frame(width: size.width, height: size.height)
    }
}

struct NotchShape: Shape {
    var ear: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = max(0, min(radius, (w - 2 * ear) / 2, h - ear))
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: ear, y: ear), control: CGPoint(x: ear, y: 0))
        p.addLine(to: CGPoint(x: ear, y: h - r))
        p.addQuadCurve(to: CGPoint(x: ear + r, y: h), control: CGPoint(x: ear, y: h))
        p.addLine(to: CGPoint(x: w - ear - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - ear, y: h - r), control: CGPoint(x: w - ear, y: h))
        p.addLine(to: CGPoint(x: w - ear, y: ear))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - ear, y: 0))
        p.closeSubpath()
        return p
    }
}

struct CollapsedBar: View {
    @ObservedObject var store: Store
    let geometry: NotchGeometry
    let wings: Bool

    var body: some View {
        if wings {
            HStack(spacing: 0) {
                StatusGlyph(store: store)
                    .padding(.leading, 12)
                    .frame(width: NotchGeometry.wing, alignment: .leading)
                Color.clear.frame(width: geometry.notchWidth)
                HStack(spacing: 7) {
                    UsageGlance(store: store)
                    if store.anyNeedsInput { BlinkingDot() }
                }
                .padding(.trailing, 12)
                .frame(width: NotchGeometry.wing, alignment: .trailing)
            }
            .padding(.horizontal, NotchGeometry.ear)
            .frame(height: geometry.notchHeight)
            .transition(.opacity)
        } else {
            Color.clear.frame(width: geometry.compactSize.width, height: geometry.notchHeight)
        }
    }
}

struct StatusGlyph: View {
    @ObservedObject var store: Store

    var body: some View {
        HStack(spacing: 5) {
            if store.workingCount > 0 {
                WorkingBars(color: Tone.working)
                if store.workingCount > 1 {
                    Text("\(store.workingCount)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Tone.working)
                }
            } else if store.anyNeedsInput {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(Tone.waiting)
            } else if store.agents.isEmpty {
                Image(systemName: "moon.zzz.fill").foregroundStyle(Tone.muted)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Tone.idle)
            }
        }
        .font(.system(size: 13))
    }
}

struct UsageGlance: View {
    @ObservedObject var store: Store
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        switch prefs.glance {
        case .none:
            EmptyView()
        case .quota:
            if let q = store.quotas.first { quota(q) }
        case .context:
            if let ctx = store.primary?.context {
                HStack(spacing: 4) {
                    Ring(value: ctx.fraction, tint: Tone.meter(ctx.fraction))
                    Text(ctx.label ?? percent(ctx.fraction))
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
            } else if let q = store.quotas.first {
                quota(q)
            }
        }
    }

    private func quota(_ q: Quota) -> some View {
        Text("\(q.short ?? "") \(percent(q.used))")
            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .foregroundStyle(Tone.meter(q.used))
    }
}

struct ExpandedView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: NotchUI
    private static let spacing: CGFloat = 12
    private static let bottomPadding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            header
            if !store.agents.isEmpty {
                AgentTabs(store: store, selected: store.selected?.pane ?? Store.newAgent)
                    .background(heightReader { ui.tabsHeight = $0 })
            }
            ZStack(alignment: .top) {
                CappedScroll(maxHeight: middleMaxHeight) {
                    if let agent = store.selected {
                        VStack(alignment: .leading, spacing: Self.spacing) {
                            AgentCard(store: store, agent: agent)
                            if let dialog = agent.dialog {
                                DialogView(store: store, agent: agent, dialog: dialog)
                            } else if agent.needsInput {
                                WaitingFallback(store: store, agent: agent)
                            }
                        }
                    } else {
                        NewAgentCard(store: store)
                    }
                }
                .id(store.selected?.pane ?? Store.newAgent)
                .transition(.blurReveal)
            }
            footer
                .background(heightReader { ui.footerHeight = $0 })
        }
        .padding(.horizontal, 18 + NotchGeometry.ear)
        .padding(.bottom, Self.bottomPadding)
        .frame(width: Preferences.shared.width.points)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
        .onExitCommand { ui.requestCollapse() }
    }

    private func heightReader(_ set: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { set(geo.size.height) }
                .onChange(of: geo.size.height) { _, height in set(height) }
        }
    }

    private var middleMaxHeight: CGFloat {
        let tabs = store.agents.isEmpty ? 0 : ui.tabsHeight + Self.spacing
        return max(120, ui.maxHeight - ui.geometry.notchHeight - tabs - ui.footerHeight
            - 2 * Self.spacing - Self.bottomPadding)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Composer(store: store, ui: ui, agent: store.selected)
            if let toast = store.toast {
                Label(toast.text, systemImage: toast.level == "error" ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(toast.level == "error" ? Color.red : Tone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                StatusGlyph(store: store)
                Text(summary).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: ui.geometry.notchWidth)
            HStack(spacing: 7) {
                UsageGlance(store: store)
                if store.anyNeedsInput { BlinkingDot() }
                Button { SettingsWindow.shared.show() } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(Tone.muted)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: ui.geometry.notchHeight)
    }

    private var summary: String {
        if !store.live { return "Waiting for Tern…" }
        let agents = store.agents
        if agents.isEmpty { return "No agents" }
        var parts: [String] = []
        let working = agents.filter(\.isWorking).count
        let waiting = agents.filter(\.needsInput).count
        if working > 0 { parts.append("\(working) working") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        return parts.isEmpty ? "\(agents.count) idle" : parts.joined(separator: " · ")
    }
}

struct Segment: Identifiable {
    let id: String
    let label: String
    var dot: Color? = nil
    var done = false
    var flagged = false
}

struct SegmentedTabs: View {
    let segments: [Segment]
    let selected: String?
    var fontSize: CGFloat = 12
    let onSelect: (String) -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                let on = segment.id == selected
                Button { withAnimation(Motion.content) { onSelect(segment.id) } } label: {
                    HStack(spacing: 6) {
                        if segment.done {
                            Image(systemName: "checkmark").font(.system(size: fontSize - 3, weight: .bold))
                                .foregroundStyle(Tone.idle)
                        } else if let dot = segment.dot {
                            Circle().fill(dot).frame(width: 7, height: 7)
                                .shadow(color: dot.opacity(on ? 0.8 : 0), radius: 3)
                        }
                        Text(segment.label).font(.system(size: fontSize, weight: on ? .semibold : .medium)).lineLimit(1)
                        if segment.flagged {
                            Circle().fill(Tone.waiting).frame(width: 5, height: 5)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(on ? Color.white : Color.white.opacity(0.6))
                    .background {
                        if on {
                            Capsule().fill(Color.white.opacity(0.17))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                                .matchedGeometryEffect(id: "selection", in: selection)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .id(segment.id)
            }
        }
        .padding(3)
        .controlSurface(Capsule(), fill: Color.white.opacity(0.06))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > limit {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

struct AgentTabs: View {
    @ObservedObject var store: Store
    let selected: Int

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                SegmentedTabs(
                    segments: store.agents.map {
                        Segment(id: String($0.pane), label: $0.shortTitle, dot: Tone.of($0),
                                flagged: $0.needsInput && $0.pane != selected)
                    } + [Segment(id: String(Store.newAgent), label: "+ New")],
                    selected: String(selected)
                ) { id in store.selectedPane = Int(id) }
                .fixedSize()
            }
            .onAppear { reader.scrollTo(String(selected), anchor: .center) }
            .onChange(of: selected) { _, now in
                withAnimation(Motion.content) { reader.scrollTo(String(now), anchor: .center) }
            }
        }
    }
}

struct AgentCard: View {
    @ObservedObject var store: Store
    let agent: Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(Tone.of(agent)).frame(width: 8, height: 8)
                Text(agent.title.isEmpty ? (agent.program ?? "Agent") : agent.title)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { store.focus(agent) } label: {
                    Label("Show in Tern", systemImage: "arrow.up.forward.app").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(Tone.muted)
            }
            if !meta.isEmpty {
                Text(meta).font(.system(size: 11)).foregroundStyle(Tone.muted).lineLimit(1).truncationMode(.middle)
            }
            statusLine
            if let ctx = agent.context {
                HStack(spacing: 8) {
                    Text("Context").font(.system(size: 11)).foregroundStyle(Tone.muted)
                    Meter(value: ctx.fraction, tint: Tone.meter(ctx.fraction)).frame(width: 140)
                    Text([ctx.label, ctx.detail].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    Spacer(minLength: 0)
                    if let cost = agent.cost {
                        Text(cost.first?.isNumber == true ? "$\(cost)" : cost)
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let cwd = agent.cwd, !cwd.isEmpty {
            parts.append(cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var statusLine: some View {
        if agent.isWorking {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let since = store.workingSince[agent.pane].map { " · " + elapsed(from: $0, to: context.date) } ?? ""
                (Text("Working").foregroundStyle(Tone.working)
                    + Text(agent.activity.map { "  " + $0 } ?? "")
                    + Text(since).foregroundStyle(Tone.muted))
                    .font(.system(size: 12)).monospacedDigit()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if agent.needsInput {
            Text("Waiting for you").font(.system(size: 12, weight: .medium)).foregroundStyle(Tone.waiting)
        } else if let last = agent.last {
            Text(last).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
        } else {
            Text("Idle").font(.system(size: 12)).foregroundStyle(Tone.muted)
        }
    }
}

struct DialogView: View {
    @ObservedObject var store: Store
    let agent: Agent
    let dialog: Dialog

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let eyebrow = dialog.eyebrow {
                Text(eyebrow.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(Tone.waiting)
            }
            if let tabs = dialog.tabs, tabs.items.count > 1 {
                SegmentedTabs(
                    segments: tabs.items.map { Segment(id: $0.id, label: $0.label, done: $0.done == true) },
                    selected: tabs.active,
                    fontSize: 11
                ) { id in
                    if let tab = tabs.items.first(where: { $0.id == id }) { store.selectTab(tab, in: tabs, agent: agent) }
                }
            }
            if let title = dialog.title {
                Text(title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            if let notice = dialog.notice {
                Text(notice).font(.system(size: 11)).foregroundStyle(Tone.muted)
            }
            if let answers = dialog.answers, !answers.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(answers, id: \.self) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.k).foregroundStyle(Tone.muted)
                            Text(row.v)
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            if let list = dialog.list, !list.items.isEmpty { options(list) }
            if dialog.kind == "answer" {
                Text("Type the answer in the field below; Return sends it.")
                    .font(.system(size: 11)).foregroundStyle(Tone.muted)
            }
            if let buttons = dialog.buttons, !buttons.isEmpty {
                HStack(spacing: 6) {
                    ForEach(buttons.filter { $0.primary != true }) { button in action(button) }
                    Spacer(minLength: 0)
                    ForEach(buttons.filter { $0.primary == true }) { button in action(button) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Tone.waiting.opacity(0.4), lineWidth: 0.75))
        )
    }

    private func options(_ list: OptionList) -> some View {
        VStack(spacing: 5) {
            ForEach(Array(list.items.enumerated()), id: \.element.id) { index, option in
                OptionRow(option: option, index: index, pending: store.pending.contains(option.id)) {
                    store.pick(option, in: list, agent: agent)
                }
            }
        }
    }

    private func action(_ button: DialogButton) -> some View {
        let primary = button.primary == true
        return Button { store.press(button, agent: agent) } label: {
            HStack(spacing: 5) {
                if store.pending.contains(button.id) { ProgressView().controlSize(.mini) }
                Text(button.label).font(.system(size: 11.5, weight: .semibold))
            }
            .padding(.horizontal, 13).padding(.vertical, 6)
            .foregroundStyle(primary ? Color.black : Color.white)
            .contentShape(Capsule())
            .controlSurface(Capsule(), fill: primary ? Tone.waiting : Color.white.opacity(0.12))
        }
        .buttonStyle(.plain)
    }
}

struct OptionRow: View {
    let option: DialogOption
    let index: Int
    let pending: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                marker.frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(.system(size: 12.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = option.detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(Tone.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                if pending {
                    ProgressView().controlSize(.small)
                } else if let badge = option.badge {
                    Text(badge).font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(Tone.idle)
                        .background(Capsule().fill(Tone.idle.opacity(0.16)))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.14 : 0.06)))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(option.disabled == true)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var marker: some View {
        switch option.kind {
        case "check":
            Image(systemName: option.checked == true ? "checkmark.square.fill" : "square")
                .font(.system(size: 13)).foregroundStyle(option.checked == true ? Tone.waiting : Tone.muted)
        case "other":
            Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(Tone.muted)
        default:
            Text("\(index + 1)").font(.system(size: 10, weight: .bold)).monospacedDigit()
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
    }
}

struct WaitingFallback: View {
    @ObservedObject var store: Store
    let agent: Agent

    var body: some View {
        HStack {
            Text("This agent is waiting for input in Tern.").font(.system(size: 12))
            Spacer()
            Button("Show in Tern") { store.focus(agent) }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Tone.waiting)).foregroundStyle(.black)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Tone.waiting.opacity(0.1)))
    }
}

struct NewAgentCard: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Tone.working)
                Text("New agent").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            Text("Starts omp in a new Tern tab in \(tilde(store.state?.launch?.cwd ?? NSHomeDirectory())), the folder of Tern's focused pane.")
                .font(.system(size: 12)).foregroundStyle(Tone.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Composer: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: NotchUI
    let agent: Agent?
    @State private var text = ""
    @State private var focused = false
    @State private var focusToken = 0
    @State private var highlight = 0
    @State private var dismissedAt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !suggestions.isEmpty { suggestionList }
            HStack(spacing: 8) {
                Image(systemName: text.hasPrefix("/") ? "command" : (agent == nil ? "sparkles" : "text.bubble"))
                    .font(.system(size: 12)).foregroundStyle(Tone.muted)
                CommandField(text: $text, placeholder: placeholder, focused: $focused,
                             focusToken: focusToken, onCommand: handle)
                    .frame(height: 20)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 18))
                        .foregroundStyle(trimmed.isEmpty ? Tone.muted : Color.white)
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .controlSurface(RoundedRectangle(cornerRadius: 14, style: .continuous),
                            fill: Color.white.opacity(focused ? 0.12 : 0.08))
            ComposerFacts(store: store, agent: agent)
        }
        .onChange(of: focused) { _, _ in syncHold() }
        .onChange(of: text) { _, _ in
            highlight = 0
            syncHold()
        }
        .onChange(of: ui.expanded) { _, open in
            if open, agent?.dialog?.kind == "answer" { focusToken += 1 }
        }
        .onChange(of: agent?.dialog?.kind) { _, kind in
            if ui.expanded, kind == "answer" { focusToken += 1 }
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var placeholder: String {
        guard let agent else { return "Ask a new agent — / runs a command" }
        switch agent.dialog?.kind {
        case "answer": return "Type your answer…"
        case "ask": return "Type a different answer…"
        default: return "Message \(agent.shortTitle) — / runs a command"
        }
    }

    private var query: String { String(text.dropFirst()).lowercased() }

    private var suggestions: [SlashCommand] {
        guard text.hasPrefix("/"), !text.contains(" "), dismissedAt != text, agent?.dialog == nil else { return [] }
        let all = store.commands
        let prefix = all.filter { $0.name.lowercased().hasPrefix(query) }
        let inside = query.isEmpty ? [] : all.filter {
            !$0.name.lowercased().hasPrefix(query) && $0.name.lowercased().contains(query)
        }
        return Array((prefix + inside).prefix(6))
    }

    private var current: SlashCommand? {
        let list = suggestions
        return list.isEmpty ? nil : list[min(highlight, list.count - 1)]
    }

    private var suggestionList: some View {
        VStack(spacing: 1) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, command in
                Button { complete(command) } label: {
                    HStack(spacing: 8) {
                        Text("/" + command.name).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        if let hint = command.hint {
                            Text(hint).font(.system(size: 11, design: .monospaced)).foregroundStyle(Tone.muted).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if let description = command.description {
                            Text(description).font(.system(size: 11)).foregroundStyle(Tone.muted).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(index == min(highlight, suggestions.count - 1) ? Color.white.opacity(0.14) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func complete(_ command: SlashCommand) {
        text = "/" + command.name + " "
        focusToken += 1
    }

    private func handle(_ key: CommandField.Key) -> Bool {
        let count = suggestions.count
        switch key {
        case .up where count > 0:
            highlight = (min(highlight, count - 1) - 1 + count) % count
            return true
        case .down where count > 0:
            highlight = (min(highlight, count - 1) + 1) % count
            return true
        case .tab:
            if let current { complete(current) }
            return true
        case .enter:
            if let current, current.name.lowercased() != query {
                complete(current)
            } else {
                send()
            }
            return true
        case .escape:
            if count > 0 { dismissedAt = text } else { ui.requestCollapse() }
            return true
        default:
            return false
        }
    }

    private func syncHold() { ui.holdOpen = focused && !trimmed.isEmpty }

    private func send() {
        guard !trimmed.isEmpty else { return }
        if let agent {
            store.submit(trimmed, agent: agent)
        } else {
            store.startAgent(trimmed)
        }
        text = ""
    }
}

struct ComposerFacts: View {
    @ObservedObject var store: Store
    let agent: Agent?

    private static let efforts = ["off", "minimal", "low", "medium", "high", "xhigh", "max", "auto"]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            modelMenu
            effortMenu
            if let cwd = store.targetCwd {
                Chip(icon: "folder", text: (cwd as NSString).lastPathComponent)
                    .help(tilde(cwd))
                if let folder = store.folder(cwd), let branch = folder.branch {
                    GitChip(branch: branch, added: folder.added ?? 0, removed: folder.removed ?? 0, files: folder.files ?? 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelLabel: String {
        if let agent { return agent.model ?? "Model" }
        if let selector = store.newModel {
            return store.models.first(where: { $0.selector == selector })?.name ?? selector
        }
        return "Default model"
    }

    private var providers: [String] {
        let all = Set(store.models.map(\.provider))
        let first = ["anthropic", "openai-codex", "openai"].filter(all.contains)
        return first + all.subtracting(first).sorted()
    }

    private func isCurrent(_ model: ModelEntry) -> Bool {
        if let agent, let name = agent.model { return model.name == name || model.name.hasSuffix(" " + name) }
        return model.selector == store.newModel
    }

    private var modelMenu: some View {
        Menu {
            if agent == nil {
                Button { store.newModel = nil } label: { checked("Default model", store.newModel == nil) }
                Divider()
            }
            ForEach(providers, id: \.self) { provider in
                Menu(provider) {
                    ForEach(store.models.filter { $0.provider == provider }) { model in
                        Button { choose(model) } label: { checked(model.name, isCurrent(model)) }
                    }
                }
            }
        } label: {
            Chip(icon: "cpu", text: modelLabel, emphasized: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(store.models.isEmpty)
    }

    private func choose(_ model: ModelEntry) {
        if let agent { store.setModel(model.selector, agent: agent) } else { store.newModel = model.selector }
    }

    private var effortLabel: String {
        if let agent { return agent.effort ?? "effort" }
        return store.newEffort ?? "default effort"
    }

    private var levels: [String] {
        if agent == nil, let selector = store.newModel,
           let thinking = store.models.first(where: { $0.selector == selector })?.thinking, !thinking.isEmpty {
            return ["off"] + thinking + ["auto"]
        }
        return Self.efforts
    }

    private var effortMenu: some View {
        Menu {
            if agent == nil {
                Button { store.newEffort = nil } label: { checked("Default", store.newEffort == nil) }
                Divider()
            }
            ForEach(levels, id: \.self) { level in
                Button {
                    if let agent { store.setEffort(level, agent: agent) } else { store.newEffort = level }
                } label: {
                    checked(level, (agent?.effort ?? store.newEffort) == level)
                }
            }
        } label: {
            Chip(icon: "brain", text: effortLabel)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder private func checked(_ title: String, _ on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

struct Chip: View {
    let icon: String
    let text: String
    var emphasized = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9.5, weight: .semibold))
            Text(text).font(.system(size: 11, weight: emphasized ? .semibold : .medium)).lineLimit(1)
        }
        .foregroundStyle(emphasized ? Color.white : Color.white.opacity(0.75))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .contentShape(Capsule())
    }
}

struct GitChip: View {
    let branch: String
    let added: Int
    let removed: Int
    let files: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 9.5, weight: .semibold))
            Text(branch).font(.system(size: 11, weight: .medium)).lineLimit(1)
            if added > 0 || removed > 0 {
                Text("+\(added)").foregroundStyle(Tone.idle)
                Text("−\(removed)").foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
            }
        }
        .font(.system(size: 11, weight: .semibold).monospacedDigit())
        .foregroundStyle(Color.white.opacity(0.75))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .help(files == 0 ? "No changes since HEAD" : "\(files) file\(files == 1 ? "" : "s") changed since HEAD")
    }
}

func tilde(_ path: String) -> String {
    path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
}

struct CommandField: NSViewRepresentable {
    enum Key { case up, down, tab, enter, escape }

    @Binding var text: String
    var placeholder: String
    @Binding var focused: Bool
    var focusToken: Int
    var onCommand: (Key) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 13),
        ])
        if focusToken != coordinator.focusToken {
            coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                window.makeKey()
                window.makeFirstResponder(field)
                field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandField
        var focusToken: Int

        init(_ parent: CommandField) {
            self.parent = parent
            focusToken = parent.focusToken
        }

        func controlTextDidChange(_ note: Notification) {
            if let field = note.object as? NSTextField { parent.text = field.stringValue }
        }

        func controlTextDidBeginEditing(_ note: Notification) { parent.focused = true }
        func controlTextDidEndEditing(_ note: Notification) { parent.focused = false }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): return parent.onCommand(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.onCommand(.down)
            case #selector(NSResponder.insertTab(_:)): return parent.onCommand(.tab)
            case #selector(NSResponder.insertNewline(_:)): return parent.onCommand(.enter)
            case #selector(NSResponder.cancelOperation(_:)): return parent.onCommand(.escape)
            default: return false
            }
        }
    }
}

struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content.background(GeometryReader { geo in
                Color.clear
                    .onAppear { height = geo.size.height }
                    .onChange(of: geo.size.height) { _, next in withAnimation(Motion.content) { height = next } }
            })
        }
        .defaultScrollAnchor(.top)
        .scrollIndicators(height > maxHeight ? .automatic : .hidden)
        .frame(height: min(height, maxHeight))
    }
}

struct Meter: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(tint).frame(width: max(4, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 5)
    }
}

struct Ring: View {
    let value: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 2.5)
            Circle().trim(from: 0, to: min(max(value, 0.02), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
    }
}

private let loopFrameRate = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)

struct WorkingBars: NSViewRepresentable {
    let color: Color

    private static let size = CGSize(width: 16, height: 13)
    private static let barWidth: CGFloat = 2.5
    private static let envelope: [CGFloat] = [0.62, 1.0, 0.86, 0.55]
    private static let periods: [CFTimeInterval] = [0.82, 0.67, 0.94, 0.74]

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: Self.size))
        view.wantsLayer = true
        let spacing = Self.barWidth * 1.85
        let start = (Self.size.width - spacing * 3 - Self.barWidth) / 2
        for index in 0..<4 {
            let bar = CALayer()
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.size.height)
            bar.position = CGPoint(x: start + CGFloat(index) * spacing + Self.barWidth / 2, y: Self.size.height / 2)
            bar.cornerRadius = Self.barWidth / 2
            bar.backgroundColor = NSColor(color).cgColor
            let top = Self.envelope[index]
            let swing = CAKeyframeAnimation(keyPath: "transform.scale.y")
            swing.values = [0.28, top, 0.42, top * 0.78, 0.28]
            swing.keyTimes = [0, 0.3, 0.55, 0.8, 1]
            swing.calculationMode = .cubic
            swing.duration = Self.periods[index]
            swing.repeatCount = .infinity
            swing.isRemovedOnCompletion = false
            swing.timeOffset = Double(index) * 0.17
            swing.preferredFrameRateRange = loopFrameRate
            bar.transform = CATransform3DMakeScale(1, 0.28, 1)
            bar.add(swing, forKey: "swing")
            view.layer?.addSublayer(bar)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        Self.size
    }
}

struct BlinkingDot: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        PulseDot(blinking: prefs.blink).id(prefs.blink)
    }
}

struct PulseDot: NSViewRepresentable {
    let blinking: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        view.wantsLayer = true
        let color = NSColor(Tone.waiting).cgColor
        let dot = CALayer()
        dot.frame = CGRect(x: 3, y: 3, width: 8, height: 8)
        dot.cornerRadius = 4
        dot.backgroundColor = color
        dot.shadowColor = color
        dot.shadowOpacity = 0.9
        dot.shadowRadius = 3
        dot.shadowOffset = .zero
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0.15
        blink.duration = 0.55
        blink.autoreverses = true
        blink.repeatCount = .infinity
        blink.isRemovedOnCompletion = false
        blink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        blink.preferredFrameRateRange = loopFrameRate
        if blinking { dot.add(blink, forKey: "blink") }
        view.layer?.addSublayer(dot)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: 14, height: 14)
    }
}

func percent(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
}

func elapsed(from start: Date, to now: Date) -> String {
    let s = max(0, Int(now.timeIntervalSince(start)))
    return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m \(s % 60)s" : "\(s / 3600)h \(s / 60 % 60)m"
}

func duration(until epoch: Double, from now: Date) -> String {
    let s = max(0, Int(epoch - now.timeIntervalSince1970))
    if s >= 86400 { return "\(s / 86400)d \(s / 3600 % 24)h" }
    if s >= 3600 { return "\(s / 3600)h \(s / 60 % 60)m" }
    return "\(max(1, s / 60))m"
}
