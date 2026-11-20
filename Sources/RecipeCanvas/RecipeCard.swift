import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

enum CardSize: String, CaseIterable, Identifiable {
    case index4x6 = "4 × 6 in", card5x7 = "5 × 7 in", halfLetter = "Half Letter", letter = "US Letter", a4 = "A4"
    var id: String { rawValue }
    /// Size in PostScript points (1/72 in).
    var points: CGSize {
        switch self {
        case .index4x6: CGSize(width: 432, height: 288)       // landscape, like a recipe box card
        case .card5x7: CGSize(width: 504, height: 360)
        case .halfLetter: CGSize(width: 396, height: 612)
        case .letter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595, height: 842)
        }
    }
}

enum CardStyle: String, CaseIterable, Identifiable {
    case classic = "Classic", modern = "Modern"
    var id: String { rawValue }
}

struct CardOptions: Equatable {
    var size: CardSize = .card5x7
    var style: CardStyle = .classic
    var includeNotes = true
    var includeSubstitutions = true
}

/// The printable card. Fixed colours so it looks the same in dark mode and on paper.
struct RecipeCardView: View {
    let content: RecipeContent
    let versionLabel: String
    let notes: [String]
    let options: CardOptions

    var body: some View {
        let size = options.size.points
        // Try progressively smaller type until everything fits on the card.
        ViewThatFits(in: .vertical) {
            ForEach([1.0, 0.88, 0.76, 0.66, 0.57, 0.5], id: \.self) { scale in
                card(scale: scale, size: size)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(options.style == .classic ? Theme.paper : .white)
        .overlay(alignment: .top) {
            if options.style == .modern { Theme.accent.frame(height: 6) }
        }
        .environment(\.colorScheme, .light)
    }

    private func card(scale s: CGFloat, size: CGSize) -> some View {
        let serif = options.style == .classic
        let base = (size.width < 450 ? 9.5 : 11) * s
        let font = { (sz: CGFloat, w: Font.Weight) in Font.system(size: sz, weight: w, design: serif ? .serif : .default) }
        let landscape = size.width > size.height
        let pad = max(14, size.width * 0.05)

        let ingredients = VStack(alignment: .leading, spacing: 3 * s) {
            Text("INGREDIENTS").font(font(base * 0.8, .bold)).kerning(1).foregroundStyle(Theme.accent)
            ForEach(content.ingredients) { ing in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("•").foregroundStyle(Theme.accent)
                    (Text(ing.amount.isEmpty ? "" : ing.amount + " ").bold() + Text(ing.name)
                        + Text(ing.note.isEmpty ? "" : ", \(ing.note)").italic())
                }
                .font(font(base, .regular))
            }
        }
        let method = VStack(alignment: .leading, spacing: 4 * s) {
            Text("METHOD").font(font(base * 0.8, .bold)).kerning(1).foregroundStyle(Theme.accent)
            ForEach(Array(content.steps.enumerated()), id: \.element.id) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(i + 1).").bold().foregroundStyle(Theme.accent).monospacedDigit()
                    Text(step.text)
                }
                .font(font(base, .regular))
            }
        }
        let worked = content.substitutions.filter { $0.outcome == .great || $0.outcome == .okay }

