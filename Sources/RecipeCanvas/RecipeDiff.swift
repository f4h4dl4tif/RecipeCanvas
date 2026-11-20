import Foundation

/// Computes what changed between two recipe states, for the Compare tab and history summaries.
struct RecipeDiff {
    struct FieldChange: Identifiable {
        var id: String { label }
        let label: String
        let old: String
        let new: String
    }

    enum Status { case same, added, removed, changed }

    struct IngredientRow: Identifiable {
        let id = UUID()
        let status: Status
        let old: Ingredient?
        let new: Ingredient?
    }

    struct StepRow: Identifiable {
        let id = UUID()
        let index: Int
        let text: String
        let highlighted: Bool   // removed (left side) or inserted (right side)
    }

    struct SubstitutionRow: Identifiable {
        let id = UUID()
        let status: Status
        let old: Substitution?
        let new: Substitution?
    }

    let fields: [FieldChange]
    let ingredients: [IngredientRow]
    let stepsOld: [StepRow]
    let stepsNew: [StepRow]
    let substitutions: [SubstitutionRow]

    init(old: RecipeContent, new: RecipeContent) {
        var f: [FieldChange] = []
        func add(_ label: String, _ a: String, _ b: String) { if a != b { f.append(.init(label: label, old: a, new: b)) } }
        add("Title", old.title, new.title)
        add("Description", old.summary, new.summary)
        add("Servings", "\(old.servings)", "\(new.servings)")
        add("Prep time", Format.minutes(old.prepMinutes), Format.minutes(new.prepMinutes))
        add("Cook time", Format.minutes(old.cookMinutes), Format.minutes(new.cookMinutes))
        fields = f

        ingredients = Self.matchRows(old: old.ingredients, new: new.ingredients,
                                     key: { $0.name.lowercased().trimmingCharacters(in: .whitespaces) })
            .map { IngredientRow(status: $0.status, old: $0.old, new: $0.new) }

        substitutions = Self.matchRows(old: old.substitutions, new: new.substitutions,
                                       key: { $0.original.lowercased() + "→" + $0.replacement.lowercased() })
            .map { SubstitutionRow(status: $0.status, old: $0.old, new: $0.new) }

        let a = old.steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let b = new.steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let diff = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        stepsOld = a.enumerated().map { StepRow(index: $0.offset + 1, text: $0.element, highlighted: removed.contains($0.offset)) }
        stepsNew = b.enumerated().map { StepRow(index: $0.offset + 1, text: $0.element, highlighted: inserted.contains($0.offset)) }
    }

    /// Matches items by stable id first, then by a natural key (e.g. ingredient name).
    private static func matchRows<T: Identifiable & Equatable>(old: [T], new: [T], key: (T) -> String)
        -> [(status: Status, old: T?, new: T?)] where T.ID == UUID {
        var remainingOld = old
        var rows: [(Status, T?, T?)] = []
        for item in new {
            if let i = remainingOld.firstIndex(where: { $0.id == item.id })
                ?? remainingOld.firstIndex(where: { key($0) == key(item) && !key(item).isEmpty }) {
                let o = remainingOld.remove(at: i)
                rows.append((o == item ? .same : .changed, o, item))
            } else {
                rows.append((.added, nil, item))
            }
        }
        rows += remainingOld.map { (.removed, $0, nil) }
        return rows
    }

    var stepChanges: Int { max(stepsOld.filter(\.highlighted).count, stepsNew.filter(\.highlighted).count) }
    func count(_ s: Status) -> Int { ingredients.filter { $0.status == s }.count }
    var changedSubstitutions: Int { substitutions.filter { $0.status != .same }.count }

    var isEmpty: Bool {
        fields.isEmpty && ingredients.allSatisfy { $0.status == .same } && stepChanges == 0 && changedSubstitutions == 0
    }

    /// One-line human summary, e.g. "+2 ingredients · 1 changed · 3 steps edited".
    var summary: String {
        var parts: [String] = []
        let added = count(.added), removed = count(.removed), changed = count(.changed)
        if added > 0 { parts.append("+\(added) ingredient\(added == 1 ? "" : "s")") }
        if removed > 0 { parts.append("−\(removed) ingredient\(removed == 1 ? "" : "s")") }
        if changed > 0 { parts.append("\(changed) ingredient\(changed == 1 ? "" : "s") adjusted") }
        if stepChanges > 0 { parts.append("\(stepChanges) step\(stepChanges == 1 ? "" : "s") edited") }
        if changedSubstitutions > 0 { parts.append("\(changedSubstitutions) substitution\(changedSubstitutions == 1 ? "" : "s")") }
        parts += fields.filter { $0.label != "Description" }.map { "\($0.label.lowercased()) \($0.old) → \($0.new)" }
        if parts.isEmpty { return fields.isEmpty ? "No changes" : "Description edited" }
        return parts.joined(separator: " · ")
    }
}

/// Turns a typed line like "1 1/2 cups flour, sifted" into an Ingredient.
enum IngredientParser {
    static let units: Set<String> = [
        "tsp", "teaspoon", "teaspoons", "tbsp", "tablespoon", "tablespoons", "cup", "cups", "c",
        "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "g", "gram", "grams", "kg",
        "ml", "l", "liter", "liters", "litre", "litres", "pinch", "pinches", "dash", "clove", "cloves",
        "can", "cans", "stick", "sticks", "slice", "slices", "bunch", "sprig", "sprigs", "handful",
        "piece", "pieces", "quart", "quarts", "pint", "pints", "package", "packages", "jar", "head"
    ]

    static func parse(_ line: String) -> Ingredient {
        var text = line.trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: "^[-•*]\\s*", with: "", options: .regularExpression)
        var note = ""
        if let comma = text.firstIndex(of: ",") {
            note = text[text.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            text = String(text[..<comma])
        }
        var tokens = text.split(separator: " ").map(String.init)
        var qty: [String] = []
        while let t = tokens.first, isQuantity(t) { qty.append(tokens.removeFirst()) }
        var unit = ""
        if let t = tokens.first, !qty.isEmpty, units.contains(t.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            unit = tokens.removeFirst()
        }
        return Ingredient(quantity: qty.joined(separator: " "), unit: unit, name: tokens.joined(separator: " "), note: note)
    }

    private static func isQuantity(_ t: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789/.-–½⅓⅔¼¾⅛⅜⅝⅞")
        return !t.isEmpty && t.unicodeScalars.allSatisfy { allowed.contains($0) } && t.rangeOfCharacter(from: .decimalDigits.union(CharacterSet(charactersIn: "½⅓⅔¼¾⅛⅜⅝⅞"))) != nil
    }
}
