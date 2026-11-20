import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case all, favorites, category(String), substitutions
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var license: LicenseManager
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var recipes: [Recipe]
    @AppStorage("didSeedSamples") private var didSeedSamples = false

    @State private var sidebar: SidebarItem? = .all
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var showPaywall = false
    @State private var showCommit = false
    @State private var showCard = false
    @State private var pendingDelete: Recipe?

    private var categories: [String] {
        Array(Set(recipes.map(\.category).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [Recipe] {
        let base: [Recipe]
        switch sidebar ?? .all {
        case .all, .substitutions: base = recipes
        case .favorites: base = recipes.filter(\.isFavorite)
        case .category(let c): base = recipes.filter { $0.category == c }
        }
        guard !search.isEmpty else { return base }
        return base.filter { r in
            r.title.localizedCaseInsensitiveContains(search)
                || r.draft.ingredients.contains { $0.name.localizedCaseInsensitiveContains(search) }
        }
    }

    private var selected: Recipe? { recipes.first { $0.id == selectedID } }

    var body: some View {
        NavigationSplitView {
            sidebarList
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            Group {
                if sidebar == .substitutions {
                    SubstitutionLogView(recipes: recipes, selectedID: $selectedID)
                } else {
                    recipeList
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if let recipe = selected {
                RecipeDetailView(recipe: recipe, showCommit: $showCommit, showCard: $showCard,
                                 duplicate: duplicate)
                    .id(recipe.id)
            } else {
                EmptyDetail(newRecipe: newRecipe)
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Recipes or ingredients")
        .focusedSceneValue(\.recipeActions, RecipeActions(
            newRecipe: newRecipe,
            saveVersion: selected == nil ? nil : { showCommit = true },
            printCard: selected == nil ? nil : { showCard = true },
            showLicense: { showPaywall = true }))
        .sheet(isPresented: $showPaywall) { LicenseView().environmentObject(license) }
        .confirmationDialog("Delete “\(pendingDelete?.title ?? "")”?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Recipe and All Versions", role: .destructive) {
                if let r = pendingDelete { delete(r) }
            }
        } message: {
            Text("Its version history and notes will be deleted too. This can't be undone.")
        }
        .onAppear {
            if !didSeedSamples {
                SampleData.seed(into: context)
                didSeedSamples = true
            }
            if selectedID == nil { selectedID = recipes.first?.id }
        }
    }

    // MARK: Columns

    private var sidebarList: some View {
        List(selection: $sidebar) {
            Section("Library") {
                Label("All Recipes", systemImage: "book.closed").tag(SidebarItem.all)
                Label("Favourites", systemImage: "star").tag(SidebarItem.favorites)
                Label("Substitution Log", systemImage: "arrow.triangle.swap").tag(SidebarItem.substitutions)
            }
            if !categories.isEmpty {
                Section("Categories") {
                    ForEach(categories, id: \.self) { c in
                        Label(c, systemImage: "folder").tag(SidebarItem.category(c))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !license.isUnlocked {
                Button { showPaywall = true } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free plan").font(.caption.bold())
                        Text("\(ownRecipeCount)/\(LicenseConfig.freeRecipeLimit) recipes · Unlock for \(LicenseConfig.price)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
    }

    private var recipeList: some View {
        List(selection: $selectedID) {
            ForEach(filtered) { recipe in
                RecipeRow(recipe: recipe)
                    .tag(recipe.id)
                    .contextMenu {
                        Button(recipe.isFavorite ? "Remove from Favourites" : "Add to Favourites") { recipe.isFavorite.toggle() }
                        Button("Duplicate") { duplicate(recipe.draft, recipe.category) }
                        Divider()
                        Button("Delete…", role: .destructive) { pendingDelete = recipe }
                    }
            }
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(search.isEmpty ? "No Recipes" : "No Matches",
                                       systemImage: "fork.knife",
                                       description: Text(search.isEmpty ? "Press ⌘N to start a recipe." : "Try another search."))
            }
        }
        .onDeleteCommand { if let r = selected { pendingDelete = r } }
        .toolbar {
            ToolbarItem {
                Button(action: newRecipe) { Label("New Recipe", systemImage: "square.and.pencil") }
                    .help("New Recipe (⌘N)")
            }
        }
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        switch sidebar ?? .all {
        case .all: "All Recipes"
        case .favorites: "Favourites"
        case .category(let c): c
        case .substitutions: "Substitution Log"
        }
    }

    // MARK: Actions

    private var ownRecipeCount: Int { recipes.filter { !$0.isSample }.count }

    private func newRecipe() {
        var content = RecipeContent()
        content.title = "Untitled Recipe"
        var category = ""
        if case .category(let c) = sidebar ?? .all { category = c }
        createRecipe(content, category: category)
    }

    private func duplicate(_ content: RecipeContent, _ category: String) {
        var copy = content
        copy.title += " (copy)"
        createRecipe(copy, category: category)
    }

    private func createRecipe(_ content: RecipeContent, category: String) {
        guard license.canCreateRecipe(ownRecipeCount: ownRecipeCount) else { showPaywall = true; return }
        let recipe = Recipe(content: content, category: category)
        if sidebar == .favorites { recipe.isFavorite = true }
        context.insert(recipe)
        try? context.save()
        if sidebar == .substitutions { sidebar = .all }
        search = ""
        selectedID = recipe.id
    }

    private func delete(_ recipe: Recipe) {
        if selectedID == recipe.id { selectedID = nil }
        context.delete(recipe)
        try? context.save()
        pendingDelete = nil
    }
}

struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(recipe.title.isEmpty ? "Untitled" : recipe.title).font(.headline).lineLimit(1)
                if recipe.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
            }
            HStack(spacing: 6) {
                if let v = recipe.latestVersion {
                    Text(v.shortName).font(.caption.monospaced())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                } else {
                    Text("draft").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if !recipe.category.isEmpty { Text(recipe.category).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text(recipe.updatedAt, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct EmptyDetail: View {
    let newRecipe: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Pick a recipe", systemImage: "frying.pan")
        } description: {
            Text("Select a recipe, or start a new one and save versions as you experiment.")
        } actions: {
            Button("New Recipe", action: newRecipe).buttonStyle(.borderedProminent)
        }
    }
}

/// Every substitution recorded in any recipe, so you can see what has worked before.
struct SubstitutionLogView: View {
    let recipes: [Recipe]
    @Binding var selectedID: UUID?
    @State private var outcomeFilter: SubstitutionOutcome?

    private var rows: [(recipe: Recipe, sub: Substitution)] {
        recipes.flatMap { r in r.draft.substitutions.map { (r, $0) } }
            .filter { outcomeFilter == nil || $0.sub.outcome == outcomeFilter }
            .sorted { $0.sub.original.localizedCaseInsensitiveCompare($1.sub.original) == .orderedAscending }
    }

    var body: some View {
        List(selection: $selectedID) {
            ForEach(rows, id: \.sub.id) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: row.sub.outcome.symbol).foregroundStyle(row.sub.outcome.color)
                        Text(row.sub.original.isEmpty ? "?" : row.sub.original).strikethrough(row.sub.outcome == .great, color: .secondary)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        Text(row.sub.replacement.isEmpty ? "?" : row.sub.replacement).bold()
                    }
                    .lineLimit(1)
                    Text("in \(row.recipe.title)\(row.sub.ratio.isEmpty ? "" : " · \(row.sub.ratio)")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(row.recipe.id)
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("No Substitutions", systemImage: "arrow.triangle.swap",
                                       description: Text("Record swaps in a recipe's Substitutions tab."))
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Outcome", selection: $outcomeFilter) {
                    Text("All outcomes").tag(SubstitutionOutcome?.none)
                    ForEach(SubstitutionOutcome.allCases) { Text($0.label).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
        }
        .navigationTitle("Substitution Log")
    }
}
