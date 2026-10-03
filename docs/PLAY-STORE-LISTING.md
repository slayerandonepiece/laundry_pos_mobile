# KlenPOS: Google Play default store listing (prod)

Where: Play Console > KlenPOS > Grow users > Store presence > Main store listing (default language English (India) – en-IN).
Copy each field below as-is. Limits are Play's.

## App details

| Field | Value | Limit |
|---|---|---|
| App name | `KlenPOS: Laundry POS` | 30 (20 used) |
| Short description | `Laundry & dry-cleaning POS: orders, payments, expenses and staff, even offline.` | 80 (79 used) |

### Full description (limit 4000)

```
KlenPOS is the point-of-sale app for laundry and dry-cleaning shops. Take orders at the counter, track every order from pickup to delivery, record payments, and see how your business is doing, from your phone.

KlenPOS is for businesses onboarded by the KlenPOS team. Accounts are created for you, and your login details are shared when you join. To get started, contact itsreddygona@gmail.com.

WHAT YOU CAN DO

• Orders from counter to delivery: create orders, add services, and move each one through Pending, In progress, Ready and Delivered. Search by order number, customer or phone, and filter by status, payment or due date.

• Payments and dues: record what was collected and what is still to collect, with the payment methods your store accepts. See collected vs. to-collect at a glance.

• Invoices: share a clean invoice with your customer.

• Sales dashboard: today's sales, this month's sales, sales by date and by service, with 7-day, monthly and custom date ranges. Tap Open, Delivered or Due today to jump straight to those orders.

• Expenses: record and track your expenses and compare them with what you collected.

• Staff and outlets: add employees, assign them to outlets, and switch between outlets or see all of them combined.

• Works offline: keep taking orders when the connection drops. Everything syncs automatically when you are back online, and anything that could not be sent is shown so you can retry it.

• Your store, your settings: manage your services and prices, payment methods and store profile in one place.

BUILT FOR THE COUNTER

Fast screens, large touch targets and a simple layout so your team can work quickly during a rush.

PRIVACY

KlenPOS records the sales information your store enters. It does not process card or UPI payments and does not collect your location, contacts, photos or files. Read our Privacy Policy at https://klenpos-prod.vercel.app/privacy.

Need help or want to start using KlenPOS? Email itsreddygona@gmail.com.
```

## Graphics

| Asset | File in repo | Spec | Status |
|---|---|---|---|
| App icon | `assets/icons/klenpos_appicon_playstore_512.png` | 512 × 512 PNG, up to 1 MB | present |
| Feature graphic | `assets/branding/klenpos_feature_graphic_1024x500.png` | 1024 × 500 PNG/JPEG, no alpha | present |
| Phone screenshots (2 to 8) | `marketing/klenpos-store-screenshots/google-play/01…06-*.png` | 1440 × 2880, 24-bit PNG, no alpha | present, 6 files |
| 7-inch and 10-inch tablet screenshots | none | optional | skip for first release |
| Promo video (YouTube URL) | none | optional | skip |

Screenshot order to upload: 01-dashboard, 02-orders, 05-store-controls, 04-insights, 06-outlets. Leave out `03-klenpos.png`: it is only the splash screen and does not show the product. (Play needs at least 2; 5 is plenty.) The screenshots use demo data (store "ABC").

## Store settings and contact

| Field | Value |
|---|---|
| App or game | App |
| Category | Business (tags: Business, Point of sale if offered) |
| Free or paid | Free (cannot be changed later) |
| Contact email | itsreddygona@gmail.com |
| Website | https://klenpos-prod.vercel.app (optional) |
| Phone | optional, leave blank unless you want it public |
| Privacy policy URL | https://klenpos-prod.vercel.app/privacy (must be live: deploy the web app first) |
| Countries / regions | India only (Production > Countries/regions) |

## Before you save
- The privacy policy URL must open publicly. Deploy `laundry_pos` (`feat/legal-pages`) to prod first.
- Do not add reviews, ratings, rankings or "#1" claims, and keep emoji and ALL CAPS out of the name and short description (Play metadata policy).
- Screenshots show demo data only. Keep real customer names and phone numbers out of any new screenshots.
