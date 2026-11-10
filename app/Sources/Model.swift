import Foundation

struct NotchState: Decodable, Equatable {
    var v: Int
    var at: Double
    var agents: [Agent]
    var quota: [Quota]
    var launch: Launch?
    var folders: [Folder]?
    var toast: Toast?
}

struct Launch: Decodable, Equatable {
    var cwd: String
}

struct Folder: Decodable, Equatable {
    var cwd: String
    var branch: String?
    var added: Int?
    var removed: Int?
    var files: Int?
    var commands: [SlashCommand]?
}

struct Catalog: Decodable, Equatable {
    var models: [ModelEntry]
    var commands: [SlashCommand]
}

struct ModelEntry: Decodable, Equatable, Identifiable {
    var selector: String
    var name: String
    var provider: String
    var thinking: [String]?
    var id: String { selector }
}

struct SlashCommand: Decodable, Equatable, Hashable, Identifiable {
    var name: String
    var description: String?
    var hint: String?
    var id: String { name }
}

struct Agent: Decodable, Equatable, Identifiable {
    var pane: Int
    var title: String
    var state: String
    var program: String?
    var model: String?
    var effort: String?
    var cwd: String?
    var focused: Bool?
    var activity: String?
    var context: ContextUse?
    var cost: String?
    var last: String?
    var draft: Bool?
    var dialog: Dialog?

    var id: Int { pane }
    var isWorking: Bool { state == "working" }
    var needsInput: Bool {
        state == "waiting_input" || dialog?.kind == "ask" || dialog?.kind == "answer"
    }
    var shortTitle: String {
        let base = title.isEmpty ? (program ?? "agent") : title
        if let colon = base.firstIndex(of: ":"), base.distance(from: base.startIndex, to: colon) <= 16 {
            return String(base[..<colon])
        }
        return base.count > 18 ? String(base.prefix(17)) + "…" : base
    }
}

struct ContextUse: Decodable, Equatable {
    var fraction: Double
    var label: String?
    var detail: String?
}

struct Dialog: Decodable, Equatable {
    var kind: String
    var title: String?
    var eyebrow: String?
    var tabs: DialogTabs?
    var list: OptionList?
    var notice: String?
    var answers: [AnswerRow]?
    var buttons: [DialogButton]?
    var input: Bool?
}

struct DialogTabs: Decodable, Equatable {
    var id: String
    var active: String?
    var items: [DialogTab]
}

struct DialogTab: Decodable, Equatable, Identifiable {
    var id: String
    var label: String
    var done: Bool?
}

struct OptionList: Decodable, Equatable {
    var id: String
    var items: [DialogOption]
}

struct DialogOption: Decodable, Equatable, Identifiable {
    var id: String
    var label: String
    var detail: String?
    var badge: String?
    var kind: String
    var multi: Bool?
    var checked: Bool?
    var disabled: Bool?
}

struct AnswerRow: Decodable, Equatable, Hashable {
    var k: String
    var v: String
}

struct DialogButton: Decodable, Equatable, Identifiable {
    var id: String
    var act: String
    var label: String
    var primary: Bool?
}

struct Quota: Decodable, Equatable, Identifiable {
    var id: String
    var provider: String
    var label: String
    var short: String?
    var used: Double
    var resetsAt: Double?
    var status: String?
}

struct Toast: Decodable, Equatable {
    var id: Int
    var level: String
    var text: String
}
