# Prompt — Phase 2: build the Flutter app

Copy everything below into a fresh session, working in the
`laundry_pos_mobile` repository. **Do not start until Phase 1 is done
and merged.**

---

You are building "MyShop", a Flutter app for a laundry POS. The backend
is the sibling repo `../laundry_pos` and its HTTP API was built in Phase
1 — read `../laundry_pos/.agents/MOBILE-API-TASKS.md` and
`../laundry_pos/.agents/CURRENT-STATE.md` to learn what actually shipped
and what was decided.

## Read first

1. `TASKS.md` — **your task list**, in order.
2. `docs/DESIGN-SPEC.md` — design tokens, metrics, navigation rules, and
   the full screen inventory.
3. The approved designs:
   **https://claude.ai/code/artifact/39d574e0-47c8-4b64-aa91-ae4a68d65b40**
   (shared by link). Pan around: **v1 on the left is the approved set;
   v2 on the far right is an unapproved exploration.** The sticky notes
   on the canvas are part of the spec.
   Offline fallback: `design/*.dc.html`, one plain-HTML file per screen.

## Non-negotiables

1. **Build v1 unless told otherwise.** v2 needs explicit sign-off.
2. **Lift exact values** from `docs/DESIGN-SPEC.md` — colours, radii,
   type sizes, control heights. Do not round them, and do not substitute
   Material defaults. The palette was contrast-audited; several
   plausible-looking greys fail WCAG AA. If you introduce a colour,
   verify it reaches 4.5:1 on every background it sits on.
3. **44px minimum touch target, 11px minimum UI type.** Text-only
   actions get padded hit areas.
4. **Role differences are structural.** An employee gets two tabs and
   owner features are *absent*, not disabled. But the client is never
   the authority — the API re-checks every request. A 403 is correct
   behaviour; render the blocked state.
5. **No partial payments anywhere.** Full amount or nothing. The backend
   supports partial; this app deliberately does not.
6. **Send an idempotency key with order creation** and reuse it on
   retry. A double-tap must never create two orders.
7. **Store the session token in the Keychain / Keystore**, never in
   SharedPreferences.
8. **Dates are already IST calendar dates** with no time component. Do
   not apply a second timezone conversion.
9. **No fake status bar and no fake keyboard** in any screen.

## Where to stop and ask

- The four open decisions in `TASKS.md` §F0.
- The prepaid-delivery gap in §F6: an order paid at checkout is settled
  but never reaches Collect payment, and Delivered is not settable by
  hand — so nothing moves it to Delivered and it never gets an invoice.
  Two reasonable fixes are described. **Ask; do not invent a third.**
- Any place the canvas and `docs/DESIGN-SPEC.md` disagree. The canvas
  wins, but flag it.

## Definition of done

- `flutter analyze` clean; widget tests for the shared components.
- An end-to-end run on a real device or emulator: log in → take a sale →
  collect payment → view the invoice.
- **Both roles exercised**, including that owner screens are unreachable
  as an employee and that a revoked session is handled on the next
  request rather than crashing.
- Checked at 375×812 and at 360×640 — several screens are tight.
- Invoice PDF shows `Rs.`, not a broken rupee glyph.

## Report back

What you built, what you ran, what passed, and explicitly what you could
not verify. Do not call the work complete if any screen or state was
skipped — list what is left instead.
