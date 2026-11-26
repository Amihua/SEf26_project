# Sihao M4 + M0 Engineering Evidence

Evidence date: 2026-11-26 (America/New_York)  
Branch: `Sihao`  
Inherited fork point: `7b55bf1`  
Verified implementation parent: `33fae7c`
Final merge SHA: record after integration into the team default branch

## Honest status

Sihao's presentation, evaluation, inherited-screen integration seam, and
offline rehearsal work are implemented and tested. The current repository has
no Andy/Wenbo/Feiyang branches or shared WolfGuard domain, analyzer, planner,
applier, or catalog ports. Therefore:

- the UI is verified against injected fake ports and immutable view data;
- the full fake-port basket journey is verified offline;
- `BasketScreen` contains a verified optional WolfGuard panel and safe checkout
  handoff that preserves the inherited QR destination;
- the real app exposes a deterministic, clearly labeled offline rehearsal from
  the basket screen without Firebase or `AppState` dependencies;
- production injection from `AppState` and the shared WolfGuard implementation
  remains pending because those team-owned contracts are not present;
- the final production rehearsal driver cannot use the shared analyzer/planner
  until those contracts exist;
- M0-WG synthetic fixtures verify the instrument only; participant outcome
  claim is **Not Verified**.

Do not describe this branch alone as connected to the production WolfGuard
engine. Its inherited-screen seam and offline rehearsal are integrated; its
live production data adapter is not.

## Implemented M4 delta

| Capability | Evidence | Status |
| --- | --- | --- |
| Readiness states | Empty, loading, ready, attention, error; covered/self-paid/blocked/unknown counts; semantic status | Verified |
| Detailed report | Aggregate counts, stable line keys, item status, issues, evidence, next step, actions | Verified |
| Repair confirmation | Before/after preview, explicit apply, cancel no-op, repeated-tap lock, stale/unsupported/persistence errors | Verified |
| Candidate search | Loading, empty, unavailable/retry, exact UPC selection, same-category vs verified package evidence | Verified |
| Live recalculation | Listens to injected basket changes; rejects stale async results; detaches listener on dispose | Verified with fake source |
| Safe checkout | Reviewed basket proceeds; risky/error states require review; explicit limitation acknowledgement; cancel no-op | Verified with injected navigation callback |
| Rehearsal UI | Clearly labeled synthetic, isolated driver, report/repair/apply/retry flow | Verified with fake driver and built-in deterministic fixture |
| Full journey | Analyze → report → candidate → preview → apply → recalculate → checkout, plus cancel journey | Verified offline E2E |
| Inherited BasketScreen/QR wiring | Optional live panel and guarded checkout preserve the existing QR route; omitted integration preserves inherited behavior | Verified |
| Default app rehearsal entry | Basket-screen shield opens an isolated four-state synthetic scenario and two-action repair flow | Verified |
| Real AppState/domain adapter | Requires shared M1/M2/M3 contracts | Pending integration |
| Production shared-logic rehearsal driver | Requires shared analyzer/planner contracts | Pending integration |

Feature source is under `Project2/lib/features/wolfguard/presentation/`, with a
narrow optional composition seam in the inherited `basket_screen.dart`. E2E
coverage remains isolated under `Project2/test/e2e/` and
`Project2/integration_test/`. Inherited basket tile and state logic was not
restructured. No Andy engine/domain, Wenbo repair/state, or Feiyang
catalog/service file was edited.

## Flutter verification

Run from `Project2` with Flutter 3.47.2 / Dart 3.13.2.

| Gate | Command | Result |
| --- | --- | --- |
| Entire inherited + delta suite | `flutter test --no-pub` | **456/456 passed** |
| Count reconciliation | inherited 377 + new Sihao 79 | **456 total** |
| M4 presentation + E2E | `flutter test --no-pub test/features/wolfguard/presentation test/e2e/wolfguard_journey_test.dart` | **79/79 passed** |
| Device-smoke journey logic | `flutter test --no-pub test/e2e/wolfguard_journey_test.dart` | **2/2 passed** |
| Linux integration device launch | `flutter test --no-pub integration_test/wolfguard_demo_test.dart` | **Not run**: container lacks CMake; wrapper passes analyzer |
| Strict analyzer | `flutter analyze --no-pub --fatal-infos --fatal-warnings` | **0 issues** |
| Formatter | `dart format --output=none --set-exit-if-changed lib test integration_test` | **88 files, 0 changed** |
| Release web build | `flutter build web --release --no-pub` | **PASS**, `build/web` produced |

