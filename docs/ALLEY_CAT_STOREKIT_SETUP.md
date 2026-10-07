# Alley Cåt StoreKit setup

The current product design is a one-time Pro unlock, not a recurring subscription.
TestFlight/App Store uses verified StoreKit transactions; the full unsigned lane
keeps included Pro access through ALLEY_CAT_SIDELOAD_UNLOCKED.

## App Store Connect

Use the Alley Cåt app with bundle ID `com.nightvibes.alleycat`.
Under Monetization → In-App Purchases create a **Non-Consumable**:

- Reference name and localized display name: Alley Cåt Pro
- Product ID: `com.nightvibes.alleycat.pro` (must match exactly)
- Set your intended price, availability, description, and review screenshot.
- Family Sharing is optional; the local test configuration enables it.

The local .storekit file does not create products in App Store Connect.
Complete the Paid Apps agreement, tax and banking information under Business.
Resolve Missing Metadata and submit the first purchase alongside an app version
for review; attach the product in that version's In-App Purchases section.

Optional existing tip products are also **Non-Consumable** supporter tiers:
`com.nightvibes.alleycat.tip.10`, `.tip.25`, `.tip.50`, `.tip.100`.
Each tier can be bought once and restored; these are not repeatable consumable tips.
Configure each exact full product ID separately if you want the tip page enabled.

## TestFlight acceptance

Install the new StoreKit-enabled build. Earlier uploaded build 20261007180718
predates this repair and grants Pro automatically in its AppStoreSafe mode.
On the new build, open Settings → Alley Cãt Pro, verify Apple's localized price,
purchase in TestFlight's sandbox (no real charge), restart and restore purchases.
Confirm paid alternate icons unlock; verify cancellation and revoked transactions
leave the entitlement locked. Product propagation can take time. Never fabricate
a product response or show an invented purchasable price when Apple returns none.

A native archive, product configuration, sandbox transaction, and physical-device
entitlement restoration are separate checks. Recurring subscriptions need a chosen
billing period and price, an auto-renewable product group, expiration handling,
and corresponding purchase UI; they must not be configured as this one-time ID.
