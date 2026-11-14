# Releasing Upside

- **Versions:** each feature bundle gets the next version (0.29, 0.30…); a fix-only build adds a third digit (0.29.1). Build numbers stay the automatic UTC timestamp.
- **Bundles:** changes collect under "## Next" in RELEASE_NOTES.md, committed with `[skip ci]`.
- **Before shipping:** a check run (push without `[skip ci]`) runs the tests and screenshots every screen; review them.
- **Shipping:** on "build", set `MARKETING_VERSION` in project.yml, rename the top notes heading to `## <version>: <theme>`, commit with `[ship-native]`.
- **Cadence:** a bundle every 2–4 days; urgent fixes as .1 builds.
- **TestFlight:** builds expire after 90 days; expire old versions with the TestFlight expire workflow.

## Roadmap
- 0.29 Settle in: sharing verified end to end, first-week fixes, split purchases in the Transactions filter
- 0.30 Look ahead: checking forecast to month end, net worth over time (home value and mortgage)
- 0.31 Plan, adjust, look back: original plan vs adjustments, rebalance, recap against the plan (done)
- 0.32 Save first, plan realistically: extra income waits, payday reminders, step-down limits (done)
- 0.33 Debt plan: card interest rates, which card first, interest saved
- 0.34 At a glance: widgets, Siri
- 0.35 Year-end: year summary, CSV export, 401(k) per paycheck, notes and tags
- 1.0 Ready: two weeks of shared use without data problems, then App Store prep if wanted
