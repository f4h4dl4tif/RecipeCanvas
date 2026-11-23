import SwiftUI
import SwiftData
import AppKit

// MARK: - Timers

struct CookTimer: Identifiable {
    let id = UUID()
    let label: String
    let stepNumber: Int
    let total: Int
    var endDate: Date?          // set while running
    var pausedRemaining: Int?   // set while paused
    var acknowledged = false

    func remaining(at now: Date) -> Int {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return total }
        return max(0, Int(endDate.timeIntervalSince(now).rounded(.up)))
    }
    func isDone(at now: Date) -> Bool { remaining(at: now) == 0 }
}

@MainActor
final class CookTimerStore: ObservableObject {
    @Published var timers: [CookTimer] = []
    private var ticker: Timer?
    private var alerted = Set<UUID>()

    func start(_ detected: DetectedTimer, step: Int) {
        timers.append(CookTimer(label: detected.label, stepNumber: step, total: detected.seconds,
                                endDate: .now + TimeInterval(detected.seconds)))
        ensureTicker()
    }

    func togglePause(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        if let remaining = timers[i].pausedRemaining {
            timers[i].pausedRemaining = nil
            timers[i].endDate = .now + TimeInterval(remaining)
        } else {
            timers[i].pausedRemaining = timers[i].remaining(at: .now)
            timers[i].endDate = nil
        }
    }

    func add(_ id: UUID, seconds: Int) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        if let p = timers[i].pausedRemaining { timers[i].pausedRemaining = p + seconds }
        else { timers[i].endDate = max(timers[i].endDate ?? .now, .now) + TimeInterval(seconds) }
        alerted.remove(id)
        timers[i].acknowledged = false
    }

    func remove(_ id: UUID) {
        timers.removeAll { $0.id == id }
        alerted.remove(id)
    }

    func stopAll() {
        ticker?.invalidate()
        ticker = nil
        timers.removeAll()
    }

    private func ensureTicker() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let now = Date()
        for t in timers where t.isDone(at: now) && !t.acknowledged {
            // Chime every few seconds until dismissed.
            if !alerted.contains(t.id) || Int(now.timeIntervalSince1970) % 4 == 0 {
                NSSound(named: "Glass")?.play()
                alerted.insert(t.id)
            }
        }
    }
}

// MARK: - Cook Mode window

/// Window content for `WindowGroup(id: "cook", for: UUID.self)`.
struct CookModeWindow: View {
    let recipeID: UUID?
    @Query private var recipes: [Recipe]

    var body: some View {
        if let recipe = recipes.first(where: { $0.id == recipeID }) {
            CookModeView(recipe: recipe)
        } else {
            ContentUnavailableView("Recipe not found", systemImage: "fork.knife")
                .frame(minWidth: 500, minHeight: 300)
        }
    }
}

