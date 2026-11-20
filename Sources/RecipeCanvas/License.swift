import Foundation
import SwiftUI

/// One-time $19.99 lifetime licence. The free tier allows a few personal recipes; a key unlocks everything forever.
///
/// Keys are sold and verified through Gumroad's licence API (Lemon Squeezy works the same way).
/// Fill in `productID` and `purchaseURL` before shipping. If you ship on the Mac App Store instead,
/// swap `activate` for a StoreKit 2 non-consumable purchase — the rest of the app only reads `isUnlocked`.
enum LicenseConfig {
    static let productID = ""                                     // Gumroad product_id — fill in before release
    static let purchaseURL = URL(string: "https://gumroad.com")!  // your product page
    static let price = "$19.99"
    static let freeRecipeLimit = 5
    /// Accepted only while `productID` is empty, so the paywall can be tested before a store exists.
    static let developmentKey = "RECIPECANVAS-DEV-UNLOCK"
}

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isUnlocked: Bool
    @Published private(set) var licensedEmail: String?
    @Published var isWorking = false
    @Published var lastError: String?

    private let defaults = UserDefaults.standard
    private let keyKey = "license.key"
    private let emailKey = "license.email"

    init() {
        isUnlocked = defaults.string(forKey: keyKey) != nil
        licensedEmail = defaults.string(forKey: emailKey)
    }

    func canCreateRecipe(ownRecipeCount: Int) -> Bool {
        isUnlocked || ownRecipeCount < LicenseConfig.freeRecipeLimit
    }

    func activate(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { lastError = "Enter your licence key."; return }
        lastError = nil
        isWorking = true
        defer { isWorking = false }

        if LicenseConfig.productID.isEmpty {
            if key == LicenseConfig.developmentKey { store(key: key, email: nil) }
            else { lastError = "The store isn't set up yet. Use the development key to test." }
            return
        }

        do {
            let result = try await verifyWithGumroad(key: key)
            if result.success && !result.refunded { store(key: key, email: result.email) }
            else if result.refunded { lastError = "This purchase was refunded." }
            else { lastError = result.message ?? "That key wasn't recognised." }
        } catch {
            lastError = "Couldn't reach the licence server. Check your connection and try again."
        }
    }

    func deactivate() {
        defaults.removeObject(forKey: keyKey)
        defaults.removeObject(forKey: emailKey)
        isUnlocked = false
        licensedEmail = nil
    }

    private func store(key: String, email: String?) {
        defaults.set(key, forKey: keyKey)
        if let email { defaults.set(email, forKey: emailKey) }
        licensedEmail = email
        isUnlocked = true
    }

    private struct VerifyResult { let success: Bool; let refunded: Bool; let email: String?; let message: String? }

    private func verifyWithGumroad(key: String) async throws -> VerifyResult {
        var request = URLRequest(url: URL(string: "https://api.gumroad.com/v2/licenses/verify")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "product_id", value: LicenseConfig.productID),
            .init(name: "license_key", value: key),
            .init(name: "increment_uses_count", value: "false"),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let purchase = json["purchase"] as? [String: Any] ?? [:]
        let refunded = (purchase["refunded"] as? Bool ?? false) || (purchase["chargebacked"] as? Bool ?? false)
        return VerifyResult(success: json["success"] as? Bool ?? false, refunded: refunded,
                            email: purchase["email"] as? String, message: json["message"] as? String)
    }
}

struct LicenseView: View {
    @EnvironmentObject var license: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    var showsClose = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "frying.pan.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("RecipeCanvas Lifetime").font(.title2.bold())
                    Text("\(LicenseConfig.price) once. Yours forever, no subscription.")
                        .foregroundStyle(.secondary)
                }
            }

            if license.isUnlocked {
                Label("Unlocked\(license.licensedEmail.map { " for \($0)" } ?? ""). Thank you!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Button("Remove licence from this Mac", role: .destructive) { license.deactivate() }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    feature("infinity", "Unlimited recipes (free: \(LicenseConfig.freeRecipeLimit))")
                    feature("clock.arrow.circlepath", "Full version history and side-by-side compare")
                    feature("arrow.triangle.swap", "Substitution log across all your recipes")
                    feature("printer", "Printable recipe cards and PDF export")
                    feature("gift", "All future 1.x updates included")
                }

                Button {
                    openURL(LicenseConfig.purchaseURL)
                } label: {
                    Text("Buy Lifetime Licence – \(LicenseConfig.price)").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Divider()
                Text("Already purchased? Enter your licence key:").font(.callout)
                HStack {
                    TextField("XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await license.activate(key) } }
                    Button("Activate") { Task { await license.activate(key) } }
                        .disabled(license.isWorking)
                }
                if license.isWorking { ProgressView().controlSize(.small) }
                if let error = license.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                if LicenseConfig.productID.isEmpty {
                    Text("Developer build: use key \(LicenseConfig.developmentKey)")
                        .font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
                }
            }

            if showsClose {
                HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).symbolRenderingMode(.hierarchical)
    }
}
