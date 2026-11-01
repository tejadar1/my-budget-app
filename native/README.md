# Upside — native iPhone app

SwiftUI rewrite of Upside: no server, banks through SimpleFIN directly,
and (next) iCloud sharing between both phones.

- `project.yml` — XcodeGen spec (the `.xcodeproj` is generated, not committed)
- `Upside/Model` — data types, `BudgetStore` (all the budget math), demo data
- `Upside/Services` — SimpleFIN client, bank sync and auto-categorizing
- `Upside/Features` — Budget, Accounts, Settings, setup screens
- `UpsideTests` — unit tests for the budget math

CI (`.github/workflows/native.yml`) runs the tests, builds for the iPhone
simulator and screenshots every screen in light and dark mode to the
`previews-native` branch. Launch arguments used there:
`-demo` (sample data), `-tab budget|accounts|settings`,
`-open category:<id> | review | trip:<id> | limits | account:<id>`.

Local build (Mac): `brew install xcodegen && cd native && xcodegen && open Upside.xcodeproj`
