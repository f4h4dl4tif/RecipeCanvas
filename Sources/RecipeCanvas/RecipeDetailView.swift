import SwiftUI
import SwiftData

enum DetailTab: String, CaseIterable, Identifiable {
    case recipe = "Recipe", substitutions = "Substitutions", notes = "Notes", history = "History", compare = "Compare"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .recipe: "doc.richtext"
        case .substitutions: "arrow.triangle.swap"
        case .notes: "note.text"
        case .history: "clock.arrow.circlepath"
        case .compare: "rectangle.split.2x1"
        }
    }
}

/// Which recipe state is shown on one side of the Compare tab.
enum CompareSide: Hashable {
    case draft
    case version(Int)
}

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.openWindow) private var openWindow
    @Binding var showCommit: Bool
    @Binding var showCard: Bool
    let duplicate: (RecipeContent, String) -> Void

    @State private var draft: RecipeContent
    @State private var tab: DetailTab = .recipe
    @State private var compareLeft: CompareSide = .draft
    @State private var compareRight: CompareSide = .draft
    @State private var focusSubstitution: UUID?
    @AppStorage(GlassTheme.key) private var glass = false

    init(recipe: Recipe, showCommit: Binding<Bool>, showCard: Binding<Bool>, duplicate: @escaping (RecipeContent, String) -> Void) {
        self.recipe = recipe
        self._showCommit = showCommit
        self._showCard = showCard
        self.duplicate = duplicate
        self._draft = State(initialValue: recipe.draft)
        let latest = recipe.latestVersion?.number
        let previous = recipe.sortedVersions.dropFirst().first?.number
        self._compareLeft = State(initialValue: previous.map(CompareSide.version) ?? latest.map(CompareSide.version) ?? .draft)
        self._compareRight = State(initialValue: previous == nil ? .draft : latest.map(CompareSide.version) ?? .draft)
    }

    private var isModified: Bool { recipe.hasChanges(comparedTo: draft) }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            Group {
                switch tab {
                case .recipe:
                    RecipeEditorView(draft: $draft, category: $recipe.category, onSubstitute: { ingredient in
                        let sub = Substitution(original: ingredient.name)
                        draft.substitutions.append(sub)
                        focusSubstitution = sub.id
                        tab = .substitutions
                    })
                case .substitutions:
                    SubstitutionsView(draft: $draft, focus: $focusSubstitution)
                case .notes:
                    NotesView(recipe: recipe)
                case .history:
                    HistoryView(recipe: recipe, draft: $draft, isModified: isModified,
                                saveVersion: { showCommit = true },
                                compare: { left, right in compareLeft = left; compareRight = right; tab = .compare },
                                duplicate: { duplicate($0, recipe.category) })
                case .compare:
                    CompareView(recipe: recipe, draft: draft, left: $compareLeft, right: $compareRight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: draft) { _, newValue in recipe.draft = newValue }
        .navigationTitle(draft.title.isEmpty ? "Untitled" : draft.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $tab) {
                    ForEach(DetailTab.allCases) { t in
                        Label(t.rawValue, systemImage: t.symbol).labelStyle(.titleOnly).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 460)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { recipe.isFavorite.toggle() } label: {
                    Label("Favourite", systemImage: recipe.isFavorite ? "star.fill" : "star")
                }
                .help("Favourite")
                Button { openWindow(id: "cook", value: recipe.id) } label: { Label("Cook", systemImage: "flame") }
                    .help("Start Cook Mode: full-screen steps with timers (⌘K)")
                Button { showCard = true } label: { Label("Recipe Card", systemImage: "printer") }
                    .help("Print or export a recipe card (⌘P)")
                Button { showCommit = true } label: { Label("Save Version", systemImage: "checkmark.circle") }
                    .help("Save the current draft as a new version (⌘S)")
            }
        }
        .sheet(isPresented: $showCommit) {
            CommitVersionSheet(recipe: recipe, draft: draft)
        }
        .sheet(isPresented: $showCard) {
            RecipeCardSheet(content: draft,
                            versionLabel: isModified ? "Draft" : recipe.latestVersion?.shortName ?? "Draft",
                            notes: recipe.sortedNotes.filter(\.isPinned).map(\.text))
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let latest = recipe.latestVersion {
                if isModified {
                    Label("Draft has unsaved changes since \(latest.shortName)", systemImage: "pencil.circle.fill")
                        .foregroundStyle(Theme.changed)
                } else {
                    Label("Matches \(latest.shortName) · \(latest.label)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Label("New recipe — save a first version to start its history", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(recipe.versions.count) version\(recipe.versions.count == 1 ? "" : "s") · \(recipe.notes.count) note\(recipe.notes.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            if isModified {
                Button("Save Version…") { showCommit = true }.controlSize(.small).glassButton(glass)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct CommitVersionSheet: View {
    let recipe: Recipe
    let draft: RecipeContent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var label = ""
    @State private var note = ""
    @State private var rating = 0

    private var diff: RecipeDiff? {
        recipe.latestVersion.map { RecipeDiff(old: $0.content, new: draft) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Version \((recipe.latestVersion?.number ?? 0) + 1)").font(.title2.bold())
            if let diff {
                Label(diff.summary, systemImage: "plus.forwardslash.minus")
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            TextField("Name (e.g. “Less sugar, longer bake”)", text: $label)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 4) {
                Text("What did you change, and why?").font(.callout)
                TextEditor(text: $note)
                    .font(.body)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
            HStack {
                Text("How did it turn out?")
                RatingView(rating: $rating)
                Spacer()
            }
            if diff?.isEmpty == true {
                Text("Nothing has changed since the last version.").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Version") {
                    recipe.commitVersion(draft, label: label, note: note, rating: rating)
                    try? context.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

struct RatingView: View {
    @Binding var rating: Int
    var size: Font = .body

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .foregroundStyle(i <= rating ? Color.yellow : Color.secondary)
                    .font(size)
                    .onTapGesture { rating = (rating == i ? 0 : i) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating) of 5")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(0, rating - 1)
            @unknown default: break
            }
        }
    }
}
