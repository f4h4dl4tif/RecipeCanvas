import Foundation
import SwiftData
import SwiftUI

// MARK: - Value types stored inside a recipe snapshot

struct Ingredient: Codable, Hashable, Identifiable {
    var id = UUID()
    var quantity = ""
    var unit = ""
    var name = ""
    var note = ""

    var amount: String { [quantity, unit].filter { !$0.isEmpty }.joined(separator: " ") }
    var display: String {
        let base = [amount, name].filter { !$0.isEmpty }.joined(separator: " ")
        return note.isEmpty ? base : "\(base), \(note)"
    }
}

struct Step: Codable, Hashable, Identifiable {
    var id = UUID()
    var text = ""
}

enum SubstitutionOutcome: String, Codable, CaseIterable, Identifiable {
    case untested, great, okay, failed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .untested: "Untested"
        case .great: "Worked great"
        case .okay: "Acceptable"
        case .failed: "Didn't work"
        }
    }
    var symbol: String {
        switch self {
        case .untested: "questionmark.circle"
        case .great: "checkmark.circle.fill"
        case .okay: "equal.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .untested: .secondary
        case .great: .green
        case .okay: .orange
        case .failed: .red
        }
    }
}

struct Substitution: Codable, Hashable, Identifiable {
    var id = UUID()
    var original = ""
    var replacement = ""
    var ratio = ""
    var reason = ""
    var outcome: SubstitutionOutcome = .untested
    var notes = ""
}

/// Everything that makes up one "state" of a recipe. Drafts and versions both store this.
struct RecipeContent: Codable, Hashable {
    var title = "Untitled Recipe"
    var summary = ""
    var servings = 4
    var prepMinutes = 0
    var cookMinutes = 0
    var ingredients: [Ingredient] = []
    var steps: [Step] = []
    var substitutions: [Substitution] = []

    init() {}

    init(title: String, summary: String = "", servings: Int = 4, prepMinutes: Int = 0, cookMinutes: Int = 0,
         ingredients: [Ingredient] = [], steps: [Step] = [], substitutions: [Substitution] = []) {
        self.title = title; self.summary = summary; self.servings = servings
        self.prepMinutes = prepMinutes; self.cookMinutes = cookMinutes
        self.ingredients = ingredients; self.steps = steps; self.substitutions = substitutions
    }

    // Tolerant decoding so older saved snapshots keep loading when fields are added later.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Recipe"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        servings = try c.decodeIfPresent(Int.self, forKey: .servings) ?? 4
        prepMinutes = try c.decodeIfPresent(Int.self, forKey: .prepMinutes) ?? 0
        cookMinutes = try c.decodeIfPresent(Int.self, forKey: .cookMinutes) ?? 0
        ingredients = try c.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? []
        steps = try c.decodeIfPresent([Step].self, forKey: .steps) ?? []
        substitutions = try c.decodeIfPresent([Substitution].self, forKey: .substitutions) ?? []
    }

    var totalMinutes: Int { prepMinutes + cookMinutes }

    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ data: Data) -> RecipeContent {
        (try? JSONDecoder().decode(RecipeContent.self, from: data)) ?? RecipeContent()
    }
}

// MARK: - Persistent models

@Model
final class Recipe {
    var id: UUID = UUID()
    var title: String = ""
    var category: String = ""
    var isFavorite: Bool = false
    var isSample: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var draftData: Data = Data()

    @Relationship(deleteRule: .cascade, inverse: \RecipeVersion.recipe)
    var versions: [RecipeVersion] = []

    @Relationship(deleteRule: .cascade, inverse: \PrepNote.recipe)
    var notes: [PrepNote] = []

    init(content: RecipeContent, category: String = "", isSample: Bool = false) {
        self.title = content.title
        self.category = category
        self.isSample = isSample
        self.draftData = content.encoded()
    }

    /// The working copy the editor changes. Versions are immutable snapshots of it.
    var draft: RecipeContent {
        get { RecipeContent.decode(draftData) }
        set {
            draftData = newValue.encoded()
            title = newValue.title
            updatedAt = .now
        }
    }

    var sortedVersions: [RecipeVersion] { versions.sorted { $0.number > $1.number } }
    var latestVersion: RecipeVersion? { versions.max { $0.number < $1.number } }
    var sortedNotes: [PrepNote] {
        notes.sorted { ($0.isPinned ? 1 : 0, $0.createdAt) > ($1.isPinned ? 1 : 0, $1.createdAt) }
    }

    func hasChanges(comparedTo content: RecipeContent) -> Bool {
        guard let latest = latestVersion else { return true }
        return latest.content != content
    }

    @discardableResult
    func commitVersion(_ content: RecipeContent, label: String, note: String, rating: Int = 0) -> RecipeVersion {
        let number = (latestVersion?.number ?? 0) + 1
        let version = RecipeVersion(number: number,
                                    label: label.isEmpty ? "Version \(number)" : label,
                                    changeNote: note, rating: rating, content: content)
        versions.append(version)
        updatedAt = .now
        return version
    }
}

@Model
final class RecipeVersion {
    var number: Int = 1
    var label: String = ""
    var changeNote: String = ""
    var rating: Int = 0
    var createdAt: Date = Date()
    var contentData: Data = Data()
    var recipe: Recipe?

    init(number: Int, label: String, changeNote: String, rating: Int, content: RecipeContent, createdAt: Date = .now) {
        self.number = number
        self.label = label
        self.changeNote = changeNote
        self.rating = rating
        self.contentData = content.encoded()
        self.createdAt = createdAt
    }

    var content: RecipeContent { RecipeContent.decode(contentData) }
    var shortName: String { "v\(number)" }
}

enum NoteKind: String, CaseIterable, Identifiable {
    case prep, timing, technique, tasting, general
    var id: String { rawValue }
    var label: String {
        switch self {
        case .prep: "Prep / Mise en place"
        case .timing: "Timing"
        case .technique: "Technique"
        case .tasting: "Tasting"
        case .general: "General"
        }
    }
    var symbol: String {
        switch self {
        case .prep: "list.bullet.clipboard"
        case .timing: "timer"
        case .technique: "frying.pan"
        case .tasting: "fork.knife"
        case .general: "note.text"
        }
    }
}

@Model
final class PrepNote {
    var text: String = ""
    var kindRaw: String = NoteKind.general.rawValue
    var isPinned: Bool = false
    var createdAt: Date = Date()
    var recipe: Recipe?

    init(text: String, kind: NoteKind, isPinned: Bool = false) {
        self.text = text
        self.kindRaw = kind.rawValue
        self.isPinned = isPinned
    }

    var kind: NoteKind {
        get { NoteKind(rawValue: kindRaw) ?? .general }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Formatting helpers

enum Format {
    static func minutes(_ m: Int) -> String {
        guard m > 0 else { return "—" }
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }
}
