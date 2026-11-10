import AppKit
import Combine

@MainActor
final class Store: ObservableObject {
    @Published private(set) var state: NotchState?
    @Published private(set) var live = false
    @Published private(set) var visible = false
    @Published private(set) var toast: Toast?
    @Published var selectedPane: Int?
    @Published private(set) var workingSince: [Int: Date] = [:]
    @Published private(set) var pending: Set<String> = []
    @Published private(set) var catalog: Catalog?
    @Published var drafts: [Int: String] = [:]
    @Published var newModel: String? = UserDefaults.standard.string(forKey: "newModel") {
        didSet { UserDefaults.standard.set(newModel, forKey: "newModel") }
    }
    @Published var newEffort: String? = UserDefaults.standard.string(forKey: "newEffort") {
        didSet { UserDefaults.standard.set(newEffort, forKey: "newEffort") }
    }

    static let newAgent = -1

    let dir: URL
    private var stamp: Date?
    private var timer: Timer?
    private var catalogStamp: Date?
    private var lastToastId: Int?
    private var toastClear: DispatchWorkItem?

    init() {
        dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TernNotch", isDirectory: true)
    }

    func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir.appendingPathComponent("inbox"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: dir.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        poll()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let url = dir.appendingPathComponent("state.json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modified = attrs[.modificationDate] as? Date, modified != stamp,
           let data = try? Data(contentsOf: url),
           let next = try? JSONDecoder().decode(NotchState.self, from: data) {
            stamp = modified
            apply(next)
        }
        let catalogURL = dir.appendingPathComponent("catalog.json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: catalogURL.path),
           let modified = attrs[.modificationDate] as? Date, modified != catalogStamp,
           let data = try? Data(contentsOf: catalogURL),
           let next = try? JSONDecoder().decode(Catalog.self, from: data) {
            catalogStamp = modified
            catalog = next
        }
        let age = state.map { Date().timeIntervalSince1970 - $0.at } ?? .infinity
        if (age < 15) != live { live = age < 15 }
        if (age < 120) != visible { visible = age < 120 }
    }

    private func apply(_ next: NotchState) {
        var since = workingSince
        for agent in next.agents {
            if agent.isWorking {
                if since[agent.pane] == nil { since[agent.pane] = Date() }
            } else {
                since[agent.pane] = nil
            }
        }
        let panes = Set(next.agents.map(\.pane))
        since = since.filter { panes.contains($0.key) }
        if since != workingSince { workingSince = since }
        if let selected = selectedPane, selected != Store.newAgent, !panes.contains(selected) { selectedPane = nil }
        let stale = drafts.keys.filter { $0 != Store.newAgent && !panes.contains($0) }
        if !stale.isEmpty { stale.forEach { drafts[$0] = nil } }
        if next.agents != state?.agents { pending = [] }
        if let t = next.toast, t.id != lastToastId {
            lastToastId = t.id
            show(t)
        }
        if next != state { state = next }
    }

    private func show(_ t: Toast) {
        toast = t
        toastClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    var agents: [Agent] { state?.agents ?? [] }

    var primary: Agent? {
        agents.first(where: \.needsInput)
            ?? agents.first(where: \.isWorking)
            ?? agents.first(where: { $0.focused == true })
            ?? agents.first
    }

    var selected: Agent? {
        if composingNew { return nil }
        if let pane = selectedPane, let agent = agents.first(where: { $0.pane == pane }) { return agent }
        return primary
    }

    var composingNew: Bool { selectedPane == Store.newAgent || agents.isEmpty }

    var anyNeedsInput: Bool { agents.contains(where: \.needsInput) }
    var workingCount: Int { agents.filter(\.isWorking).count }
    var isActive: Bool { anyNeedsInput || workingCount > 0 }

    var quotas: [Quota] { (state?.quota ?? []).sorted { $0.used > $1.used } }

    var targetCwd: String? { selected?.cwd ?? state?.launch?.cwd }

    func folder(_ cwd: String?) -> Folder? {
        guard let cwd else { return nil }
        return state?.folders?.first(where: { $0.cwd == cwd })
    }

    var commands: [SlashCommand] {
        var seen = Set<String>()
        return ((folder(targetCwd)?.commands ?? []) + (catalog?.commands ?? [])).filter { seen.insert($0.name).inserted }
    }

    var models: [ModelEntry] { catalog?.models ?? [] }

    func pick(_ option: DialogOption, in list: OptionList, agent: Agent) {
        markPending(option.id)
        send("pick", ["pane": agent.pane, "list": list.id, "item": option.id,
                      "mode": option.kind == "check" ? "select" : "activate"])
    }

    func selectTab(_ tab: DialogTab, in tabs: DialogTabs, agent: Agent) {
        send("tab", ["pane": agent.pane, "tabs": tabs.id, "item": tab.id])
    }

    func press(_ button: DialogButton, agent: Agent) {
        markPending(button.id)
        send("button", ["pane": agent.pane, "id": button.id, "act": button.act])
    }

    func submit(_ text: String, agent: Agent) {
        send("send", ["pane": agent.pane, "text": text])
    }

    func startAgent(_ text: String) {
        var fields: [String: Any] = ["text": text, "cwd": state?.launch?.cwd ?? NSHomeDirectory()]
        if let model = newModel { fields["model"] = model }
        if let effort = newEffort { fields["effort"] = effort }
        send("start", fields)
        selectedPane = nil
    }

    func setModel(_ selector: String, agent: Agent) {
        send("model", ["pane": agent.pane, "model": selector])
    }

    func setEffort(_ level: String, agent: Agent) {
        send("effort", ["pane": agent.pane, "effort": level])
    }

    func focus(_ agent: Agent) {
        send("focus", ["pane": agent.pane])
        NSRunningApplication.runningApplications(withBundleIdentifier: ternBundleID).first?.activate()
    }

    func close(_ pane: Int) {
        if selectedPane == pane { selectedPane = nil }
        send("close", ["pane": pane])
    }

    private func markPending(_ id: String) {
        pending.insert(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.pending.remove(id) }
    }

    private func send(_ op: String, _ fields: [String: Any]) {
        var cmd = fields
        let now = Date().timeIntervalSince1970
        cmd["op"] = op
        cmd["at"] = now
        let name = String(format: "%013.0f-%@.json", now * 1000, UUID().uuidString)
        let tmp = dir.appendingPathComponent("tmp").appendingPathComponent(name)
        let dst = dir.appendingPathComponent("inbox").appendingPathComponent(name)
        do {
            let data = try JSONSerialization.data(withJSONObject: cmd)
            try data.write(to: tmp)
            try FileManager.default.moveItem(at: tmp, to: dst)
        } catch {
            show(Toast(id: -1, level: "error", text: "Could not reach Tern: \(error.localizedDescription)"))
        }
    }
}

let ternBundleID = "so.stencil.tern"
