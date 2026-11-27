# Sihao M4 + M0 Engineering Evidence

Evidence date: 2026-11-27 (America/New_York)
Branch: `Sihao`
Inherited fork point: `7b55bf1`
Shared M1/M2 integration base: `d2005dd`
Verified implementation parent: `0f92253`
Final merge SHA: record after integration into the team default branch

## Honest status

Sihao's presentation, evaluation, normal basket-route integration, and offline
rehearsal work are implemented and tested. Andy's M1 and Wenbo's M2 are merged
into this branch; Feiyang's M3 implementation is not present on any remote
branch. Therefore:

- the UI is verified against injected fake ports and immutable view data;
- the normal `/basket` route now reads exact-UPCs through inherited
  `AplService`, snapshots live `AppState`, runs M1, and renders the result;
- M2 preview and atomic apply are wired through Wenbo's planner/applier, with
  stale, unsupported, and persistence failures preserved;
- the real route blocks an unknown basket before QR and preserves inherited QR
  navigation after a confirmed repair;
- the default offline rehearsal uses the same M1 analyzer, M2 planner, M2
  applier, and presentation mapper as the live basket while keeping all state
  isolated;
- candidate mapping, stale-safe domain-candidate caching, replacement planning,
  and the optional production composition seam are ready; the normal route
  keeps them disabled until Feiyang's concrete `CandidateProvider` merges;
- the deterministic 60-second operator runbook is committed, but the required
  screenshot/clip has not yet been recorded;
- M0-WG synthetic fixtures verify the instrument only; participant outcome
  claim is **Not Verified**.

Describe this branch as production-integrated for M1 analysis, M2 repair, M4
readiness, safe handoff, and shared-logic rehearsal. Do not claim the M3
replacement path or the four-milestone team delta is complete yet.

## Implemented M4 delta

| Capability | Evidence | Status |
| --- | --- | --- |
| Readiness states | Empty, loading, ready, attention, error; covered/self-paid/blocked/unknown counts; semantic status | Verified |
| Detailed report | Aggregate counts, stable line keys, item status, issues, evidence, next step, actions | Verified |
| Repair confirmation | Before/after preview, explicit apply, cancel no-op, repeated-tap lock, stale/unsupported/persistence errors | Verified |
| Candidate search UI | Loading, empty, unavailable/retry, exact UPC selection, same-category vs exact package-match evidence | Verified through optional production seam; concrete M3 pending |
| Live recalculation | Exact-UPCs through inherited APL, immutable AppState snapshot, M1 analysis, stale async rejection, listener disposal | Verified on production route |
| Safe checkout | Unknown basket blocked before QR; repaired basket reaches inherited QR; acknowledgement and cancel remain available | Verified on production route |
| Rehearsal UI | Clearly labeled synthetic; real M1/M2 analyzer/planner/applier; report/preview/apply/retry; AppState isolation | Verified |
| Full M1/M2/M4 journey | Live AppState → report → preview → atomic apply → recalculate → inherited QR | Verified |
| Replacement journey | Domain candidate → UI selection → M2 preview → atomic apply → recalculate → QR | Verified through production wrapper with injected provider; concrete M3 pending |
| Inherited BasketScreen/QR wiring | Optional live panel and guarded checkout preserve the existing QR route; omitted integration preserves inherited behavior | Verified |
| Default app rehearsal entry | Basket-screen shield opens an isolated four-state scenario using shared M1/M2 logic | Verified |
| Real AppState/domain adapter | M1 report source, M2 repair coordinator, optional M3 callbacks | Verified; concrete M3 provider pending |
| Production shared-logic rehearsal driver | Same M1 analyzer, M2 planner/applier, and mapper as normal basket | Verified |

Feature source is under `Project2/lib/features/wolfguard/presentation/`, with a
narrow optional composition seam in inherited `basket_screen.dart` and one
route target change in `app_router.dart`. E2E coverage remains isolated under
`Project2/test/e2e/` and `Project2/integration_test/`. Inherited basket tile and
state logic was not restructured. The integration tranche did not edit Andy's
domain/engine, Wenbo's repair/AppState, or any Feiyang catalog/service file.

## Flutter verification

Run from `Project2` with Flutter 3.47.2 / Dart 3.13.2.

| Gate | Command | Result |
| --- | --- | --- |
| Entire inherited + merged delta suite | `flutter test --no-pub --coverage --concurrency=1` | **640/640 passed** |
| Team count reconciliation | inherited 377 + merged delta 263 | **640 total** |
| Sihao presentation + E2E | `flutter test --no-pub test/features/wolfguard/presentation test/e2e/wolfguard_journey_test.dart` | **116/116 passed** |
| Device-wrapper source scenarios | E2E + optional seam + production basket + domain rehearsal source files | **21/21 passed** |
| Linux integration device launch | `flutter test --no-pub integration_test/wolfguard_demo_test.dart` | **Not run**: container lacks CMake; wrapper includes the 21 verified source scenarios and passes analyzer |
| Flutter line coverage | generated `coverage/lcov.info` | **92.86%**, 4,043/4,354 lines |
| Strict analyzer | `flutter analyze --no-pub --fatal-infos --fatal-warnings` | **0 issues** |
| Formatter | `dart format --output=none --set-exit-if-changed lib test integration_test` | **118 files, 0 changed** |
| Release web build | `flutter build web --release --no-pub` | **PASS**, `build/web` produced |

Sihao's 116 presentation/E2E tests exceed the minimum of 14. The merged suite
also exceeds the team target of 100. A final rerun remains required after M3.

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
23. `7c740b1` — expanded device wrapper coverage
24. `6abd278` — rehearsal-to-basket isolation acceptance test
25. `111530a` — explicit package-mismatch evidence scenario
26. `ffb8741` — deterministic 60-second demo runbook
27. `c923134` — shared domain-to-UI mapping
28. `b1c3d06` — live AppState/APL M1 report source
29. `622ec63` — benefit-origin compatibility in immutable snapshots
30. `c01e080` — live M2 repair coordinator
31. `a47812d` — production `/basket` composition
32. `d3c4b57` — shared-domain rehearsal driver
33. `9b03d65` — shared-domain rehearsal on the basket route
34. `c9345a6` — production device-smoke coverage
35. `a1a6805` — production checkout-handoff acceptance
36. `db4c94e` — conservative M3 candidate evidence mapping
37. `717f399` — selected domain candidate to M2 repair bridge
38. `0f92253` — optional M3 production composition seam

Evidence-only refresh commits are intentionally omitted from this capability
list but remain visible in the complete Git history.

From shared integration base `d2005dd` through the verified parent, the Sihao
integration tranche contains 14 changed files, 1,867 insertions, and 77
deletions. Merge history, not this count alone, is the authoritative grading
evidence.

## Required integration handoff

After Feiyang merges the M3 implementation:

1. Instantiate Feiyang's concrete `AplCandidateProvider` from the inherited
   catalog service and pass it to `WolfGuardBasketScreen`; do not restructure
   `BasketScreen`.
2. Add a concrete-provider integration test proving exact UPC preservation,
   canonical-category filtering, duplicate removal, retryable source failure,
   and no basket mutation before confirm.
3. Rerun all 640 current tests plus M3 tests,
   regenerate coverage, and rerun analyzer, formatter, web build, Python,
   JavaScript, inherited M0, and M0-WG gates.
4. Run JavaScript gates in CI or a Node-equipped clone; the current container
   has no `node`, `nodejs`, or `npm`.
5. Record the screenshot/clip, merged final SHA, and final evidence only after
   M3 and the visual artifact actually pass.
