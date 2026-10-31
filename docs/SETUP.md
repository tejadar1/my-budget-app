# One-time setup

You do these steps once. After that, every build is one click (or automatic
when the app changes) and lands in TestFlight on your iPhone.

## 1. Create the app in App Store Connect

1. Go to [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
   and add an **App ID** with the bundle ID from `app.config`
   (`com.tejadar1.upside`). No extra capabilities are needed.
2. Go to [App Store Connect → Apps](https://appstoreconnect.apple.com/apps),
   click **+ → New App**, platform iOS, name **Upside Budget**,
   and pick that bundle ID. The SKU can be anything, like `upside`.

The app stays private: it's only installable through TestFlight by people
you invite. Nothing is submitted to the public App Store.

## 2. Create an App Store Connect API key

App Store Connect → **Users and Access → Integrations → App Store Connect API
→ Team Keys → +**. Give it the **Admin** role (lower roles can't create the
signing profiles). Note:

- the **Issuer ID** (shown above the key list)
- the **Key ID** (in the key's row)
- the **.p8 file** — downloadable only once, keep it safe

## 3. Find your Team ID

[developer.apple.com → Membership details](https://developer.apple.com/account#MembershipDetailsCard) → **Team ID**.

## 4. Add the secrets to GitHub

In this repo: **Settings → Secrets and variables → Actions → New repository
secret**. Add:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Team ID from step 3 |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from step 2 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID from step 2 |
| `APP_STORE_CONNECT_API_KEY_P8` | Entire contents of the .p8 file, including the `BEGIN`/`END` lines |

Optional, only if a build fails at signing:

| Secret | Value |
| --- | --- |
| `APPLE_SIGNING_P12_BASE64` | An "Apple Distribution" certificate exported as .p12, base64-encoded (`base64 -i cert.p12`) |
| `APPLE_SIGNING_P12_PASSWORD` | The password you set when exporting it |

## 5. Build

**Actions → Build iPhone app → Run workflow.** A build takes roughly
20–40 minutes. When it's green, open **TestFlight** on your iPhone (install
it from the App Store if needed) and install **Upside**. To give your wife
the app too, add her under App Store Connect → your app → TestFlight →
Internal Testing.

> GitHub's free plan for private repos includes 2,000 Actions minutes a month,
> and macOS minutes count 10×, so that's roughly 5 iPhone builds a month for free.

## 6. The server (for syncing and bank connections)

The app keeps your budget on the phone. To share one budget between both of
your phones and pull bank transactions, it needs an Actual server:

1. Create an Actual server on [PikaPods](https://www.pikapods.com/pods?run=actual) (~$2/month).
2. Open the app and, when it asks for a server, enter your PikaPods URL.
3. For bank sync in the US, sign up for [SimpleFIN Bridge](https://www.simplefin.org/)
   (~$15/year), link both of your banks there, and paste the setup token into
   Actual's bank sync settings when linking an account.
