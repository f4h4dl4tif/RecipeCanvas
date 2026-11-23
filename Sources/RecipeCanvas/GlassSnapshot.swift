#if DEBUG
import SwiftUI
import SwiftData
import AppKit

/// Debug aid: `RecipeCanvas --glass-snapshot <dir>` captures the main window, Cook Mode and Settings with the
/// Liquid Glass theme off and on, light and dark, using sample recipes in an in-memory library. It captures the
/// real on-screen windows (cacheDisplay/ImageRenderer can't draw Liquid Glass), restores preferences and quits.
@MainActor
enum GlassSnapshot {
    nonisolated static var isActive: Bool { CommandLine.arguments.contains("--glass-snapshot") }

    static func run() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--glass-snapshot"), i + 1 < args.count else { exit(1) }
        let dir = args[i + 1]
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let saved = [GlassTheme.key, "didSeedSamples"].map { ($0, defaults.object(forKey: $0)) }
        func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

        let container = RecipeCanvasApp.container
        let context = container.mainContext
        wait(1.0)
        if ((try? context.fetchCount(FetchDescriptor<Recipe>())) ?? 0) == 0 { SampleData.seed(into: context) }
        try? context.save()
        wait(0.5)
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        guard let recipe = recipes.first(where: { $0.title.contains("Cookies") }) ?? recipes.first else { exit(1) }

        let main = NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
        main?.setContentSize(NSSize(width: 1240, height: 780))

        let cook = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        cook.isReleasedWhenClosed = false
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.title = "Settings"
        settings.isReleasedWhenClosed = false

        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for glass in [false, true] {
                defaults.set(glass, forKey: GlassTheme.key)
                let suffix = "\(glass ? "glass" : "plain")-\(dark ? "dark" : "light")"
                NSApp.activate(ignoringOtherApps: true)
                main?.makeKeyAndOrderFront(nil)
                wait(1.2)
                NSApp.activate(ignoringOtherApps: true)
                main?.makeKeyAndOrderFront(nil)
                wait(0.6)
                if let main { capture(main, "\(dir)/main-\(suffix).png") }

                cook.contentView = NSHostingView(rootView: CookModeView(recipe: recipe).modelContainer(container).tint(Theme.accent))
                cook.setContentSize(NSSize(width: 1200, height: 760))
                cook.center()
                cook.makeKeyAndOrderFront(nil)
                wait(1.5)
                NSApp.activate(ignoringOtherApps: true)
                cook.makeKeyAndOrderFront(nil)
                wait(0.8)
                capture(cook, "\(dir)/cook-\(suffix).png")
                cook.orderOut(nil)
                cook.contentView = nil

                settings.contentView = NSHostingView(rootView: SettingsView().tint(Theme.accent))
                settings.center()
                settings.makeKeyAndOrderFront(nil)
                wait(1.0)
                capture(settings, "\(dir)/settings-\(suffix).png")
                settings.orderOut(nil)
            }
        }
        for (k, v) in saved { if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) } }
        exit(0)
    }

    private typealias CapFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static func capture(_ window: NSWindow, _ path: String) {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return }
        let f = unsafeBitCast(sym, to: CapFn.self)
        guard let img = f(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else { return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("glass-snapshot: wrote \(path)")
    }
}
#endif