        return VStack(alignment: .leading, spacing: 8 * s) {
            VStack(alignment: .leading, spacing: 3 * s) {
                Text(content.title).font(font(base * 2.0, .bold))
                let meta = ["Serves \(content.servings)",
                            content.prepMinutes > 0 ? "Prep \(Format.minutes(content.prepMinutes))" : nil,
                            content.cookMinutes > 0 ? "Cook \(Format.minutes(content.cookMinutes))" : nil]
                    .compactMap { $0 }.joined(separator: "  ·  ")
                Text(meta).font(font(base * 0.85, .medium)).foregroundStyle(Theme.ink.opacity(0.65))
                if !content.summary.isEmpty {
                    Text(content.summary).font(font(base * 0.95, .regular)).italic().foregroundStyle(Theme.ink.opacity(0.8))
                }
            }
            Rectangle().fill(Theme.accent.opacity(0.5)).frame(height: 1)

            if landscape {
                HStack(alignment: .top, spacing: 14 * s) {
                    ingredients.frame(width: size.width * 0.36, alignment: .leading)
                    method.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ingredients
                method
            }

            if options.includeSubstitutions && !worked.isEmpty {
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text("SWAPS THAT WORK").font(font(base * 0.75, .bold)).kerning(1).foregroundStyle(Theme.accent)
                    ForEach(worked) { sub in
                        Text("\(sub.original) → \(sub.replacement)\(sub.ratio.isEmpty ? "" : " (\(sub.ratio))")")
                            .font(font(base * 0.85, .regular))
                    }
                }
            }
            if options.includeNotes && !notes.isEmpty {
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text("NOTES").font(font(base * 0.75, .bold)).kerning(1).foregroundStyle(Theme.accent)
                    ForEach(notes, id: \.self) { Text($0).font(font(base * 0.85, .regular)).italic() }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text("\(versionLabel) · RecipeCanvas").font(.system(size: max(6, base * 0.65))).foregroundStyle(Theme.ink.opacity(0.4))
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(pad)
        .padding(.top, options.style == .modern ? 6 : 0)
        .frame(width: size.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum CardRenderer {
    @MainActor
    static func pdfData(content: RecipeContent, versionLabel: String, notes: [String], options: CardOptions) -> Data {
        let size = options.size.points
        let view = RecipeCardView(content: content, versionLabel: versionLabel, notes: notes, options: options)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        let data = NSMutableData()
        renderer.render { _, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return data as Data
    }
}

struct RecipeCardSheet: View {
    let content: RecipeContent
    let versionLabel: String
    let notes: [String]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("card.size") private var sizeRaw = CardSize.card5x7.rawValue
    @AppStorage("card.style") private var styleRaw = CardStyle.classic.rawValue
    @AppStorage("card.notes") private var includeNotes = true
    @AppStorage("card.subs") private var includeSubs = true

    private var options: CardOptions {
        CardOptions(size: CardSize(rawValue: sizeRaw) ?? .card5x7, style: CardStyle(rawValue: styleRaw) ?? .classic,
                    includeNotes: includeNotes, includeSubstitutions: includeSubs)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Preview
            GeometryReader { geo in
                let size = options.size.points
                let scale = min((geo.size.width - 40) / size.width, (geo.size.height - 40) / size.height, 1.4)
                RecipeCardView(content: content, versionLabel: versionLabel, notes: notes, options: options)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            // Options
            Form {
                Section("Card") {
                    Picker("Size", selection: $sizeRaw) {
                        ForEach(CardSize.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("Style", selection: $styleRaw) {
                        ForEach(CardStyle.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Include") {
                    Toggle("Pinned notes", isOn: $includeNotes)
                    Toggle("Swaps that work", isOn: $includeSubs)
                }
                Section {
                    Text("Type shrinks automatically to fit. Long recipes print best on Half Letter or larger.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(width: 260)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button { printCard() } label: { Label("Print…", systemImage: "printer").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Button { savePDF() } label: { Label("Save as PDF…", systemImage: "arrow.down.doc").frame(maxWidth: .infinity) }
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                .controlSize(.large)
                .padding(14)
            }
        }
        .frame(width: 920, height: 620)
    }

    private var pdf: Data {
        CardRenderer.pdfData(content: content, versionLabel: versionLabel, notes: notes, options: options)
    }

    private func printCard() {
        guard let document = PDFDocument(data: pdf) else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = options.size.points
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.orientation = options.size.points.width > options.size.points.height ? .landscape : .portrait
        guard let op = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        op.jobTitle = content.title
        if let window = NSApp.keyWindow {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    private func savePDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(content.title.isEmpty ? "Recipe" : content.title).pdf"
        let data = pdf
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}

#if DEBUG
/// Debug-only: `RecipeCanvas --render-cards <dir>` writes sample cards as PDF + PNG, then exits.
enum CardSnapshot {
    @MainActor static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-cards"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = IngredientParser.parse
        let content = RecipeContent(
            title: "Chocolate Chip Cookies", summary: "Chewy centres, crisp edges.", servings: 24, prepMinutes: 30, cookMinutes: 12,
            ingredients: ["225 g butter, browned", "200 g brown sugar", "100 g white sugar", "2 eggs", "2 tsp vanilla",
                          "280 g flour", "1/2 tsp baking soda", "1 tsp salt", "300 g dark chocolate, chopped"].map(p),
            steps: ["Heat oven to 190°C.", "Brown butter, cool, whisk with sugars.", "Beat in eggs and vanilla.",
                    "Fold in dry ingredients.", "Stir in chocolate.", "Chill 2 hours.", "Bake 10–12 minutes."].map { Step(text: $0) },
            substitutions: [Substitution(original: "chocolate chips", replacement: "chopped dark chocolate", ratio: "1:1", outcome: .great)])
        for size in CardSize.allCases {
            for style in CardStyle.allCases {
                let opts = CardOptions(size: size, style: style)
                let name = "\(size.id)-\(style.id)".replacingOccurrences(of: " ", with: "")
                let data = CardRenderer.pdfData(content: content, versionLabel: "v3", notes: ["Weigh the flour."], options: opts)
                try? data.write(to: dir.appendingPathComponent("\(name).pdf"))
                let r = ImageRenderer(content: RecipeCardView(content: content, versionLabel: "v3", notes: ["Weigh the flour."], options: opts))
                r.scale = 2
                if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
                }
            }
        }
        exit(0)
    }
}
#endif
