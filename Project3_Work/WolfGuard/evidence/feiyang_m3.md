# Feiyang M3 Evidence: Evidence-Safe Replacement Search

Evidence date: 2026-11-27 (America/New_York)
Branch: `p3/feiyang-catalog`
Base: `Sihao` @ `08c00e6` (contains merged M1 PR #2/#3 and M2 PR #4)
Final merge SHA: record after integration into the team default branch

## Honest status

- **Implemented and tested:** a read-only eligible-replacement query on the
  inherited `AplService`, the concrete `AplCandidateProvider` behind the
  frozen `CandidateProvider` port, and 27 new reported Dart tests.
- **Proven end to end in tests:** the concrete provider, backed by fake
  Firestore, drives Sihao's production `WolfGuardBasketScreen` through
  candidate search → preview → cancel → preview → apply, plus Retry after a
  catalog failure and the honest empty state.
- **Not yet visible in the running app:** the `/basket` route still builds
  `WolfGuardBasketScreen()` without a provider. `app_router.dart` belongs to
  Sihao (plan Section 5.5), so the one-line wiring is a requested diff below,
  not an edit on this branch. M3 counts as **done** under plan Section 4 only
  after that diff merges and a screenshot or clip is recorded.
- Candidates are same-category APL listings only. WolfGuard does not claim a
  verified package match, an official eWIC balance, or checkout acceptance.

## Owned files

| Path | Purpose |
| --- | --- |
| `Project2/lib/services/apl_service.dart` | Added `eligibleReplacements` (read-only). No existing method changed. |
| `Project2/lib/features/wolfguard/catalog/apl_candidate_provider.dart` | `AplCandidateProvider implements CandidateProvider` |
| `Project2/test/features/wolfguard/catalog/apl_replacement_query_test.dart` | 9 service tests on fake Firestore |
| `Project2/test/features/wolfguard/catalog/apl_candidate_provider_test.dart` | 15 provider tests, including 2 against the real M2 planner |
| `Project2/test/features/wolfguard/catalog/apl_candidate_basket_flow_test.dart` | 3 widget tests through the production basket composition |

No other inherited file and no other owner's path was edited. No dependency
was added.

## Design decisions

1. **Query by category code, then re-check in Dart.** The NC APL `category`
   text has spelling variants (code 51 is both `MILK - WHOLE` and
   `MILK-WHOLE`), but `categoryCode` is consistent. The query reads by code
   when the canonical name has one, and by the canonical label as well, so a
   record without a code is not missed. Every record is then re-checked:
   `eligible` must be Boolean `true`, and `WicCategories.canonical(category,
   code:)` must equal the line's original category. A label that matches but
   whose code means another category is rejected.
2. **The document ID is the UPC.** Results carry the Firestore document ID
   exactly (leading zeros preserved). A record whose stored `upc` field
   disagrees with its ID is contradictory evidence and is skipped.
3. **Original category.** A `PAID` overflow line is searched in its
   `originalBenefitCategory`. A blank, `UNKNOWN`, or `PAID` category, or a
   `PAID` line without a recorded origin, returns an empty list **without
   querying**.
4. **No package size from the APL.** `verifiedPackageSize` is always null.
   `unitOfMeasure` is the APL accounting unit, not a verified package size
   (plan Section 3.5), so it is returned as stored and never converted.
5. **Honest label.** Every candidate carries
   `Imported NC APL: same-category candidate; package size not verified`.
6. **Defense in depth.** The provider repeats the eligibility, category,
   blank-UPC, self-exclusion, dedupe, and `max` checks even though the
   service already applies them, so a future change to the service cannot
   silently weaken the port contract. M2's planner then applies its own
   safety rules (exhausted allowance, freshness, package mismatch).
7. **Errors propagate.** `FirebaseException` reaches the candidate sheet,
   which shows "Replacement evidence is temporarily unavailable" and
   **Retry alternatives**. Nothing is cached as a fabricated result.

## Acceptance coverage (FR-6 and Section 6.6)

| Acceptance | Test |
| --- | --- |
| Exact canonical original category; spelling variants via code | `apl_replacement_query_test`: spelling variants; code contradicts label |
| PAID line searches its origin; blank/UNKNOWN/PAID returns empty, no query | `apl_candidate_provider_test`: PAID overflow; 4 contract-guard cases |
| Current UPC excluded | query: excludes current UPC; provider: re-check test; mutation-tested |
| Duplicate UPCs removed, first kept | query: dedupe across both queries; provider: keep-first dedupe |
| Only `eligible == true` | query: Boolean-true only (`false`, `'true'`, missing rejected); provider re-check |
| Document-ID UPC preserved and usable by the swap | query: leading zeros; flow test: basket ends with UPC `000222` |
| Missing package evidence stays null | query: accounting unit kept, no size invented; provider: `verifiedPackageSize` null |
| Empty says "No evidence-safe alternatives found" | flow test: honest empty state |
| Firestore failure offers Retry; basket unchanged | provider: error then recovery; flow test: Retry path |
| Read-only; no mutation before confirm | query + provider: `FakeFirebaseFirestore.dump()` unchanged; flow test: basket unchanged after lookup, preview, and Cancel |
| Exhausted allowance gets no same-category swap (FR-4) | provider + real M2 planner test |
| Ineligible product gets a replacement with the exact UPC | provider + real M2 planner test |

Mutation check (run locally, not committed): removing self-exclusion, the
eligibility re-check, the service category re-check, or the
contradictory-UPC check, or changing keep-first dedupe to keep-last, each
makes at least one M3 test fail.

## Verification (WSL Ubuntu 24.04, on branch working tree over `08c00e6`)

Toolchain: Flutter 3.47.2, Dart 3.13.2, Node v22.23.5, Python 3.12
(system 3.12.3; scripts gate in a 3.12.16 env with pinned `openpyxl==3.1.5`,
as in CI).

| Gate | Result |
| --- | --- |
| `flutter pub get --enforce-lockfile` | Pass |
| `dart format --output=none --set-exit-if-changed lib test tool` | Pass, 0 changed |
| `flutter analyze --no-pub --fatal-infos --fatal-warnings` | No issues |
| `flutter test --no-pub --coverage --concurrency=1` | **667 passed**, 0 failed, 0 skipped (640 before M3 + 27 M3) |
| Coverage (`coverage/lcov.info`) | 4108 / 4419 lines = 92.96% |
| `flutter build web --release --no-pub` | Pass |
| `Project2/scripts` Python tests | 13 passed |
| `verify_firebase_config.py` | Pass |
| `Project2/scripts` Node tests | 16 passed |
| `.github/scripts` Python tests | 11 passed |
| `.github/scripts` Node test | 5 passed |
| Inherited M0 (`Project2_Work/M0`) | 13 passed |
| M0-WG instrument tests | 42 passed |
| M0-WG passing fixture | Exit 0 |
| M0-WG failing fixture | Exit 1, as documented |

## Requested diff for Sihao (`Project2/lib/app_router.dart`)

The diff was applied in a throwaway worktree and verified there (format clean,
analyzer clean, 317 basket/E2E/WolfGuard tests passing). It is **not**
committed on this branch. One provider is cached per `AppState`, so route
rebuilds keep the same provider identity and do not reset the live
WolfGuard binding in `WolfGuardBasketScreen.didUpdateWidget`.

```diff
+import 'package:provider/provider.dart';
+
+import 'features/wolfguard/catalog/apl_candidate_provider.dart';
+import 'features/wolfguard/domain/wolfguard_ports.dart';
 import 'features/wolfguard/presentation/wolfguard_basket_screen.dart';
+import 'state/app_state.dart';
@@
         GoRoute(
           path: '/basket',
-          pageBuilder: (context, state) =>
-              const NoTransitionPage(child: WolfGuardBasketScreen()),
+          pageBuilder: (context, state) => NoTransitionPage(
+            child: WolfGuardBasketScreen(
+              candidateProvider: _wolfGuardCandidatesFor(
+                context.read<AppState>(),
+              ),
+            ),
+          ),
         ),
@@
+
+/// One M3 catalog provider per [AppState], so route rebuilds keep the same
+/// provider identity and do not reset the live WolfGuard binding.
+final Expando<CandidateProvider> _wolfGuardCandidates = Expando();
+
+CandidateProvider _wolfGuardCandidatesFor(AppState state) =>
+    _wolfGuardCandidates[state] ??= AplCandidateProvider(state.productCatalog);
```

## Remaining before M3 is done

1. Sihao approves the wiring commit `062cca9` in PR #5 (an ownership
   exception, since `app_router.dart` is Sihao-owned), or replaces it.
