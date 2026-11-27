# Andy M1 Evidence: Whole-Basket Checkout Preflight

Evidence date: 2026-11-26 (America/New_York)
Branch: `p3/andy-preflight` (stacked on `p3/andy-contract`)
Base: `Sihao` @ `5685898` (same tree as `main` @ `9d52e18`)
Final merge SHA: record after integration into the team default branch

## Honest status

- **Implemented and tested:** the shared domain contract and ports, the
  deterministic preflight engine, the `AppState` request builder, the
  synthetic scenario fixture (including M0-WG trial baskets `WG-S1` and
  `WG-S2`), and 75 new engine tests.
- **Not yet user-visible:** Sihao's presentation layer still renders its own
  presentation fixtures. M1 becomes visible once the production adapter maps
  `PreflightReport` into `WolfGuardReportViewData` (Sihao's handoff step 1).
  Until that merges, the milestone is **not done** under plan Section 4, and
  no screenshot or clip is claimed here.
- The engine reads only application-managed allowances and supplied catalog
  evidence. It does not query an eWIC account and does not guarantee checkout
  acceptance.

## Owned files

| Path | Purpose |
| --- | --- |
| `Project2/lib/features/wolfguard/domain/wolfguard_models.dart` | Shared immutable contract (Section 6), including the M2/M3 value types |
| `Project2/lib/features/wolfguard/domain/wolfguard_ports.dart` | `PreflightAnalyzer`, `FixPlanner`, `FixPlanApplier`, `CandidateProvider` |
| `Project2/lib/features/wolfguard/engine/checkout_preflight_engine.dart` | `CheckoutPreflightEngine` |
| `Project2/lib/features/wolfguard/engine/preflight_rules.dart` | Category, package, and issue-wording rules |
| `Project2/lib/features/wolfguard/engine/preflight_request_builder.dart` | `AppState` basket/balances → `PreflightRequest`; APL record → evidence |
| `Project2/test/features/wolfguard/engine/` | 75 tests plus support builders and scenario loader |
| `Project2/test/fixtures/wolfguard_scenarios.json` | Synthetic scenarios and M0-WG oracles |

The domain and engine layers do not import Flutter or Firebase. The only
inherited import is `WicCategories` (pure Dart). No inherited file was edited.

## Contract decisions (also in PR #2)

1. `BenefitCategorySnapshot.used` counts units consumed **outside** the
   request. The inherited `AppState.used` also includes basket units, so the
   builder subtracts them. Remaining allowance is `allowed - used`.
2. `PreflightReport` derives its totals from its lines, so a report with
   inconsistent counts cannot be built.
3. `readyForHandoff` is false for an empty basket; `readinessPercent()` is
   null for an empty basket.
4. `PreflightRequest.fingerprint` hashes lines, evidence, and allowances
   (excluding `evaluatedAt`). Hash arithmetic stays below 2^53, so the result
   is identical on the Dart VM and on the web.
5. `LinePreflightResult.notes` carries non-blocking context, for example
   "prototype-uncapped".
6. A quantity that is zero, negative, or unreadable counts as one unknown unit,
   so it cannot drop out of the totals.

## Rules and evidence

| Acceptance | Engine behavior | Test file |
| --- | --- | --- |
| FR-1 every unit in exactly one outcome | Per-line `accountedUnits`; report sums lines | `preflight_invariants_test.dart` (500 seeded baskets) |
| FR-1 deterministic, non-mutating | No clock or state; immutable request; equal requests give equal reports | `preflight_invariants_test.dart`, `wolfguard_contract_test.dart` |
| FR-1 duplicate-UPC covered/PAID lines stay distinct | Line keys `index:upc:category` | `checkout_preflight_allocation_test.dart`, `preflight_request_builder_test.dart` |
| FR-1 spelling variants share one category | `WicCategories.canonical` on basket, evidence, and allowance keys | `checkout_preflight_allocation_test.dart` |
| FR-2 missing APL evidence never covered | Unknown, `insufficientEvidence` | `checkout_preflight_evidence_test.dart` |
| FR-2 PAID line without original category | Unknown unless exact-UPC evidence names exactly one category | `checkout_preflight_allocation_test.dart` |
| FR-2 stale/contradictory evidence named | `staleEvidence` / `contradictoryEvidence` issues | `checkout_preflight_evidence_test.dart` |
| FR-2 zero is not missing | `allowed: 0` blocks; `used: 0` is valid | `checkout_preflight_allocation_test.dart` |
| FR-2 package mismatch only with explicit, same-unit evidence | Same supported unit and different size → blocked; different/unsupported unit or missing size → unknown; float noise matches | `checkout_preflight_evidence_test.dart` |
| FR-3 allocation in stable order | Covered up to `allowed - used`, the rest blocked | `checkout_preflight_allocation_test.dart` |
| FR-3 excess never silently self-paid | Only `PAID` lines are self-pay | `checkout_preflight_allocation_test.dart` |
| FR-3 prototype-uncapped labeled | Note: "not an official unlimited benefit" | `checkout_preflight_allocation_test.dart` |
| FR-3 used/allowed inconsistency | Unknown, never a negative balance | `checkout_preflight_evidence_test.dart`, `preflight_request_builder_test.dart` |
| Section 9.2 raw quantity decimal/string/missing | Builder emits 0 → one unknown unit | `preflight_request_builder_test.dart` |
| NFR-1 100 lines < 100 ms | Measured after warm-up | `preflight_invariants_test.dart` |

Conservative allocation rule: a line with unknown evidence still holds its
share of a capped allowance, because the register might count it, but its
units stay unknown. Later lines therefore cannot claim coverage that the
unknown line might use.

## Verification

Run from `Project2` with Flutter 3.47.2 / Dart 3.13.2 on macOS (arm64).

| Gate | Command | Result |
| --- | --- | --- |
| M1 engine tests | `flutter test --no-pub test/features/wolfguard/engine` | **75/75 passed** |
| Entire inherited + delta suite | `flutter test --no-pub --coverage --concurrency=1` | **532/532 passed** (Sihao baseline 457 + Andy 75), 0 skipped |
| Strict analyzer | `flutter analyze --no-pub --fatal-infos --fatal-warnings` | **0 issues** |
| Formatter | `dart format --output=none --set-exit-if-changed lib test tool` | **98 files, 0 changed** |
| Release web build | `flutter build web --release --no-pub` | **PASS**, `build/web` produced |
| Line coverage, whole app | `coverage/lcov.info` | **92.12%**, 3,530/3,832 |
| Line coverage, M1 files | same report | **87.11%**, 561/644 (engine 182/184, rules 180/188, builder 48/51, models 151/221) |

Most uncovered model lines are equality members of the M2/M3 value types,
which Wenbo's and Feiyang's tests will exercise.

### Mutation check

Three engine rules were broken deliberately, the engine tests were run, and
the file was restored:

| Mutation | Failing tests |
| --- | ---: |
| Missing APL evidence treated as eligible | 8 |
| Unknown lines stop holding allowance | 1 |
| `used > allowed` accepted as consistent | 3 |

### Additional repository gates (unchanged by M1)

| Gate | Result |
| --- | --- |
| `Project2/scripts` Python (with `requirements-apl.txt`) | 13/13 passed |
| `Project2/scripts` Node | 16/16 passed |
| Firebase configuration consistency | PASS (`wolfbyte-proj1`) |
| `.github/scripts` Python | 11/11 passed |
| `.github/scripts` Node | 5/5 passed |
| Inherited M0 (`Project2_Work/M0`) | 13/13 passed |
| M0-WG instrument tests | 42/42 passed |
| M0-WG passing / failing fixtures | exit 0 / exit 1 |

## Commits

1. `aad6ae7` shared domain contract
2. `0a674c9` ports
3. `ea84582` category, package, and issue rules
4. `da0d4b8` whole-basket preflight engine
5. `1a6265e` allocation and PAID tests
6. `94d4f30` evidence and package tests
7. `2eb1c24` `AppState` request builder
8. `00277b6` request builder tests
9. `efe0c10` seeded invariant tests
10. `3a3c8c1` contract value tests
11. `54d071f` synthetic scenario fixture with M0-WG trial baskets
12. `4361332` scenario and oracle tests

## Integration handoff

- **Sihao (M4):** in the production `WolfGuardLiveReportSource`, call
  `PreflightRequestBuilder.fromAppState(basket: appState.basket, balances:
  appState.balances, evaluatedAt: now, evidenceByUpc: …)`, then
  `const CheckoutPreflightEngine().analyze(request)`. Map each
  `LinePreflightResult` to `WolfGuardLineViewData` by `lineKey`; the product
  name is on the matching `request.lines` entry. Evidence comes from
  `PreflightRequestBuilder.evidenceFromAplRecord(await apl.findByUpc(upc))`.
  The rehearsal can load `WG-S1`/`WG-S2` content as `PreflightRequest`s so it
  uses the same engine as the real basket.
- **Wenbo (M2):** use `report.requestFingerprint` as
  `FixPlan.sourceFingerprint`, and build the projected report by calling the
  analyzer on a projected `PreflightRequest`. Because `used` already excludes
  basket units, a projection only edits `lines`. Key actions on line `status`,
  not issue code: a `selfPay` line carries an `allowanceExceeded` issue that
  explains it, but needs no action.
- **Feiyang (M3):** `ReplacementCandidate` and `CandidateProvider` are in the
  shared domain files. Use `PreflightCategories.benefitCategory` for the
  blank/`PAID`/`UNKNOWN` rule.
