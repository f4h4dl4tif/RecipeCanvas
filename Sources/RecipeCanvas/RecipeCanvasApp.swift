import SwiftUI
import SwiftData

@main
struct RecipeCanvasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Own folder in Application Support, so the library never shares SwiftData's generic `default.store`.
    static let container: ModelContainer = {
        let dir = URL.applicationSupportDirectory.appending(path: "RecipeCanvas", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = ModelConfiguration(url: dir.appending(path: "Library.store"))
        #if DEBUG
        if GlassSnapshot.isActive { config = ModelConfiguration(isStoredInMemoryOnly: true) }   // never touch the real library
        #endif
        do {
            return try ModelContainer(for: Recipe.self, RecipeVersion.self, PrepNote.self, configurations: config)
        } catch {
            fatalError("Could not open the recipe library: \(error)")
        }
    }()

    init() {
        #if DEBUG
        MainActor.assumeIsolated { CardSnapshot.runIfRequested() }
        #endif
    }

    var body: some Scene {
        WindowGroup("RecipeCanvas") {
            ContentView()
                .frame(minWidth: 1040, minHeight: 660)
                .tint(Theme.accent)
        }
        .modelContainer(Self.container)
        .commands { RecipeCommands() }

        WindowGroup("Cook Mode", id: "cook", for: UUID.self) { $recipeID in
            CookModeWindow(recipeID: recipeID)
                .tint(Theme.accent)
        }
        .modelContainer(Self.container)
        .defaultSize(width: 1200, height: 800)
        .commandsRemoved()

        Settings {
            SettingsView().tint(Theme.accent)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (swift run); harmless inside the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        if GlassSnapshot.isActive { DispatchQueue.main.async { GlassSnapshot.run() } }
        #endif
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Theme {
    static let accent = Color(red: 0.80, green: 0.40, blue: 0.24)      // terracotta
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.93)
    static let ink = Color(red: 0.20, green: 0.16, blue: 0.13)
    static let added = Color.green
    static let removed = Color.red
    static let changed = Color.orange
}

// MARK: - Menu commands

struct RecipeActions {
    var newRecipe: () -> Void
    var saveVersion: (() -> Void)?
    var printCard: (() -> Void)?
    var cook: (() -> Void)?
}

struct RecipeActionsKey: FocusedValueKey { typealias Value = RecipeActions }

extension FocusedValues {
    var recipeActions: RecipeActions? {
        get { self[RecipeActionsKey.self] }
        set { self[RecipeActionsKey.self] = newValue }
    }
}

struct RecipeCommands: Commands {
    @FocusedValue(\.recipeActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Recipe") { actions?.newRecipe() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Version…") { actions?.saveVersion?() }
                .keyboardShortcut("s")
                .disabled(actions?.saveVersion == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print Recipe Card…") { actions?.printCard?() }
                .keyboardShortcut("p")
                .disabled(actions?.printCard == nil)
        }
        CommandMenu("Recipe") {
            Button("Start Cook Mode") { actions?.cook?() }
                .keyboardShortcut("k")
                .disabled(actions?.cook == nil)
        }
    }
}