2. Record a screenshot or clip of a live candidate with its evidence label.
3. Merge to the team default branch and record the merge SHA here.

## Live Firestore check (2026-11-27)

Run against `wolfbyte-proj1` using the `scripts/verify_apl_access.cjs`
pattern: a temporary `@example.invalid` account with a random password (never
printed or stored), read-only REST `runQuery` calls, then account deletion
(confirmed deleted). Each query used `limit: 20`.

| Query (`&& eligible == true`) | Result |
| --- | --- |
| `categoryCode == "51"` (MILK - WHOLE) | 20 records (limit reached), label `MILK - WHOLE`, unit `GAL` |
| `category == "MILK - WHOLE"` | 20 records (limit reached), same products as the code query |
| `categoryCode == "02"` (CHEESE) | 20 records (limit reached), label `CHEESE`, unit `LB` |
| `categoryCode == "05"` (BREAKFAST CEREAL) | 20 records (limit reached), label `BREAKFAST CEREAL`, unit `OZ` |

- Security rules allow both M3 queries for a signed-in user; neither needed
  an extra index.
- Every returned record had Boolean `eligible: true` and a stored `upc` equal
  to its document ID, with leading zeros preserved (e.g. `0077890608500`).
- `unitOfMeasure` holds only unit labels, never an amount, which confirms that
  M3 must not derive a package size from it.
- Limits: the live sample showed no spelling variants (the code and label
  queries returned the same products), so variant handling is covered only by
  the fake-Firestore tests. This check called the REST API directly; an
  in-app screenshot or clip is still outstanding.
