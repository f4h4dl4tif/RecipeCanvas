import Foundation
import SwiftData

/// Two example recipes with real history, so the History and Compare tabs make sense on first launch.
enum SampleData {
    static func seed(into context: ModelContext) {
        let p = IngredientParser.parse
        let day: TimeInterval = 86_400

        // Cookies: three versions showing an evolving experiment.
        var v1 = RecipeContent(
            title: "Chocolate Chip Cookies",
            summary: "Chewy centres, crisp edges. The base recipe everything else grew from.",
            servings: 24, prepMinutes: 15, cookMinutes: 12,
            ingredients: ["225 g butter, softened", "200 g brown sugar", "100 g white sugar", "2 eggs",
                          "2 tsp vanilla extract", "280 g all-purpose flour", "1 tsp baking soda",
                          "1 tsp salt", "300 g chocolate chips"].map(p),
            steps: ["Heat oven to 190°C / 375°F and line two trays.",
                    "Cream butter and both sugars until pale, about 3 minutes.",
                    "Beat in eggs one at a time, then vanilla.",
                    "Whisk flour, baking soda and salt; fold into the butter mixture.",
                    "Stir in chocolate chips.",
                    "Scoop 2-tablespoon balls onto trays and bake 10–12 minutes."].map { Step(text: $0) })

        var v2 = v1
        v2.summary = "Brown butter version — deeper, nuttier, toffee-like."
        v2.ingredients[0] = Ingredient(id: v1.ingredients[0].id, quantity: "225", unit: "g", name: "butter", note: "browned and cooled")
        v2.steps[1] = Step(id: v1.steps[1].id, text: "Brown the butter, cool 15 minutes, then whisk with both sugars.")
        v2.steps.insert(Step(text: "Chill the dough at least 2 hours (overnight is best)."), at: 5)
        v2.prepMinutes = 30

        var v3 = v2
        v3.ingredients.removeAll { $0.name == "chocolate chips" }
        v3.ingredients.append(p("300 g dark chocolate, chopped"))
        v3.ingredients.append(p("flaky sea salt, to finish"))
        v3.ingredients[6] = Ingredient(id: v2.ingredients[6].id, quantity: "1/2", unit: "tsp", name: "baking soda", note: "")
        v3.steps[4] = Step(id: v2.steps[4].id, text: "Stir in chopped chocolate.")
        v3.steps.append(Step(text: "Sprinkle with flaky salt straight out of the oven."))
        v3.substitutions = [
            Substitution(original: "chocolate chips", replacement: "chopped dark chocolate (70%)", ratio: "1:1 by weight",
                         reason: "Wanted melty puddles instead of chips", outcome: .great, notes: "Much better texture."),
            Substitution(original: "all-purpose flour", replacement: "half bread flour", ratio: "140 g + 140 g",
                         reason: "More chew", outcome: .okay, notes: "Chewier but a little tough on day two."),
        ]

        let cookies = Recipe(content: v3, category: "Baking", isSample: true)
        cookies.isFavorite = true
        cookies.createdAt = .now - 21 * day
        context.insert(cookies)
        cookies.versions.append(RecipeVersion(number: 1, label: "Original", changeNote: "Family base recipe.",
                                              rating: 3, content: v1, createdAt: .now - 21 * day))
        cookies.versions.append(RecipeVersion(number: 2, label: "Brown butter + chill", changeNote: "Browned the butter and added an overnight chill.",
                                              rating: 4, content: v2, createdAt: .now - 10 * day))
        cookies.versions.append(RecipeVersion(number: 3, label: "Chopped chocolate & flaky salt", changeNote: "Swapped chips for chopped bar, less soda, flaky salt on top.",
                                              rating: 5, content: v3, createdAt: .now - 2 * day))
        cookies.notes.append(PrepNote(text: "Weigh the flour — cups make these cakey.", kind: .prep, isPinned: true))
        cookies.notes.append(PrepNote(text: "Pull them when the centres still look underbaked; they set on the tray.", kind: .timing))
        cookies.notes.append(PrepNote(text: "v3 is the keeper. Kids preferred v2 slightly warmer.", kind: .tasting))

        // Soup: one saved version and an uncommitted experiment in the draft.
        let soupV1 = RecipeContent(
            title: "Weeknight Tomato Soup",
            summary: "Pantry soup that tastes like it simmered all afternoon.",
            servings: 4, prepMinutes: 10, cookMinutes: 25,
            ingredients: ["2 tbsp olive oil", "1 onion, diced", "3 cloves garlic, sliced",
                          "2 cans whole tomatoes", "500 ml vegetable stock", "1 tsp sugar", "salt and pepper, to taste"].map(p),
            steps: ["Soften onion in olive oil over medium heat, 8 minutes.",
                    "Add garlic and cook 1 minute.",
                    "Add tomatoes, stock and sugar; simmer 20 minutes.",
                    "Blend until smooth and season."].map { Step(text: $0) })
        var soupDraft = soupV1
        soupDraft.ingredients.append(p("60 ml cream, optional"))
        soupDraft.ingredients[0].name = "butter"
        soupDraft.substitutions = [Substitution(original: "olive oil", replacement: "butter", ratio: "1:1",
                                                reason: "Richer flavour", outcome: .untested)]
        let soup = Recipe(content: soupDraft, category: "Soups", isSample: true)
        soup.createdAt = .now - 5 * day
        context.insert(soup)
        soup.versions.append(RecipeVersion(number: 1, label: "First try", changeNote: "Simple pantry version.",
                                           rating: 4, content: soupV1, createdAt: .now - 5 * day))
        soup.notes.append(PrepNote(text: "San Marzano tomatoes are worth it here.", kind: .general))

        try? context.save()
    }
}