struct CookModeView: View {
    @Bindable var recipe: Recipe
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.modelContext) private var context
    @StateObject private var timers = CookTimerStore()

    @State private var content: RecipeContent
    @State private var stepIndex = 0              // steps.count == finish screen
    @State private var checked = Set<UUID>()
    @State private var showIngredients = true
    @State private var awake: NSObjectProtocol?
    @State private var window: NSWindow?
    @AppStorage(GlassTheme.key) private var glass = false

    // Finish screen
    @State private var rating = 0
    @State private var tastingNote = ""
    @State private var saveAsVersion = true
    @State private var saved = false

    init(recipe: Recipe) {
        self.recipe = recipe
        _content = State(initialValue: recipe.draft)
    }

    private var steps: [Step] { content.steps.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var isFinish: Bool { stepIndex >= steps.count }
    private var draftIsSaved: Bool { !recipe.hasChanges(comparedTo: content) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                if showIngredients {
                    ingredientPanel.frame(width: 300)
                    Divider()
                }
                Group {
                    if steps.isEmpty { noSteps } else if isFinish { finishScreen } else { stepScreen }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !timers.timers.isEmpty {
                Divider()
                timerTray
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.paper.opacity(0.35))
        .background(WindowAccessor { window = $0 })
        .navigationTitle("Cooking: \(content.title)")
        .onAppear {
            awake = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Cook Mode keeps the screen on")
            rating = recipe.latestVersion?.rating ?? 0
            #if DEBUG
            if GlassSnapshot.isActive { timers.start(DetectedTimer(label: "12 minutes", seconds: 720), step: 1) }
            #endif
        }
        .onChange(of: window) { _, w in
            #if DEBUG
            if GlassSnapshot.isActive { return }
            #endif
            if let w, !w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        }
        .onDisappear {
            if let awake { ProcessInfo.processInfo.endActivity(awake) }
            timers.stopAll()
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { showIngredients.toggle() } label: {
                Label("Ingredients", systemImage: "sidebar.left")
            }
            .glassButton(glass)
            .help("Show or hide ingredients")
            VStack(alignment: .leading, spacing: 1) {
                Text(content.title).font(.title3.bold()).lineLimit(1)
                Text(draftIsSaved ? (recipe.latestVersion.map { "\($0.shortName) · \($0.label)" } ?? "Draft") : "Unsaved draft")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !steps.isEmpty {
                HStack(spacing: 5) {
                    ForEach(0...steps.count, id: \.self) { i in
                        Capsule()
                            .fill(i == stepIndex ? Theme.accent : (i < stepIndex ? Theme.accent.opacity(0.45) : Color.secondary.opacity(0.25)))
                            .frame(width: i == stepIndex ? 22 : 8, height: 8)
                            .onTapGesture { withAnimation { stepIndex = i } }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: stepIndex)
                .padding(.horizontal, glass ? 12 : 0).padding(.vertical, glass ? 9 : 0)
                .glassSurface(glass, in: Capsule()) { EmptyView() }
            }
            Spacer()
            Button {
                window?.toggleFullScreen(nil)
            } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .glassButton(glass)
                .help("Toggle full screen")
            Button("Done") { close() }
                .glassButton(glass)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Ingredients checklist

    private var ingredientPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Ingredients").font(.headline)
                Spacer()
                Text("\(checked.count)/\(content.ingredients.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(14)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(content.ingredients) { ing in
                        let done = checked.contains(ing.id)
                        Button {
                            if done { checked.remove(ing.id) } else { checked.insert(ing.id) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(done ? Theme.accent : .secondary)
                                (Text(ing.amount.isEmpty ? "" : ing.amount + " ").bold() + Text(ing.name)
                                    + Text(ing.note.isEmpty ? "" : ", \(ing.note)").foregroundColor(.secondary))
                                    .strikethrough(done)
                                    .opacity(done ? 0.5 : 1)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 17))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !content.substitutions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Swaps").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(content.substitutions) { s in
                        Label("\(s.original) → \(s.replacement)", systemImage: s.outcome.symbol)
                            .foregroundStyle(s.outcome.color)
                            .font(.callout)
                    }
                }
                .padding(14)
            }
        }
        .background(.background.opacity(0.6))
    }

    // MARK: Step

    private var stepScreen: some View {
        let step = steps[stepIndex]
        let detected = TimerDetector.detect(in: step.text)
        return VStack(spacing: 0) {
            Spacer(minLength: 20)
            Text("STEP \(stepIndex + 1) OF \(steps.count)")
                .font(.system(size: 15, weight: .bold)).kerning(2)
                .foregroundStyle(Theme.accent)
            ScrollView {
                Text(step.text)
                    .font(.system(size: 40, weight: .medium, design: .serif))
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)

            if !detected.isEmpty {
                HStack(spacing: 12) {
                    ForEach(detected) { t in
                        Button { timers.start(t, step: stepIndex + 1) } label: {
                            Label("Start \(TimerDetector.format(t.seconds)) timer", systemImage: "timer")
                                .font(.title3)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                        }
                        .glassButton(glass, bordered: true)
                        .help("Detected “\(t.label)”")
                    }
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 20)
            HStack {
                Button { withAnimation { stepIndex -= 1 } } label: {
                    Label("Previous", systemImage: "chevron.left").frame(minWidth: 140)
                }
                .glassButton(glass)
                .disabled(stepIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])
                Spacer()
                Text("← → or Space to move between steps").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button { withAnimation { stepIndex += 1 } } label: {
                    Label(stepIndex == steps.count - 1 ? "Finish" : "Next", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .frame(minWidth: 140)
                }
                .glassButton(glass, prominent: true)
                .keyboardShortcut(.rightArrow, modifiers: [])
                // Space also advances.
                Button("") { withAnimation { stepIndex += 1 } }
                    .keyboardShortcut(.space, modifiers: [])
                    .opacity(0).frame(width: 0)
                    .accessibilityHidden(true)
            }
            .controlSize(.extraLarge)
            .padding(24)
        }
        .id(stepIndex)
        .transition(.opacity)
    }

    private var noSteps: some View {
        ContentUnavailableView("No steps to cook", systemImage: "list.number",
                               description: Text("Add method steps in the recipe editor, then start Cook Mode again."))
    }

    // MARK: Finish

    private var finishScreen: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                Text("How did it turn out?").font(.system(size: 34, weight: .bold, design: .serif))
                if saved {
                    Label("Saved. Enjoy your meal!", systemImage: "checkmark.seal.fill")
                        .font(.title3).foregroundStyle(.green)
                    HStack {
                        Button("Back to Steps") { stepIndex = 0; saved = false }.glassButton(glass)
                        Button("Close Cook Mode") { close() }.glassButton(glass, prominent: true)
                    }
                    .controlSize(.large)
                } else {
                    RatingView(rating: $rating, size: .system(size: 34))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tasting notes").font(.headline)
                        TextEditor(text: $tastingNote)
                            .font(.title3)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(height: 120)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                        Text("Too salty? Needed 2 more minutes? Who loved it? This becomes a Tasting note on the recipe.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 560)

                    if draftIsSaved, let latest = recipe.latestVersion {
                        Text("The rating will be saved on \(latest.shortName) · \(latest.label).")
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("Save this draft as version \((recipe.latestVersion?.number ?? 0) + 1) with the rating", isOn: $saveAsVersion)
                            .toggleStyle(.checkbox)
                    }

                    HStack {
                        Button("Skip") { close() }.glassButton(glass)
                        Button("Save") { saveResult() }
                            .glassButton(glass, prominent: true)
                            .keyboardShortcut(.defaultAction)
                    }
                    .controlSize(.large)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }

    private func saveResult() {
        let note = tastingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if draftIsSaved, let latest = recipe.latestVersion {
            if rating > 0 { latest.rating = rating }
        } else if saveAsVersion {
            recipe.commitVersion(content, label: "Cooked \(Date.now.formatted(.dateTime.day().month()))",
                                 note: note.isEmpty ? "Saved from Cook Mode." : note, rating: rating)
        }
        if !note.isEmpty {
            let version = recipe.latestVersion.map { "[\($0.shortName)] " } ?? ""
            recipe.notes.append(PrepNote(text: version + note, kind: .tasting))
        }
        try? context.save()
        saved = true
    }

    // MARK: Timers tray

    private var timerTray: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(timers.timers) { t in timerChip(t, now: ctx.date) }
                }
                .glassContainer(glass)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
        .background(.bar)
    }

    private func timerChip(_ t: CookTimer, now: Date) -> some View {
        let remaining = t.remaining(at: now)
        let done = remaining == 0
        let progress = 1 - Double(remaining) / Double(max(t.total, 1))
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                Circle().trim(from: 0, to: progress)
                    .stroke(done ? Color.red : Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(done ? "Done!" : TimerDetector.format(remaining))
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(done ? .red : .primary)
                Text("Step \(t.stepNumber) · \(t.label)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if done {
                Button("+1 min") { timers.add(t.id, seconds: 60) }
                Button("Dismiss") { timers.remove(t.id) }.buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button { timers.togglePause(t.id) } label: {
                    Image(systemName: t.pausedRemaining == nil ? "pause.fill" : "play.fill")
                }
                .help(t.pausedRemaining == nil ? "Pause" : "Resume")
                Button { timers.remove(t.id) } label: { Image(systemName: "xmark") }
                    .help("Cancel timer")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(glass, in: RoundedRectangle(cornerRadius: 12), tint: done ? Color.red.opacity(0.25) : nil) {
            RoundedRectangle(cornerRadius: 12).fill(done ? Color.red.opacity(0.12) : Color.secondary.opacity(0.08))
        }
    }

    private func close() { dismissWindow() }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

/// Hands back the hosting NSWindow so Cook Mode can enter full screen.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let w = view.window { onWindow(w) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
