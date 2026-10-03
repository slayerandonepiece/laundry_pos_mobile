# Play Console: Data safety + related declarations (draft answers)

Derived from the app code (permissions: INTERNET, ACCESS_NETWORK_STATE only; Firebase Crashlytics, Analytics, Messaging, Remote Config). Re-check each answer against the live form.

## Data collection and security
- Does the app collect or share user data? **Yes**
- Is all data encrypted in transit? **Yes** (HTTPS only in stage/prod)
- Can users request data deletion? **Yes** (by email request; URL = your privacy policy page)

## Data types collected (none sold; none used for ads)

| Category | Type | Collected | Shared | Purpose | Optional |
| --- | --- | --- | --- | --- | --- |
| Personal info | Name | Yes | No | App functionality, account management | No |
| Personal info | Phone number | Yes | No | App functionality, account management | No |
| Personal info | Email address | Yes if used for login | No | Account management | No |
| Financial info | Purchase history / payment records (as entered by store) | Yes | No | App functionality | No |
| App activity | App interactions (analytics events) | Yes | No | Analytics | Yes |
| App info and performance | Crash logs, diagnostics | Yes | No | Analytics, app functionality | No |
| Device or other IDs | Firebase installation ID / FCM token | Yes | No | Analytics, app functionality (notifications) | No |

Notes:
- "Shared" is No: Firebase and Vercel/Neon act as service providers on our behalf, which Play does not count as sharing.
- Not collected: location, contacts, photos/files, camera, microphone, health data, card or bank credentials, SMS/call logs.
- Push notifications are not live yet. Keep the FCM token row only if the token is collected in the build you upload.

## Other declarations
- **App access:** restricted. Provide a demo owner login (and note it can be used to view all screens). Use a test store, never real customer data.
- **Ads:** No ads.
- **Target audience:** 18+ (not for children).
- **Content rating:** Utility / Business, no user-generated content, no violence, no gambling.
- **Financial features:** none. The app records payments only; it does not process payments or provide loans, banking or trading.
- **Government app:** No.
- **Account deletion:** account creation is by the developer only; state that deletion is by email request to itsreddygona@gmail.com and point to the privacy policy URL.
- **Category:** Business. **Contact:** itsreddygona@gmail.com, website [DOMAIN].
