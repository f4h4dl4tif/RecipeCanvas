# RecipeCanvas

A visual recipe and cooking-experiment studio for macOS. Build personal recipes, record ingredient
substitutions, compare cooking versions, keep preparation notes, and print recipe cards.

**Customers:** home cooks and food enthusiasts · **Price:** $19.99 one-time lifetime licence

## Build & run

Requires macOS 14+ and Xcode (the command-line tools alone can't build SwiftData macros).

```bash
./build.sh            # → build/RecipeCanvas.app (ad-hoc signed)
open build/RecipeCanvas.app
swift test            # parser, diff and versioning tests
```

`build.sh` sets `DEVELOPER_DIR` to `/Applications/Xcode.app` for you. Data lives in
`~/Library/Application Support/RecipeCanvas/Library.store`. Two sample recipes with history are added on first launch.

## How it works

| Concept | What it is |
|---|---|
| **Draft** | The working copy you edit. Autosaves on every change. |
| **Version** | An immutable snapshot of the draft (⌘S) with a name, change note and 1–5 star rating. |
| **Restore** | Copies a version back into the draft. History is never rewritten. |
| **Compare** | Any two versions (or a version vs. the draft): changed details, ingredients (+ / − / adjusted), steps side by side, substitutions. |
| **Substitutions** | Original → replacement, ratio, reason and outcome. Saved with each version, and gathered across recipes in the **Substitution Log**. |
| **Notes** | Belong to the recipe, not a version, typed as Prep, Timing, Technique, Tasting or General. Pinned notes print on cards. |
| **Recipe cards** | 4×6, 5×7, Half Letter, Letter, A4; Classic or Modern style; type auto-shrinks to fit; Print or save as PDF (⌘P). |

Quick add parses lines like `1 1/2 cups flour, sifted`; **Paste List** adds a whole clipboard ingredient list.

## Monetisation

`License.swift` uses the same Gumroad licence-key flow as the other apps: free tier = 5 of your own recipes
(samples don't count), lifetime key unlocks everything. Before release, set `LicenseConfig.productID` and
`purchaseURL`. Until then the dev key `RECIPECANVAS-DEV-UNLOCK` works. For the Mac App Store, replace
`activate()` with a StoreKit 2 non-consumable; the rest of the app only reads `isUnlocked`.

## Source map

- `Models.swift`: SwiftData models (`Recipe`, `RecipeVersion`, `PrepNote`) and the `RecipeContent` snapshot
- `RecipeDiff.swift`: version diffing and the ingredient-line parser
- `ContentView.swift`: library sidebar, recipe list, Substitution Log
- `RecipeDetailView.swift`: tabs, status bar, Save Version sheet
- `EditorViews.swift`: recipe editor, substitutions, notes
- `HistoryViews.swift`: version timeline, read-only preview, Compare
- `RecipeCard.swift`: card layout, PDF rendering, print sheet
- `License.swift`: lifetime licence and paywall

See [ROADMAP.md](ROADMAP.md) for the expansion plan.
