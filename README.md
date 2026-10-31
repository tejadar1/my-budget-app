# Upside Budget

Smart money, together. A private iPhone budget app for the two of us, built on
[Actual Budget](https://github.com/actualbudget/actual) (MIT license).
Both of our bank accounts sync into one shared budget, so we can see where
the money goes each month and who spent it.

## How it works

This repo doesn't copy Actual's code. It pins one Actual commit in
`app.config`, and the build:

1. downloads that commit (`scripts/prepare.sh`)
2. applies our changes from `patches/` and our files from `overrides/`
3. names the app "Upside" and gives it our own bundle ID
4. builds the iPhone app on GitHub's Macs and uploads it to TestFlight
   (`.github/workflows/ios.yml`)

So we get Actual's features and updates, plus our own.

## Getting started

Follow [docs/SETUP.md](docs/SETUP.md) once (Apple keys, GitHub secrets,
the sync server and bank connections). Then: **Actions → Build iPhone app →
Run workflow**, and install from TestFlight.

## Two people, one budget

- Both of us use the same budget file on the same server, from our own phones.
- Each bank account is named with its owner, e.g. `Ron · Chase Checking`,
  `<Wife> · Amex`.
- Planned: a **Spending by person** report showing, for each category and
  month, how much each of us spent (see Roadmap).

## Roadmap

- [x] iPhone app built from Actual, renamed, auto-uploaded to TestFlight
- [ ] Spending by person report (category × month × who)
- [ ] Our own app icon (`overrides/packages/mobile-client/ios/App/App/Assets.xcassets/`)

## Updating Actual

Change `ACTUAL_REF` in `app.config` to a newer commit or release tag from
[Actual's repo](https://github.com/actualbudget/actual) and push. The `check`
job tells you right away if any of our patches no longer applies.

## Local build (optional, needs a Mac with Xcode)

```sh
scripts/prepare.sh
cd actual
corepack enable && yarn --immutable
yarn build:browser --skip-translations
yarn workspace mobile-client sync:ios
open packages/mobile-client/ios/App/App.xcworkspace
```
