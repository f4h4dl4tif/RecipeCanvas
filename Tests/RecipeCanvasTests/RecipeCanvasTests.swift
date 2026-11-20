import XCTest
import SwiftData
@testable import RecipeCanvas

final class IngredientParserTests: XCTestCase {
    func testQuantityUnitNameNote() {
        let i = IngredientParser.parse("1 1/2 cups flour, sifted")
        XCTAssertEqual(i.quantity, "1 1/2"); XCTAssertEqual(i.unit, "cups")
        XCTAssertEqual(i.name, "flour"); XCTAssertEqual(i.note, "sifted")
    }
    func testNoUnit() {
        let i = IngredientParser.parse("2 eggs")
        XCTAssertEqual(i.quantity, "2"); XCTAssertEqual(i.unit, ""); XCTAssertEqual(i.name, "eggs")
    }
    func testNoQuantityAndBullet() {
        let i = IngredientParser.parse("- salt and pepper, to taste")
        XCTAssertEqual(i.quantity, ""); XCTAssertEqual(i.name, "salt and pepper"); XCTAssertEqual(i.note, "to taste")
    }
    func testUnicodeFraction() {
        XCTAssertEqual(IngredientParser.parse("½ tsp salt").quantity, "½")
    }
}

final class RecipeDiffTests: XCTestCase {
    func testDetectsAddedRemovedChanged() {
        let flour = Ingredient(quantity: "2", unit: "cups", name: "flour")
        let sugar = Ingredient(quantity: "1", unit: "cup", name: "sugar")
        let old = RecipeContent(title: "Cake", ingredients: [flour, sugar], steps: [Step(text: "Mix"), Step(text: "Bake")])
        var new = old
        new.ingredients[0].quantity = "3"
        new.ingredients.remove(at: 1)
        new.ingredients.append(Ingredient(quantity: "1", unit: "tsp", name: "salt"))
        new.steps.insert(Step(text: "Rest"), at: 1)
        new.servings = 8
        let d = RecipeDiff(old: old, new: new)
        XCTAssertEqual(d.count(.changed), 1)
        XCTAssertEqual(d.count(.removed), 1)
        XCTAssertEqual(d.count(.added), 1)
        XCTAssertEqual(d.stepChanges, 1)
        XCTAssertTrue(d.stepsNew[1].highlighted)
        XCTAssertEqual(d.fields.map(\.label), ["Servings"])
        XCTAssertFalse(d.isEmpty)
    }
    func testIdenticalIsEmpty() {
        let c = RecipeContent(title: "Soup", ingredients: [Ingredient(name: "water")], steps: [Step(text: "Boil")])
        XCTAssertTrue(RecipeDiff(old: c, new: c).isEmpty)
        XCTAssertEqual(RecipeDiff(old: c, new: c).summary, "No changes")
    }
}

@MainActor
final class VersioningTests: XCTestCase {
    func testCommitAndRestore() throws {
        let container = try ModelContainer(for: Recipe.self, RecipeVersion.self, PrepNote.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let recipe = Recipe(content: RecipeContent(title: "Bread"))
        ctx.insert(recipe)
        XCTAssertTrue(recipe.hasChanges(comparedTo: recipe.draft))   // no versions yet

        recipe.commitVersion(recipe.draft, label: "", note: "first")
        XCTAssertEqual(recipe.latestVersion?.number, 1)
        XCTAssertEqual(recipe.latestVersion?.label, "Version 1")
        XCTAssertFalse(recipe.hasChanges(comparedTo: recipe.draft))

        var d = recipe.draft
        d.steps.append(Step(text: "Knead"))
        recipe.draft = d
        XCTAssertTrue(recipe.hasChanges(comparedTo: recipe.draft))
        recipe.commitVersion(recipe.draft, label: "Kneaded", note: "")
        XCTAssertEqual(recipe.sortedVersions.map(\.number), [2, 1])

        recipe.draft = recipe.versions.first { $0.number == 1 }!.content   // restore v1
        XCTAssertTrue(recipe.draft.steps.isEmpty)
        XCTAssertEqual(recipe.versions.count, 2)                          // history untouched
    }

    func testContentDecodingToleratesMissingFields() throws {
        let data = #"{"title":"Old"}"#.data(using: .utf8)!
        let c = RecipeContent.decode(data)
        XCTAssertEqual(c.title, "Old"); XCTAssertEqual(c.servings, 4); XCTAssertTrue(c.ingredients.isEmpty)
    }
}
