import SwiftUI
import SwiftData

// MARK: - Version history

struct HistoryView: View {
    @Bindable var recipe: Recipe
    @Binding var draft: RecipeContent
    let isModified: Bool
    let saveVersion: () -> Void
    let compare: (CompareSide, CompareSide) -> Void
    let duplicate: (RecipeContent) -> Void

    @State private var selected: Int?
    @State private var pendingRestore: RecipeVersion?

    var body: some View {
        if recipe.versions.isEmpty {
            ContentUnavailableView {
                Label("No versions yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Save a version whenever you cook it differently. You can compare and restore any version later.")
            } actions: {
                Button("Save First Version…", action: saveVersion).buttonStyle(.borderedProminent)
            }
        } else {
            HSplitView {
                timeline.frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                preview.frame(minWidth: 320, maxWidth: .infinity)
            }
            .onAppear { if selected == nil { selected = recipe.latestVersion?.number } }
            .confirmationDialog("Restore \(pendingRestore?.shortName ?? "") to the draft?",
                                isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                                titleVisibility: .visible) {
                Button("Restore") {
                    if let v = pendingRestore { draft = v.content }
                    pendingRestore = nil
                }
                if isModified {
                    Button("Save Current Draft First") {
                        pendingRestore = nil
                        saveVersion()
                    }
                }
            } message: {
                Text(isModified
                     ? "Your draft has unsaved changes. They will be replaced unless you save them as a version first."
                     : "The draft will be replaced with this version. Your saved versions are not changed.")
            }
        }
    }

