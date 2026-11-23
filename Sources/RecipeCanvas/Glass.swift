import SwiftUI

/// Liquid Glass theme setting (macOS 26+). Off by default; when off RecipeCanvas looks exactly as before.
enum GlassTheme {
    static let key = "glassTheme"
    static var supported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

extension View {
    /// Liquid Glass in `shape` when the theme is on, otherwise the given plain background.
    @ViewBuilder
    func glassSurface<S: Shape, B: View>(_ glassOn: Bool, in shape: S, tint: Color? = nil,
                                         @ViewBuilder plain: () -> B) -> some View {
        if #available(macOS 26, *), glassOn {
            self.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
        } else {
            self.background(plain())
        }
    }

    /// `.glass` / `.glassProminent` when the theme is on; otherwise the button keeps its usual style.
    @ViewBuilder
    func glassButton(_ glassOn: Bool, prominent: Bool = false, bordered: Bool = false) -> some View {
        if #available(macOS 26, *), glassOn {
            // Plain glass stays neutral; only prominent buttons take the accent colour.
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass).tint(nil) }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else if bordered {
            self.buttonStyle(.bordered)
        } else {
            self
        }
    }

    /// Groups nearby glass shapes so they blend and refract together (macOS 26+).
    @ViewBuilder
    func glassContainer(_ glassOn: Bool, spacing: CGFloat = 12) -> some View {
        if #available(macOS 26, *), glassOn {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

struct SettingsView: View {
    @AppStorage(GlassTheme.key) private var glass = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle(isOn: $glass) {
                    Text("Liquid Glass theme")
                    Text(GlassTheme.supported
                         ? "Cook Mode controls, timers and floating buttons use Apple's Liquid Glass."
                         : "Requires macOS 26.")
                }
                .disabled(!GlassTheme.supported)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
