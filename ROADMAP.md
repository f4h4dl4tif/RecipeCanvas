# RecipeCanvas Roadmap

RecipeCanvas is free and open source. Everything below is ordered by how much it helps cooks compared with
how hard it is to build. Contributions are welcome. Open an issue to claim an item.

## 1.1: Make cooking easier

1. ✅ **Cook Mode** (shipped). Full-screen, large-type step view that keeps the screen awake. Tap through steps, with timers
   detected from text ("bake 12 minutes" turns into a tap-to-start timer). After cooking it asks "How did it go?",
   then saves a rating and tasting note as a new version or note.
2. **Scaling and unit conversion.** Scale servings ×½/×2/custom, switch metric ⇄ US, and convert volume to weight
   for common ingredients (flour, sugar, butter).
3. **Import from the web.** Paste a URL and read its schema.org `Recipe` data. Most food blogs have it.
   This alone removes the biggest barrier to adoption: typing.
4. **Photos per version.** Attach "how it came out" photos to each version. Compare then shows photos side by side,
   which makes the "visual" in *visual studio* real.
5. **Substitution suggestions.** When you record a swap, suggest proven ones from your own log plus a built-in
   list (buttermilk = milk + lemon, egg = flax egg…), with ratios.

## 1.2: Experiment studio (the differentiator)

6. **Branches.** Fork a version into a parallel experiment ("gluten-free", "vegan", "high-altitude") without
   losing the main line. The history view becomes a small tree.
7. **Experiment log.** Record conditions per cook: oven used, altitude, pan, weather/humidity, who ate it, and a
   per-taster score. Compare shows which variables changed.
8. **Baker's percentages and hydration.** Optional view for bread, pizza and pastry people. They are the most
   passionate experimenters.
9. **Cost and nutrition per version.** Rough cost per serving and macros, so "v4 is 30% cheaper" is visible.

## 2.0: Family Recipe Library

10. **Family recipe library with iCloud sharing.** A shared library via CloudKit sharing. Each member keeps
    private drafts and shares chosen recipes. Attribution: "Grandma's original, Mum's v3".
11. **Heritage capture.** Scan handwritten cards (Vision OCR) into structured recipes, keep the original scan,
    and record voice memos of a relative explaining the dish. This is a strong emotional reason to buy.
12. **Printable family cookbook.** Choose recipes and get a designed PDF book with cover, table of contents,
    stories and photos. Gift-season marketing writes itself. Optionally offer print-on-demand.
13. **Comments and "I made this".** Family members add a tasting note or photo to a shared recipe.

## 2.x: Mobile companion (iPhone/iPad)

14. **Kitchen companion.** Synced library via CloudKit, Cook Mode on an iPad propped in the kitchen,
    and hands-free step advance by voice ("next").
15. **Grocery list.** Build a list from selected recipes (scaled), merge duplicates, group by aisle, and export to
    Reminders.
16. **Quick capture.** Snap a photo or dictate a note mid-cook, and it lands on the right recipe's current draft.
17. **Widgets and Live Activities.** Active timers on the Lock Screen and "what's cooking tonight".

## Smaller polish that reviewers notice

- Tags and smart collections (e.g. "under 30 min", "rated 5★", "has untested swaps")
- Meal planner calendar that feeds the grocery list
- Spotlight indexing and Quick Look for recipe cards
- Export/import `.recipecanvas` files (JSON + photos), plus Markdown and PDF export
- More card templates (vintage, minimal, two-column) and custom fonts and colours
- Allergen flags (contains nuts/dairy/gluten), checked automatically against substitutions

## Tagline

> **"Git for your grandmother's cookies."** The free, open-source recipe app that remembers every version
> you've cooked, what you swapped, and which one tasted best.