    private var timeline: some View {
        List(selection: $selected) {
            if isModified {
                HStack {
                    Image(systemName: "pencil.circle.fill").foregroundStyle(Theme.changed)
                    VStack(alignment: .leading) {
                        Text("Current draft").font(.headline)
                        if let latest = recipe.latestVersion {
                            Text(RecipeDiff(old: latest.content, new: draft).summary)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer()
                    Button("Save…", action: saveVersion).controlSize(.small)
                }
                .padding(.vertical, 4)
                .selectionDisabled()
            }
            let versions = recipe.sortedVersions
            ForEach(Array(versions.enumerated()), id: \.element.persistentModelID) { index, version in
                VersionRow(version: version,
                           previous: index + 1 < versions.count ? versions[index + 1] : nil,
                           isLatest: index == 0)
                    .tag(version.number)
                    .contextMenu {
                        Button("Restore to Draft…") { pendingRestore = version }
                        Button("Compare with Draft") { compare(.version(version.number), .draft) }
                        if index + 1 < versions.count {
                            Button("Compare with \(versions[index + 1].shortName)") {
                                compare(.version(versions[index + 1].number), .version(version.number))
                            }
                        }
                        Divider()
                        Button("Duplicate as New Recipe") { duplicate(version.content) }
                    }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let number = selected, let version = recipe.versions.first(where: { $0.number == number }) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(version.shortName) · \(version.label)").font(.headline)
                        Text(version.createdAt, format: .dateTime.weekday().day().month().year().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Compare with Draft") { compare(.version(version.number), .draft) }
                    Button("Restore…") { pendingRestore = version }
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(.bar)
                Divider()
                ScrollView { RecipeReadView(content: version.content).padding(20) }
            }
        } else {
            ContentUnavailableView("Select a version", systemImage: "doc.text.magnifyingglass")
        }
    }
}

struct VersionRow: View {
    @Bindable var version: RecipeVersion
    let previous: RecipeVersion?
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(version.shortName)
                    .font(.caption.monospaced().bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(isLatest ? Theme.accent : Color.secondary.opacity(0.2), in: Capsule())
                    .foregroundStyle(isLatest ? .white : .primary)
                Text(version.label).font(.headline).lineLimit(1)
                Spacer()
                RatingView(rating: $version.rating, size: .caption2)
            }
            if !version.changeNote.isEmpty {
                Text(version.changeNote).font(.callout).lineLimit(3)
            }
            HStack {
                Text(version.createdAt, format: .dateTime.day().month().year())
                if let previous {
                    Text("·")
                    Text(RecipeDiff(old: previous.content, new: version.content).summary).lineLimit(2)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Read-only rendering of a recipe state.
struct RecipeReadView: View {
    let content: RecipeContent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(content.title).font(.system(.title, design: .serif).bold())
            if !content.summary.isEmpty { Text(content.summary).foregroundStyle(.secondary) }
            HStack(spacing: 16) {
                Label("Serves \(content.servings)", systemImage: "person.2")
                Label(Format.minutes(content.prepMinutes), systemImage: "knife")
                Label(Format.minutes(content.cookMinutes), systemImage: "flame")
            }
            .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Ingredients").font(.headline)
            ForEach(content.ingredients) { Text("•  \($0.display)") }
            Text("Method").font(.headline).padding(.top, 6)
            ForEach(Array(content.steps.enumerated()), id: \.element.id) { i, step in
                HStack(alignment: .top) {
                    Text("\(i + 1).").bold().monospacedDigit()
                    Text(step.text)
                }
            }
            if !content.substitutions.isEmpty {
                Text("Substitutions").font(.headline).padding(.top, 6)
                ForEach(content.substitutions) { s in
                    Label("\(s.original) → \(s.replacement)\(s.ratio.isEmpty ? "" : " (\(s.ratio))")", systemImage: s.outcome.symbol)
                        .foregroundStyle(s.outcome.color)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Compare

struct CompareView: View {
    let recipe: Recipe
    let draft: RecipeContent
    @Binding var left: CompareSide
    @Binding var right: CompareSide

    private func content(_ side: CompareSide) -> RecipeContent {
        switch side {
        case .draft: draft
        case .version(let n): recipe.versions.first { $0.number == n }?.content ?? draft
        }
    }

    private func version(_ side: CompareSide) -> RecipeVersion? {
        if case .version(let n) = side { return recipe.versions.first { $0.number == n } }
        return nil
    }

    var body: some View {
        let diff = RecipeDiff(old: content(left), new: content(right))
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                sidePicker($left)
                Button { swap(&left, &right) } label: { Image(systemName: "arrow.left.arrow.right") }
                    .help("Swap sides")
                sidePicker($right)
            }
            .padding(12)
            .background(.bar)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        outcomeCard(left)
                        outcomeCard(right)
                    }
                    Text(diff.summary)
                        .font(.callout).foregroundStyle(.secondary)

                    if !diff.fields.isEmpty {
                        CanvasSection(title: "Details", symbol: "info.circle") {
                            ForEach(diff.fields) { f in
                                HStack(alignment: .top) {
                                    Text(f.label).bold().frame(width: 100, alignment: .leading)
                                    Text(f.old.isEmpty ? "—" : f.old).strikethrough().foregroundStyle(Theme.removed)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    Text(f.new.isEmpty ? "—" : f.new).foregroundStyle(Theme.added)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    CanvasSection(title: "Ingredients", symbol: "basket") {
                        ForEach(diff.ingredients) { row in ingredientRow(row) }
                        if diff.ingredients.isEmpty { Text("No ingredients").foregroundStyle(.secondary) }
                    }

                    CanvasSection(title: "Method", symbol: "list.number") {
                        HStack(alignment: .top, spacing: 16) {
                            stepColumn(diff.stepsOld, color: Theme.removed)
                            Divider()
                            stepColumn(diff.stepsNew, color: Theme.added)
                        }
                    }

                    if !diff.substitutions.isEmpty {
                        CanvasSection(title: "Substitutions", symbol: "arrow.triangle.swap") {
                            ForEach(diff.substitutions) { row in substitutionRow(row) }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    private func sidePicker(_ side: Binding<CompareSide>) -> some View {
        Picker("", selection: side) {
            Text("Current draft").tag(CompareSide.draft)
            ForEach(recipe.sortedVersions, id: \.persistentModelID) { v in
                Text("\(v.shortName) · \(v.label)").tag(CompareSide.version(v.number))
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private func outcomeCard(_ side: CompareSide) -> some View {
        let v = version(side)
        let c = content(side)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(v.map { "\($0.shortName) · \($0.label)" } ?? "Current draft").font(.headline).lineLimit(1)
                Spacer()
                if let v {
                    HStack(spacing: 1) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= v.rating ? "star.fill" : "star")
                                .foregroundStyle(i <= v.rating ? Color.yellow : Color.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
            if let note = v?.changeNote, !note.isEmpty { Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
            Text("Serves \(c.servings) · \(Format.minutes(c.totalMinutes)) total · \(c.ingredients.count) ingredients · \(c.steps.count) steps")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }

    @ViewBuilder
    private func ingredientRow(_ row: RecipeDiff.IngredientRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            statusBadge(row.status)
            switch row.status {
            case .same: Text(row.new?.display ?? "")
            case .added: Text(row.new?.display ?? "").foregroundStyle(Theme.added)
            case .removed: Text(row.old?.display ?? "").strikethrough().foregroundStyle(Theme.removed)
            case .changed:
                Text(row.old?.display ?? "").strikethrough().foregroundStyle(Theme.removed)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Text(row.new?.display ?? "").foregroundStyle(Theme.changed)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func substitutionRow(_ row: RecipeDiff.SubstitutionRow) -> some View {
        let s = row.new ?? row.old!
        HStack(spacing: 10) {
            statusBadge(row.status)
            Text("\(s.original) → \(s.replacement)")
                .strikethrough(row.status == .removed)
            if row.status == .changed, let o = row.old, o.outcome != s.outcome {
                Text("\(o.label(for: o.outcome)) → \(s.outcome.label)").font(.caption).foregroundStyle(.secondary)
            } else {
                Label(s.outcome.label, systemImage: s.outcome.symbol).font(.caption).foregroundStyle(s.outcome.color)
            }
            Spacer()
        }
    }

    private func stepColumn(_ rows: [RecipeDiff.StepRow], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(row.index).").bold().monospacedDigit()
                    Text(row.text.isEmpty ? "(empty)" : row.text)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(row.highlighted ? color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
            if rows.isEmpty { Text("No steps").foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func statusBadge(_ status: RecipeDiff.Status) -> some View {
        let (symbol, color): (String, Color) = switch status {
        case .same: ("circle", .secondary.opacity(0.4))
        case .added: ("plus.circle.fill", Theme.added)
        case .removed: ("minus.circle.fill", Theme.removed)
        case .changed: ("pencil.circle.fill", Theme.changed)
        }
        return Image(systemName: symbol).foregroundStyle(color).frame(width: 16)
    }
}

private extension Substitution {
    func label(for outcome: SubstitutionOutcome) -> String { outcome.label }
}
