# WolfGuard 60-Second Offline Demo

Owner: Sihao  
Mode: deterministic synthetic rehearsal  
Entry: open the inherited Basket screen, then select the shield icon whose
tooltip is `Try WolfGuard rehearsal`

## What this proves

- WolfGuard is reachable from the inherited product without setup.
- Covered, self-paid, blocked, and unknown outcomes are visible together.
- A package mismatch names the selected and permitted synthetic sizes.
- Repair is previewed before apply and updates the rehearsal counts.
- Returning to Basket leaves the shopper's real basket and balances unchanged.

This path is explicitly labeled `Synthetic sample — not live benefits`. It
uses the production M1 analyzer, M2 planner/applier, and M4 mapper/widgets. It
does not prove that the pending M3 provider is integrated and must not be
presented as participant M0 evidence.

## Timed operator script

| Time | Operator action | Visible evidence / narration |
| ---: | --- | --- |
| 0–6 s | On Basket, point to the existing item, then select the shield icon. | “This begins inside the inherited WolfBite basket.” |
| 6–13 s | Pause on the rehearsal banner and summary. | Read the synthetic warning; show `Covered 1`, `Self-paid 1`, `Blocked 1`, and `Unknown 1`. |
| 13–25 s | Select `Review with WolfGuard`; scroll to `Synthetic blocked cereal`. | Show the package-size mismatch, including 24 oz selected versus 18 oz benefit evidence. |
| 25–36 s | Select `Preview safe repair`. | Show `Before` and `Projected after`; without M3, the shared planner conservatively keeps both unsafe lines self-paid. |
| 36–44 s | Select `Apply repairs`. | The rehearsal recalculates to `Covered 1`, `Self-paid 3`, `Blocked 0`, `Unknown 0`. |
| 44–52 s | Point to `Checkout preflight reviewed`. | “Unknown evidence was kept conservative rather than guessed as covered.” |
| 52–60 s | Use Back to return to Basket. | Show the same inherited basket item and quantity. “The rehearsal never touched live shopper state.” |

Do not spend demo time explaining implementation classes. The audience should
see the before/after counts, package evidence, explicit confirmation, and state
isolation.

## Pre-demo check

From `Project2/`:

```sh
flutter test --no-pub \
  test/features/wolfguard/presentation/wolfguard_basket_screen_test.dart \
  test/features/wolfguard/presentation/wolfguard_domain_rehearsal_driver_test.dart
```

Expected result: 12 tests pass. The production-route rehearsal test completes
the repair, returns to the inherited Basket, and compares both basket contents
and balances with their pre-rehearsal snapshots.

For a device-equipped machine, run:

```sh
flutter test --no-pub integration_test/wolfguard_demo_test.dart -d DEVICE_ID
```

The device wrapper includes 21 verified source scenarios: two full journey
tests, seven optional-seam tests, six production-basket tests, and six
shared-domain rehearsal tests. It uses fake or synthetic evidence and does not
contact production services.

## Recovery during a tutor demo

1. If the normal signed-in path is unavailable, use the shield entry above.
2. If the app cannot launch on the available device, run the integration test
   on a configured Flutter device.
3. If neither environment is available, play the recorded walkthrough while
   narrating the same timestamps.

The operator must still keep the installed app available in case the tutor asks
to repeat the live rehearsal.

## Recording checklist

- Record at 1080p or higher with pointer/touch indicators visible.
- Keep the synthetic warning in frame before showing any status counts.
- Capture the package-size evidence and the before/after repair preview.
- End on the unchanged inherited Basket screen.
- Do not show credentials, participant data, card numbers, or PINs.
- Store the final clip URL in the merged README; do not claim a URL before it
  exists.
