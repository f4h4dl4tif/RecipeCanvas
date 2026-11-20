import SwiftUI
import SwiftData
import AppKit

/// A rounded card section used throughout the editor.
struct CanvasSection<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                accessory
            }
            content
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

extension CanvasSection where Accessory == EmptyView {
    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - Recipe editor

struct RecipeEditorView: View {
    @Binding var draft: RecipeContent
    @Binding var category: String
    let onSubstitute: (Ingredient) -> Void

    @State private var quickAdd = ""
    @FocusState private var focusedIngredient: UUID?
    @FocusState private var focusedStep: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ingredientsSection
                methodSection
            }
            .padding(20)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Recipe title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold, design: .serif))
            TextField("A short description — what makes this one special?", text: $draft.summary, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1...4)
            HStack(spacing: 18) {
                Stepper(value: $draft.servings, in: 1...200) {
                    Label("Serves \(draft.servings)", systemImage: "person.2")
                }
                minutesField("Prep", systemImage: "knife", value: $draft.prepMinutes)
                minutesField("Cook", systemImage: "flame", value: $draft.cookMinutes)
                HStack(spacing: 4) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    TextField("Category", text: $category).frame(width: 120)
                }
                Spacer()
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 4)
        }
    }

    private func minutesField(_ title: String, systemImage: String, value: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            Text(title)
            TextField("0", value: value, format: .number).frame(width: 48)
            Text("min").foregroundStyle(.secondary)
        }
    }

    // MARK: Ingredients

    private var ingredientsSection: some View {
        CanvasSection(title: "Ingredients", symbol: "basket") {
            Button { pasteIngredients() } label: { Label("Paste List", systemImage: "doc.on.clipboard") }
                .buttonStyle(.borderless)
                .help("Add one ingredient per line from the clipboard")
        } content: {
            if !draft.ingredients.isEmpty {
                HStack(spacing: 8) {
                    Text("Qty").frame(width: 60, alignment: .leading)
                    Text("Unit").frame(width: 70, alignment: .leading)
                    Text("Ingredient").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Note").frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 24)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($draft.ingredients) { $ingredient in
                HStack(spacing: 8) {
                    TextField("2", text: $ingredient.quantity).frame(width: 60)
                    TextField("cups", text: $ingredient.unit).frame(width: 70)
                    TextField("flour", text: $ingredient.name)
                        .focused($focusedIngredient, equals: ingredient.id)
                    TextField("sifted", text: $ingredient.note).foregroundStyle(.secondary)
                    rowMenu(
                        moveUp: { move(&draft.ingredients, ingredient.id, by: -1) },
                        moveDown: { move(&draft.ingredients, ingredient.id, by: 1) },
                        insertBelow: {
                            let new = Ingredient()
                            insert(new, into: &draft.ingredients, after: ingredient.id)
                            focusedIngredient = new.id
                        },
                        delete: { draft.ingredients.removeAll { $0.id == ingredient.id } }
                    ) {
                        Button("Record a Substitution…") { onSubstitute(ingredient) }
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            HStack {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                TextField("Quick add: “1 1/2 cups flour, sifted” then Return", text: $quickAdd)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        guard !quickAdd.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        draft.ingredients.append(IngredientParser.parse(quickAdd))
                        quickAdd = ""
                    }
            }
            .padding(8)
            .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func pasteIngredients() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        draft.ingredients += lines.map(IngredientParser.parse)
    }

    // MARK: Method

    private var methodSection: some View {
        CanvasSection(title: "Method", symbol: "list.number") {
            Button {
                let s = Step()
                draft.steps.append(s)
                focusedStep = s.id
            } label: { Label("Add Step", systemImage: "plus") }
                .buttonStyle(.borderless)
        } content: {
            if draft.steps.isEmpty {
                Text("No steps yet. Add the first one.").foregroundStyle(.secondary)
            }
            ForEach(Array($draft.steps.enumerated()), id: \.element.id) { index, $step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.callout.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Theme.accent, in: Circle())
                    TextField("Describe this step…", text: $step.text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...8)
                        .focused($focusedStep, equals: step.id)
                    rowMenu(
                        moveUp: { move(&draft.steps, step.id, by: -1) },
                        moveDown: { move(&draft.steps, step.id, by: 1) },
                        insertBelow: {
                            let new = Step()
                            insert(new, into: &draft.steps, after: step.id)
                            focusedStep = new.id
                        },
                        delete: { draft.steps.removeAll { $0.id == step.id } }
                    ) { EmptyView() }
                }
            }
        }
    }

    // MARK: Row helpers

    private func rowMenu<Extra: View>(moveUp: @escaping () -> Void, moveDown: @escaping () -> Void,
                                      insertBelow: @escaping () -> Void, delete: @escaping () -> Void,
                                      @ViewBuilder extra: () -> Extra) -> some View {
        Menu {
            Button("Insert Below", action: insertBelow)
            Button("Move Up", action: moveUp)
            Button("Move Down", action: moveDown)
            extra()
            Divider()
            Button("Delete", role: .destructive, action: delete)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
    }
}

func move<T: Identifiable>(_ array: inout [T], _ id: T.ID, by offset: Int) {
    guard let i = array.firstIndex(where: { $0.id == id }) else { return }
    let j = i + offset
    guard array.indices.contains(j) else { return }
    array.swapAt(i, j)
}

func insert<T: Identifiable>(_ item: T, into array: inout [T], after id: T.ID) {
    let i = array.firstIndex(where: { $0.id == id }).map { $0 + 1 } ?? array.endIndex
    array.insert(item, at: i)
}

// MARK: - Substitutions

struct SubstitutionsView: View {
    @Binding var draft: RecipeContent
    @Binding var focus: UUID?
    @FocusState private var focusedField: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ingredient Substitutions").font(.title2.bold())
                        Text("Log every swap you try and whether it worked. They are saved with each version and gathered in the Substitution Log.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Blank Substitution") { add(Substitution()) }
                        if !draft.ingredients.isEmpty {
                            Divider()
                            ForEach(draft.ingredients.filter { !$0.name.isEmpty }) { ing in
                                Button("Replace \(ing.name)") { add(Substitution(original: ing.name)) }
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .fixedSize()
                }

                if draft.substitutions.isEmpty {
                    ContentUnavailableView("No substitutions yet", systemImage: "arrow.triangle.swap",
                                           description: Text("Out of buttermilk? Trying oat milk? Record it here."))
                        .padding(.top, 40)
                }

                ForEach($draft.substitutions) { $sub in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            TextField("Original ingredient", text: $sub.original)
                                .focused($focusedField, equals: sub.id)
                            Image(systemName: "arrow.right").foregroundStyle(Theme.accent)
                            TextField("Replacement", text: $sub.replacement)
                            TextField("Ratio (e.g. 1:1)", text: $sub.ratio).frame(width: 130)
                            Button(role: .destructive) {
                                draft.substitutions.removeAll { $0.id == sub.id }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Delete substitution")
                        }
                        TextField("Why? (allergy, ran out, healthier, experiment…)", text: $sub.reason)
                        Picker("Result", selection: $sub.outcome) {
                            ForEach(SubstitutionOutcome.allCases) { o in
                                Label(o.label, systemImage: o.symbol).tag(o)
                            }
                        }
                        .pickerStyle(.segmented)
                        TextField("Notes on the result", text: $sub.notes, axis: .vertical)
                            .lineLimit(1...4)
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .leading) {
                        UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                            .fill(sub.outcome.color).frame(width: 4)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
            }
            .padding(20)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .onAppear {
            if let focus { focusedField = focus; self.focus = nil }
        }
    }

    private func add(_ sub: Substitution) {
        draft.substitutions.append(sub)
        focusedField = sub.id
    }
}

// MARK: - Preparation notes

struct NotesView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var context
    @State private var newText = ""
    @State private var newKind: NoteKind = .prep
    @State private var filter: NoteKind?

    private var notes: [PrepNote] {
        recipe.sortedNotes.filter { filter == nil || $0.kind == filter }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preparation Notes").font(.title2.bold())
                    Text("Notes belong to the recipe, not a version, so they carry across every experiment. Pinned notes print on recipe cards.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Picker("Type", selection: $newKind) {
                        ForEach(NoteKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .fixedSize()
                    TextEditor(text: $newText)
                        .font(.body)
                        .frame(height: 70)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    HStack {
                        Spacer()
                        Button("Add Note") { addNote() }
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))

                if !recipe.notes.isEmpty {
                    Picker("Show", selection: $filter) {
                        Text("All").tag(NoteKind?.none)
                        ForEach(NoteKind.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                ForEach(notes) { note in
                    NoteRow(note: note) {
                        context.delete(note)
                        try? context.save()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func addNote() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recipe.notes.append(PrepNote(text: text, kind: newKind))
        try? context.save()
        newText = ""
    }
}

struct NoteRow: View {
    @Bindable var note: PrepNote
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.kind.symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(note.kind.label).font(.caption.bold()).foregroundStyle(.secondary)
                    Text(note.createdAt, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.tertiary)
                }
                TextField("Note", text: $note.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...12)
            }
            Spacer()
            Button { note.isPinned.toggle() } label: {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(note.isPinned ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .help(note.isPinned ? "Unpin" : "Pin (prints on recipe cards)")
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete note")
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(note.isPinned ? Theme.accent.opacity(0.5) : Color.secondary.opacity(0.2)))
    }
}