The new test count exceeds Sihao's minimum of 14. It does not replace the other
owners' test budgets or the team requirement to retest after merging M1–M3.

## M0-WG instrument

Implemented under `Project3_Work/WolfGuard/M0/`:

- strict paired-trial schema and failure-reason validator;
- 60-second, unsafe-coverage, unknown-acknowledgement, assistance, completion,
  80% success, and +20 percentage-point rules;
- text and JSON reports with exit codes 0/1/2;
- known passing and known failing synthetic fixtures;
- atomic incremental recorder with duplicate and provenance protection;
- reproducible participant protocol in `M0/README.md`.

### Instrument verification

| Gate | Result |
| --- | --- |
| M0-WG evaluator + recorder tests | **42/42 passed** |
| Known passing synthetic fixture | baseline 3/5 (60%), WolfGuard 4/5 (80%), +20pp, exit 0 |
| Known failing synthetic fixture | baseline 3/5 (60%), WolfGuard 3/5 (60%), +0pp, exit 1 |

Required current conclusion:

> M0-WG instrument verified with synthetic passing and failing fixtures;
> participant outcome claim Not Verified.

### Inherited M0 preservation

`python3 -m unittest discover -s Project2_Work/M0 -p 'test_*.py' -v`
completed with **13/13 passed**. This result remains separate from M0-WG.

## Additional repository gates

| Gate | Result |
| --- | --- |
| `.github/scripts` Python tests | **11/11 passed** |
| Project2 APL Python tests | **13/13 passed** using locked `openpyxl==3.1.5` from `requirements-apl.txt` in a `/tmp` target |
| Firebase configuration consistency | **PASS**; CLI, FlutterFire metadata, and five platform configs agree on `wolfbyte-proj1` |
| JavaScript tests | **Not run in this environment**: `node`, `nodejs`, and `npm` are unavailable |

The missing Node runtime is an environment limitation, not a passing result.
Run the repository JavaScript gates in CI or a Node-equipped clean clone before
final release.

## Auditable commit sequence

Each small capability was committed independently with ordinary project
messages:

1. `6eb93d3` — M0 scoring rules
2. `9e343cc` — M0 command-line reports and fixtures
3. `6ac4395` — readiness card
4. `d145c9a` — detailed report
5. `ad274f1` — repair preview
6. `96de54a` — isolated rehearsal screen
7. `e3a3a22` — safe checkout handoff
8. `b705fca` — basket review composition
9. `68c39a1` — live basket updates
10. `e04ac81` — checkout review coordination
11. `e39d331` — single-trial validation
12. `7510c93` — atomic trial recorder
13. `cc8a9bb` — candidate search UI
14. `61493f0` — candidate-to-repair connection
15. `48cb197` — complete journey E2E
16. `b0ee896` — M0 trial protocol
17. `d99df68` — formatter compliance
18. `2746c4f` — reject corrupted recording datasets
19. `a96cc60` — offline device demo smoke wrapper
20. `ca92689` — optional BasketScreen panel and guarded QR handoff
21. `5affaba` — deterministic four-state rehearsal fixture
22. `33fae7c` — default offline rehearsal entry from BasketScreen

At the verified parent, Sihao's delta contains 34 changed files, 5,719
insertions, and 7 deletions. Merge history, not this count alone, is the
authoritative grading evidence.

## Required integration handoff

After the other owners merge their frozen contracts and implementations:

1. Implement a narrow production adapter from `AppState` + the shared analyzer
   into `WolfGuardLiveReportSource` and immutable display snapshots.
2. Map Wenbo's plan and apply outcomes into the existing repair callbacks.
3. Map Feiyang's candidates into
   `WolfGuardReplacementCandidateViewData` without losing UPC or inventing
   package evidence.
4. Inject that adapter and the repair/catalog callbacks through the existing
   `WolfGuardBasketIntegration` seam in the app route/composition root.
5. Replace the presentation-only rehearsal driver with isolated synthetic
   domain fixtures using the same shared analyzer/planner as the real basket.
6. Add production-adapter tests, rerun all 456 current tests plus the other
   owners' tests, analyzer, formatter, web build, Python, JavaScript, inherited
   M0, and M0-WG gates.
7. Record the merged final SHA and replace every pending status above with
   evidence only after it actually passes.
