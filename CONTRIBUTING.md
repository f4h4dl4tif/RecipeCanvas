# Contributing to RecipeCanvas

Thanks for helping! RecipeCanvas is free, open source (MIT) and has no paid tier. Every feature is for everyone.

## Getting started

1. Install Xcode (macOS 14 or later).
2. `./build.sh debug && open build/RecipeCanvas.app`
3. `swift test` before opening a pull request.

## Guidelines

- Keep pull requests focused: one feature or fix each.
- Add or update tests in `Tests/RecipeCanvasTests` for logic changes (parsing, diffing, versioning, timers).
- Saved data must keep loading. `RecipeContent` decodes missing fields with defaults, so new fields need a default too.
- Follow the existing SwiftUI style; match the terracotta `Theme` for any new UI.
- Pick something from [ROADMAP.md](ROADMAP.md), or open an issue to discuss bigger ideas first.

By contributing you agree that your contributions are licensed under the MIT License.
