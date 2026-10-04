# KlenPOS: App Store Connect answers

Companion to `play-data-safety-answers.md`. Keep these in step with `ios/Runner/PrivacyInfo.xcprivacy`.
Never put real credentials in this file.

## URLs

| Field | Value |
|---|---|
| Privacy Policy URL | https://klenpos-prod.vercel.app/privacy |
| Terms of Use (optional) | https://klenpos-prod.vercel.app/terms |
| Support URL | [fill in: a page or mailto that reaches itsreddygona@gmail.com] |

Account deletion is in the app (owners: More, Account, Delete account; employees: Profile, Delete account), which satisfies guideline 5.1.1(v). Apple does not ask for a web deletion URL.

## App Privacy ("nutrition label")

Tracking: **No.** The app does not track (no ATT prompt, no advertising ID, no data sold or shared with data brokers).

Data collected, **all linked to the user, none used for tracking**:

| Apple data type | Why | Purpose |
|---|---|---|
| Name | Account and staff records | App functionality |
| Phone Number | Sign-in identifier, customer phone numbers stores enter | App functionality |
| Email Address (optional field) | Profile contact | App functionality |
| Other User Content | Customer names, orders, notes entered by the store | App functionality |
| User ID | Opaque internal ID attached to analytics and crash reports | App functionality, Analytics |
| Device ID | Firebase installation ID | Analytics |
| Product Interaction | App events such as login, order placed, payment recorded | Analytics |
| Crash Data | Firebase Crashlytics | App functionality |
| Performance Data | Firebase Crashlytics diagnostics | App functionality |

Not collected: location, contacts, photos, camera, microphone, health, financial or card details (payments are only recorded as entered by the store), browsing or search history, advertising data.

If a later build adds push notifications, also declare the push token under Device ID and add it to `PrivacyInfo.xcprivacy`.

## Export compliance

`ITSAppUsesNonExemptEncryption` is set to `false` in `Info.plist`: the app only uses HTTPS and the encryption built into iOS. Answer **No** if App Store Connect still asks.

## Age rating

No user-generated content shared between users, no web access to arbitrary sites, no gambling, no mature content. Expect **4+**.

## App Review Information

App Store Connect has one Sign-in username/password pair. Put the **owner** login there. Put the **staff** login, and the notes below, in the Notes field. Apple's own message asks for each account type in Notes.

```
KlenPOS is a point-of-sale and order-management tool for laundry businesses. There is no public sign-up: we onboard each store owner personally by phone call and create their account. Owners then add their own staff inside the app.

Demo accounts (production, sample data):
- Owner: sign in with the username and password in the fields above.
- Staff (employee): phone <STAFF PHONE>, password <STAFF PASSWORD>

Main flows to try: sign in, create an order (Orders tab, plus button), record a payment, open the dashboard (owner), open the Staff and Services screens (owner).

Account deletion: owners go to More, Account, Delete account (type DELETE to confirm). Employees go to Profile, Delete account. Deleting starts a 90-day grace period; signing in again during that time shows a Restore screen. The demo organization is protected: its deletion requests are recorded but never executed, and the account is restored automatically after 24 hours, so please feel free to try the flow.

External services: our own backend API (Next.js on Vercel) with a PostgreSQL database on Neon; Google Firebase (Crashlytics, Analytics, Remote Config). There is no payment processor and no in-app purchase: store subscriptions are agreed and invoiced directly with each business outside the app, and the Subscription screen only shows billing history.

Regions: the app behaves the same everywhere it is available and is currently intended for businesses in India.
```

## Before each upload

1. Bump the build number in `pubspec.yaml` (`1.0.0+N`): App Store Connect rejects a repeated build number.
2. Production backend deployed with the deletion endpoints (`POST /api/v1/account/deletion` must not return 404).
3. Demo owner and staff logins work against production.
4. Screenshots show the app in use, not the splash or login screen.
