# WolfGuard Project 3: All-in-One Execution Plan

> Product: WolfBite checkout preflight and repair system
>
> Team: Andy, Wenbo, Feiyang, Sihao
>
> Delivery window: five focused implementation days
>
> Status: implementation contract; change only through a recorded team decision
>
> Inherited baseline reviewed locally: `fdd6efc` on 2026-11-25

## 0. How to use this document

This is the team's single source of truth for:

- the Project 3 delta and its four major milestones;
- ownership and worktree boundaries;
- frozen Dart interfaces between the four workstreams;
- functional and non-functional acceptance criteria;
- test targets and the new M0 evaluation claim;
- merge order, five-day schedule, demo path, and submission evidence.

When code and this document disagree, stop and resolve the disagreement before
merging. Do not silently change a shared interface in one worktree.

The feature name is **WolfGuard**. Its user-facing promise is:

> Before the shopper reaches the register, WolfGuard checks the whole basket,
> identifies what the app expects to be covered, self-paid, blocked, or unknown,
> explains why, and previews safe repair options before any change is applied.

WolfGuard is a prototype using application-managed allowances and available
catalog evidence. It does **not** query an official eWIC account, process a
payment, receive a retailer's official rejection reason, or guarantee checkout
acceptance.

---

## 1. Project 3 rubric alignment

The implementation must optimize for the teacher's four stated dimensions and
the Project 3 marking rules.

| Project 3 requirement | WolfGuard evidence |
| --- | --- |
| Extend another team's Project 2 | WolfGuard reuses `AppState`, APL access, basket UI, checkout help, category normalization, persistence, and the existing test harness. It does not replace the inherited application. |
| Four or more major milestones | M1 whole-basket preflight, M2 confirmed repair plans, M3 evidence-safe replacements, and M4 live readiness/handoff are independently testable and independently visible in the walkthrough. |
| Old code respected | New code lives under `lib/features/wolfguard/`; only the small, explicitly owned inherited integration surface in Section 5.5 may be changed. |
| Old tests still pass | The inherited 377 Flutter tests, Python checks, JavaScript checks, Firebase consistency check, analyzer, formatter, and web build are release gates. |
| Add many new tests | Minimum **60 new Dart tests**; target 80 and stretch target 100. A test means one independently reported `test` or `testWidgets`, not one assertion. |
| Inherited M0 remains | The existing `Project2_Work/M0` evaluator and known passing/failing fixtures must still run and its result must be reported. |
| One new M0 claim | M0-WG below measures whether a shopper can resolve a risky basket within 60 seconds and whether WolfGuard improves success over the inherited flow. |
| Delta is obvious | A recorded adoption baseline and fork point, feature-scoped commits, new feature directory, before/after screenshots, and a delta-only walkthrough make the extension auditable. |
| 12–30 second teaser | Teaser shows a risky basket, one WolfGuard action, and a ready basket. It is placed at the top of the root README. |
| 2–5 minute walkthrough | Walkthrough demonstrates all four milestones, inherited tests, new tests, M0 instruments, and one honest limitation. |
| Five-minute live demo | The same deterministic rehearsal data used by automated tests must be available without network setup; the normal signed-in flow must also remain runnable. |
| Poster | Poster shows inherited WolfBite, WolfGuard's four milestones, test/M0 evidence, audience, limitations, and next step. |

### Required evidence language

Use these terms consistently:

- **Expected coverage**, not “guaranteed eligible.”
- **Checkout preflight**, not “real checkout simulation.”
- **Application-managed allowance**, not “official WIC balance.”
- **Suggested repair**, not “the only correct action.”
- **Unknown**, not “safe,” when evidence is missing, malformed, stale, or
  contradictory.
- **Synthetic rehearsal**, not “participant result,” for fixture-driven demos.

---

## 2. Inherited baseline and trust audit

The team starts from a working inherited baseline, but must preserve evidence
instead of relying on its README claims.

### Locally verified on 2026-11-25

- Flutter 3.47.2 and Dart 3.13.2, matching CI.
- Locked dependency resolution succeeded.
- Dart formatting: 61 files checked, 0 changed.
- Static analysis: 0 issues.
- Flutter tests: 377 passed.
- Release web build succeeded.
- Local web server returned HTTP 200.
- Python tests: 37 passed.
- JavaScript tests: 21 passed.
- Firebase client configuration consistency check passed.
- Git working tree was clean before this Project 3 planning document.

### Adoption baseline procedure

Before feature code begins, record the actual commit in the team's fork:

```sh
git rev-parse HEAD
git remote -v
git status --short
```

Create an annotated tag only after confirming the commit is the untouched
inherited starting point:

```sh
git tag -a project3-adoption-baseline -m "Inherited WolfBite baseline for Project 3"
```

Do not call a later integration commit the fork point. The poster and final
report must show the actual adoption baseline SHA and final SHA.

---

## 3. Product scope

### 3.1 Primary user

A WIC shopper who has assembled a basket and wants to identify likely
allowance or evidence problems before reaching the register.

### 3.2 Primary journey

1. Shopper scans or adds products using inherited WolfBite behavior.
2. WolfGuard recalculates after every basket or allowance change.
3. Basket summary shows covered, self-paid, blocked, and unknown unit counts.
4. Shopper opens the preflight report and reads item-level evidence.
5. Shopper selects a proposed repair.
6. WolfGuard shows a before/after preview; the basket is still unchanged.
7. Shopper confirms or cancels.
8. On confirmation, the app applies the plan and recalculates.
9. Checkout handoff remains available, but unresolved blocked/unknown items
   require an explicit review acknowledgement.

### 3.3 In scope for five days

- Deterministic whole-basket allocation using the app's current basket and
  application-managed balances.
- Four statuses: covered, self-paid, blocked, unknown.
- Four issue families:
  - allowance exceeded;
  - not in current application benefit category;
  - package mismatch **only when explicit package evidence exists**;
  - insufficient, stale, malformed, or contradictory evidence.
- Repair proposals:
  - reduce quantity;
  - remove a line;
  - keep excess as self-paid;
  - replace with an evidence-safe same-category candidate.
- Preview and explicit confirmation before mutation.
- Evidence-safe replacement lookup from the inherited APL service.
- Accessible responsive UI and a guarded checkout handoff.
- Deterministic synthetic rehearsal fixtures for package rules and live demo.
- New M0 evaluator with known passing and failing fixtures.

### 3.4 Explicitly out of scope

- ebtEDGE scraping, card-number storage, PIN collection, or official account
  access.
- Retailer POS integration, payment, online ordering, inventory, or prices.
- A claim that an item will definitely be accepted at checkout.
- Inferring package size from a product name, UPC shape, nutrition serving
  size, or APL unit of measure.
- An LLM deciding eligibility, allowance allocation, or whether evidence is
  safe.
- Rewriting `AppState`, navigation, Firebase structure, or the existing basket.
- Native camera behavior beyond the inherited implementation.

### 3.5 Critical data limitation

The imported NC APL includes category, subcategory, and accounting unit fields,
but the repository documentation explicitly states that the accounting unit is
not a verified package size. Therefore:

- live APL records can prove catalog presence and category evidence;
- live APL records cannot by themselves prove a specific package-size rule;
- package-mismatch behavior is demonstrated with clearly labeled synthetic,
  hand-authored evidence unless a separately verified source is added;
- unknown package evidence must remain `unknown`.

---

## 4. Four major milestones and ownership

Each milestone must be visible in the walkthrough and must have its own test
evidence. A backend class alone is not a completed milestone.

### M1 — Whole-basket checkout preflight

**Owner: Andy**

User-visible result:

- WolfGuard evaluates every basket line together rather than checking one UPC
  in isolation.
- Each unit becomes `covered`, `selfPay`, `blocked`, or `unknown`.
- The report explains every non-covered result and exposes aggregate counts.
- Results are deterministic and analysis never mutates inputs.

Major-milestone rationale: this changes the inherited product from individual
lookup/help into a basket-level decision system.

Minimum tests: **18** unit/property-style cases.

### M2 — Confirmed multi-action repair plan

**Owner: Wenbo**

User-visible result:

- WolfGuard proposes reduce, remove, self-pay, or replacement actions.
- The shopper sees a before/after report before confirming.
- Cancel is a guaranteed no-op.
- Apply validates that the basket has not changed since the plan was created,
  applies supported actions, and triggers a fresh preflight.

Major-milestone rationale: the app moves from explaining a problem to safely
resolving it while keeping the shopper in control.

Minimum tests: **16** planner/state tests.

### M3 — Evidence-safe replacement search

**Owner: Feiyang**

User-visible result:

- An actionable issue can request alternatives from the imported NC APL.
- Candidates must be APL eligible and share the canonical original benefit
  category.
- Candidate UPCs are preserved and duplicate UPCs are removed.
- The UI distinguishes “same-category candidate” from “verified package
  match.” Missing size evidence stays unknown.
- Network/Firestore errors produce a retryable unavailable state and never a
  fabricated recommendation.

Major-milestone rationale: repair is grounded in the inherited catalog rather
than generic advice or invented products.

Minimum tests: **12** service/Firestore tests.

### M4 — Live readiness experience and safe handoff

**Owner: Sihao**

User-visible result:

- The basket continuously displays WolfGuard status.
- A responsive report shows aggregate status and per-item explanations.
- The repair preview and candidate states are accessible from the basket.
- Blocked or unknown items cannot be silently presented as “ready.” The shopper
  may still continue only after an explicit acknowledgement because WolfBite
  is not a payment gate.
- A deterministic “Try WolfGuard rehearsal” path demonstrates all statuses
  without live Firebase or a camera and is visibly labeled synthetic.

Major-milestone rationale: M1–M3 become a coherent, always-available user
workflow connected to the existing QR checkout handoff.

Minimum tests: **14** widget/E2E/accessibility cases.

### Milestone completion rule

A milestone is not “done” until it has:

1. user-visible behavior;
2. passing owned tests;
3. no analyzer or formatter failures;
4. one screenshot or short clip;
5. a short evidence note under the owner's evidence file;
6. a merged commit on the team's default branch.

Unmerged work is not counted.

---

## 5. Worktree and file-ownership plan

### 5.1 Bootstrap before splitting

One short bootstrap commit must be merged before the four worktrees diverge.
It creates the frozen domain/port files and empty directory structure. It must
compile and contain no feature behavior.

Recommended branches/worktrees, created from the same bootstrap SHA:

```sh
git worktree add ../wolfguard-andy   -b p3/andy-preflight   main
git worktree add ../wolfguard-wenbo  -b p3/wenbo-repair     main
git worktree add ../wolfguard-feiyang -b p3/feiyang-catalog main
git worktree add ../wolfguard-sihao  -b p3/sihao-ui-eval    main
```

If each developer uses a separate clone or machine, keep the same branch names
and ownership rules.

### 5.2 New source tree

```text
Project2/lib/features/wolfguard/
├── domain/
│   ├── wolfguard_models.dart             # Andy; frozen Day 1 noon
│   └── wolfguard_ports.dart              # Andy; frozen Day 1 noon
├── engine/
│   ├── checkout_preflight_engine.dart    # Andy only
│   └── preflight_rules.dart              # Andy only
├── repair/
│   ├── fix_planner.dart                  # Wenbo only
│   ├── fix_plan_applier.dart             # Wenbo only
│   └── basket_fingerprint.dart           # Wenbo only
├── catalog/
│   └── apl_candidate_provider.dart       # Feiyang only
└── presentation/
    ├── wolfguard_card.dart               # Sihao only
    ├── wolfguard_report_sheet.dart       # Sihao only
    ├── wolfguard_fix_sheet.dart          # Sihao only
    └── wolfguard_rehearsal_screen.dart   # Sihao only
```

### 5.3 Test tree

```text
Project2/test/features/wolfguard/
├── engine/                               # Andy only
├── repair/                               # Wenbo only
├── catalog/                              # Feiyang only
└── presentation/                         # Sihao only

Project2/test/e2e/wolfguard_journey_test.dart      # Sihao owns
Project2/test/fixtures/wolfguard_scenarios.json     # Andy owns schema/content
Project2/integration_test/wolfguard_demo_test.dart  # Sihao owns
```

### 5.4 Evaluation and evidence tree

Each person writes to a separate evidence file so documentation does not become
a daily conflict hotspot.

```text
Project3_Work/WolfGuard/
├── WOLFGUARD_ALL_IN_ONE_PLAN.md           # this contract; integration edits only
├── M0/
│   ├── evaluate_wolfguard_trials.py       # Sihao owns
│   ├── test_evaluate_wolfguard_trials.py  # Sihao owns
│   └── trial_data/                        # Sihao owns
└── evidence/
    ├── andy_m1.md                         # Andy only
    ├── wenbo_m2.md                        # Wenbo only
    ├── feiyang_m3.md                      # Feiyang only
    └── sihao_m4_m0.md                     # Sihao only
```

### 5.5 Exclusive ownership of inherited files

| Inherited file | Sole editor | Allowed change |
| --- | --- | --- |
| `Project2/lib/services/apl_service.dart` | Feiyang | Add/fix a read-only eligible replacement query that preserves UPC and canonical category. No nutrition rewrite. |
| `Project2/lib/state/app_state.dart` | Wenbo | At most one narrowly documented WolfGuard plan-application entry point if public existing mutations cannot satisfy the contract. No general refactor. |
| `Project2/lib/screens/basket_screen.dart` | Sihao | Insert WolfGuard card/sheet entry points; do not restructure inherited basket tiles. |
| `Project2/lib/screens/qr_checkout_screen.dart` | Sihao | Add review acknowledgement/handoff summary only if required by M4. |
| `Project2/lib/app_router.dart` | Sihao | Add rehearsal route only if a local `MaterialPageRoute` is insufficient. Prefer no change. |
| `Project2/pubspec.yaml` and lockfile | Sihao after team approval | No new package is expected. Any dependency requires all four reviewers. |
| Root `README.md`, `USER_GUIDE.md`, `Project2/docs/TESTING.md` | Sihao during final integration | Final evidence, videos, instructions, and limitations only. |
| CI workflow | Sihao during final integration | Only add Project 3 evidence commands; never weaken existing gates. |

Nobody else edits these files. If another owner needs a change, they send a
small requested diff or failing test to the sole editor.

### 5.6 Anti-conflict rules

1. Do not run `dart format .`; format only owned files.
2. Do not rename or move inherited files during the five-day window.
3. Do not perform drive-by cleanup, dependency upgrades, or mass comment edits.
4. Do not add generated mocks unless essential; prefer hand-written fakes.
5. Each commit touches one owner's paths, except the bootstrap/integration
   commits.
6. Shared domain contracts freeze at **Day 1 noon**.
7. A contract change requires:
   - a short proposal in team chat;
   - approval from all affected owners;
   - one contract commit merged to `main`;
   - all worktrees updated from that commit.
8. Merge at least once daily. Do not keep three days of invisible work in a
   worktree.
9. The integration owner does not copy another person's source into a new
   file to avoid a merge conflict. Resolve ownership instead.

### 5.7 Daily merge order

Use this order because later layers depend on earlier ports, not concrete
implementations:

1. Andy: domain/engine.
2. Feiyang: catalog adapter.
3. Wenbo: repair planner/applier.
4. Sihao: UI, E2E, evaluation, documentation.

M2 and M4 must develop against fakes for `CandidateProvider` and
`PreflightAnalyzer`; they must not wait for M1/M3 implementations.

---

## 6. Frozen interface contract

The exact file organization may be adjusted during the bootstrap commit, but
the semantics below must remain stable after Day 1 noon.

### 6.1 Domain enums

```dart
enum PreflightStatus {
  covered,
  selfPay,
  blocked,
  unknown,
}

enum IssueCode {
  allowanceExceeded,
  notInCurrentBenefits,
  packageMismatch,
  insufficientEvidence,
  staleEvidence,
  contradictoryEvidence,
}

enum FixKind {
  reduceQuantity,
  removeLine,
  keepAsSelfPay,
  replaceProduct,
}

enum EvidenceFreshness {
  current,
  stale,
  unknown,
}
```

### 6.2 Immutable input snapshots

Feature services do not receive mutable `AppState.basket` or `balances` maps
directly. The presentation adapter copies them into immutable snapshots first.

```dart
class BasketLineSnapshot {
  final String lineKey; // unique within this snapshot
  final String upc;
  final String name;
  final String basketCategory;
  final String? originalBenefitCategory;
  final int quantity;
  final ProductEvidence? evidence;
}

class ProductEvidence {
  final bool? aplEligible;
  final String? canonicalCategory;
  final PackageAmount? packageSize;
  final EvidenceFreshness freshness;
  final String sourceLabel;
}

class PackageAmount {
  final num value;
  final String unit;
}

class BenefitCategorySnapshot {
  final String category;
  final int? allowed; // null means app-uncapped, not unlimited official benefit
  final int used;
  final PackageAmount? permittedPackageSize;
  final EvidenceFreshness freshness;
}

class PreflightRequest {
  final List<BasketLineSnapshot> lines;
  final Map<String, BenefitCategorySnapshot> benefits;
  final DateTime evaluatedAt;
}
```

Snapshot rules:

- `lineKey` is generated once per request, for example
  `index:upc:canonicalBasketCategory`.
- A nonpositive/non-integer quantity becomes an unknown issue; it is not
  silently clamped.
- Category strings use inherited `WicCategories.canonical`.
- `PAID` is a payment classification, never an original benefit category.
- `allowed == null` means only that the prototype has no cap for that category.
- Missing values remain null; zero is valid evidence when explicitly supplied.

### 6.3 Preflight output

```dart
class LinePreflightResult {
  final String lineKey;
  final PreflightStatus status;
  final int quantity;
  final int coveredUnits;
  final int selfPayUnits;
  final int blockedUnits;
  final int unknownUnits;
  final List<PreflightIssue> issues;
}

class PreflightIssue {
  final IssueCode code;
  final String lineKey;
  final String title;
  final String explanation;
  final String suggestedNextStep;
  final List<String> evidenceLabels;
}

class PreflightReport {
  final List<LinePreflightResult> lines;
  final int totalUnits;
  final int coveredUnits;
  final int selfPayUnits;
  final int blockedUnits;
  final int unknownUnits;
  final String requestFingerprint;

  bool get readyForHandoff => blockedUnits == 0 && unknownUnits == 0;
}
```

If the UI displays a percentage, define it exactly as:

```text
readiness = (coveredUnits + acknowledgedSelfPayUnits) / totalUnits * 100
```

The UI must also display blocked and unknown counts. It must never hide unknown
evidence behind a high percentage. An empty basket has no readiness percentage
and is not ready for handoff.

### 6.4 M1 analyzer port

```dart
abstract interface class PreflightAnalyzer {
  PreflightReport analyze(PreflightRequest request);
}

final class CheckoutPreflightEngine implements PreflightAnalyzer {
  const CheckoutPreflightEngine();

  @override
  PreflightReport analyze(PreflightRequest request);
}
```

Contract:

- pure and deterministic for the same request;
- no Flutter, Firebase, network, clock lookup, or mutation;
- throws only for programmer-contract violations; malformed shopper evidence
  becomes `unknown`;
- never upgrades `unknown` to `covered`;
- allocates at basket level in stable input order;
- evaluates covered lines before self-pay classification and reports how many
  units fall into each outcome.

### 6.5 M2 repair port

```dart
class FixAction {
  final String actionId;
  final FixKind kind;
  final String lineKey;
  final int? targetQuantity;
  final ReplacementCandidate? replacement;
  final String shopperExplanation;
}

class FixPlan {
  final String planId;
  final String sourceFingerprint;
  final List<FixAction> actions;
  final PreflightReport before;
  final PreflightReport projectedAfter;
}

abstract interface class FixPlanner {
  FixPlan propose({
    required PreflightRequest request,
    required PreflightReport report,
    required Map<String, List<ReplacementCandidate>> candidatesByLine,
  });
}

enum ApplyPlanResult {
  applied,
  stalePlan,
  unsupportedAction,
  persistenceFailed,
}

abstract interface class FixPlanApplier {
  Future<ApplyPlanResult> apply(FixPlan plan);
}
```

Contract:

- proposal is pure and never mutates state;
- plans contain no action for a covered line;
- replacement is never proposed when category/eligibility evidence is unsafe;
- a same-category replacement does not pretend to restore an exhausted
  allowance;
- apply first recomputes the basket fingerprint; stale plans do nothing;
- cancel never calls the applier;
- after an apply attempt, UI reruns preflight from current state;
- persistence failure is visible and is not reported as success.

### 6.6 M3 catalog port

```dart
class ReplacementCandidate {
  final String upc;
  final String name;
  final String canonicalCategory;
  final bool aplEligible;
  final PackageAmount? verifiedPackageSize;
  final EvidenceFreshness freshness;
  final String evidenceLabel;
}

abstract interface class CandidateProvider {
  Future<List<ReplacementCandidate>> findFor({
    required BasketLineSnapshot line,
    int max = 5,
  });
}

final class AplCandidateProvider implements CandidateProvider {
  AplCandidateProvider(AplService apl);
}
```

Contract:

- read-only;
- blank/PAID/unknown original category returns an empty list;
- exact UPC of the current product is excluded;
- only `eligible == true` candidates are returned;
- category is canonical and equal to the line's original category;
- results preserve Firestore document UPCs and are deduplicated by UPC;
- missing package evidence remains null;
- source errors propagate to the presentation layer, which shows retry;
- no basket mutation occurs.

### 6.7 Presentation integration contract

The main reusable entry widget should accept ports rather than instantiate
concrete services internally:

```dart
class WolfGuardCard extends StatelessWidget {
  const WolfGuardCard({
    super.key,
    required this.analyzer,
    required this.fixPlanner,
    required this.candidateProvider,
    required this.planApplier,
  });
}
```

This makes widget tests independent from Firebase and lets Sihao build with
fakes while the other worktrees are in progress.

---

## 7. Functional requirements and acceptance criteria

### FR-1: Whole-basket analysis

Given a nonempty basket and loaded app balances, when WolfGuard analyzes the
basket, then every line and every unit appears in exactly one outcome count.

Acceptance:

- Sum of covered + self-pay + blocked + unknown equals total units.
- Same request produces an equal report.
- Analysis does not modify basket, balances, or evidence maps.
- Duplicate UPC lines with covered and PAID categories remain distinct.
- Category spelling variants share the inherited canonical category.

### FR-2: Conservative evidence handling

Acceptance:

- Missing APL evidence cannot produce covered.
- Missing original category on a PAID line produces unknown unless recovered
  unambiguously from exact UPC evidence.
- Stale or contradictory evidence produces a named issue.
- Numeric zero is not treated as missing.
- Package mismatch is emitted only when both selected and permitted package
  sizes have supported, equal units and current explicit evidence.
- Different or unsupported units produce unknown; no conversion is guessed.

### FR-3: Allowance allocation

Acceptance:

- A covered category with enough remaining app allowance classifies the
  allocated units covered.
- Excess units are self-pay only when the current basket explicitly represents
  them as PAID or the shopper selects that repair.
- A new covered line that exceeds allowance is blocked; it is not silently
  rewritten as paid during analysis.
- App-uncapped categories are clearly labeled prototype-uncapped.
- Used/allowed inconsistencies produce unknown rather than a negative balance.

### FR-4: Repair proposal

Acceptance:

- Every blocked issue has at least one valid non-destructive proposal when a
  repair is possible.
- Unknown evidence never receives an automatic “safe replacement” action.
- A zero remaining category allowance does not receive a same-category swap as
  a coverage repair.
- Proposed after-state is produced by running the same analyzer on a projected
  snapshot, not by changing counts manually.
- No action applies before confirmation.

### FR-5: Confirmation and stale-plan protection

Acceptance:

- Preview shows product/quantity/category changes and before/after status.
- Cancel leaves basket, balances, persistence, and report unchanged.
- If basket fingerprint changed after preview, Apply returns `stalePlan` and
  makes no mutation.
- Rapid repeated Apply taps execute at most once.
- Success is shown only after state mutation completes; persistence errors are
  surfaced.

### FR-6: Replacement lookup

Acceptance:

- Lookup uses the exact canonical original category.
- Current UPC and duplicate UPCs are absent.
- Ineligible products are absent.
- Candidate UPC is available to `AppState.swapItem`.
- Empty results say “No evidence-safe alternatives found,” not “No alternatives
  exist.”
- Firestore failure offers Retry and leaves the basket unchanged.

### FR-7: Live readiness UI

Acceptance:

- Basket mutations cause a recalculated card without manual refresh.
- Loading, empty, ready, attention, error, and unknown states are distinct.
- Each warning identifies its affected product.
- All actions have semantic labels and tooltips where appropriate.
- Narrow 320 px layout and 200% text scale remain scrollable and closable.
- Status is not communicated by color alone.

### FR-8: Safe checkout handoff

Acceptance:

- `Ready to Checkout` remains available for a fully reviewed basket.
- Blocked/unknown status opens the WolfGuard report before QR navigation.
- The shopper may explicitly continue after acknowledging limitations; the app
  does not impersonate an official payment gate.
- Opening, cancelling, or acknowledging the report does not modify the basket.
- Existing QR checkout behavior remains intact.

### FR-9: Deterministic rehearsal

Acceptance:

- Rehearsal is visibly labeled “Synthetic sample; not live benefits.”
- It contains covered, self-pay, blocked, and unknown examples.
- It runs without Firebase, network, camera, credentials, or mutable user data.
- It uses the same analyzer/planner/widgets as the normal basket flow.
- It does not alter the signed-in shopper's basket.

---

## 8. Non-functional requirements

### NFR-1: Performance

- Pure analysis of 100 lines completes under 100 ms in a local unit benchmark.
- UI shows the new report within 500 ms of an ordinary basket mutation in the
  widget/E2E harness.
- Catalog lookup may be async; the prior report remains visible with a loading
  indicator.

### NFR-2: Reliability

- No unhandled exception for malformed fixture values.
- No state mutation from analysis, candidate lookup, preview, or cancel.
- Existing persistence semantics and monthly reset remain unchanged.

### NFR-3: Accessibility

- 320 px viewport and 200% text scale have no overflow exception.
- Screen-reader labels include product name, status, and recommended action.
- Focus returns to a meaningful control when a sheet closes.

### NFR-4: Privacy and safety

- No eWIC card number, PIN, personal receipt image, or official balance is
  required by WolfGuard.
- Trial data uses participant codes, not names/emails.
- Logs contain scenario IDs and outcomes, not credentials or personal data.

### NFR-5: Maintainability

- Feature logic has no Firebase/Flutter imports in domain and engine layers.
- Public types have Dartdoc.
- No new dependency without unanimous team approval.
- The feature can be removed by deleting its feature directory and the small
  owned integration edits.

---

## 9. Test plan

### 9.1 Minimum new Dart test budget

| Owner | Layer | Minimum | Required themes |
| --- | --- | ---: | --- |
| Andy | Engine unit tests | 18 | allocation, PAID split, zero/null, malformed input, category normalization, determinism, non-mutation, package evidence |
| Wenbo | Planner/state tests | 16 | every fix kind, preview, cancel, stale fingerprint, repeated apply, unsupported operation, persistence failure |
| Feiyang | Catalog/fake Firestore tests | 12 | UPC preservation, category, eligibility, dedupe, self exclusion, empty/error/retry, missing size evidence |
| Sihao | Widget/E2E/device tests | 14 | all visual states, responsive/large text, semantics, report flow, gate/acknowledge, rehearsal, full repair journey |
| **Total** |  | **60** | Target: 80; stretch target: 100 |

### 9.2 Mandatory adversarial cases

- Covered and PAID lines share the same UPC.
- Basket has two category spelling variants.
- `used > allowed` inherited inconsistency.
- Allowed is zero; used is zero.
- Allowed is null.
- Quantity is zero, negative, decimal, string, or missing in raw adapter input.
- UPC is blank.
- Category is `PAID`, `UNKNOWN`, whitespace, or missing.
- APL says ineligible.
- Package sizes differ by binary floating-point noise only.
- Package units are unknown or incompatible.
- Evidence changes while preview is open.
- Candidate fetch fails after a previous successful fetch.
- User taps Apply twice quickly.
- Persistence reports failure.
- 320 px viewport with 200% text.

### 9.3 Inherited regression gates

All inherited checks remain release-blocking. Do not delete, skip, loosen, or
rewrite an inherited test just to merge WolfGuard.

```sh
cd Project2
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --no-pub --fatal-infos --fatal-warnings
flutter test --no-pub --coverage --concurrency=1
flutter build web --release --no-pub
python -m unittest discover -s scripts -p 'test_*.py' -v
node --test scripts/test_*.cjs
python scripts/verify_firebase_config.py
```

From repository root:

```sh
python -m unittest discover -s .github/scripts -p 'test_*.py' -v
python -m unittest discover -s Project2_Work/M0 -p 'test_*.py' -v
node --test .github/scripts/test_publish_ci_evidence.cjs
```

### 9.4 Evidence to record

Final evidence must state:

- final commit SHA;
- Flutter/Dart/Node/Python versions;
- inherited Flutter pass count;
- new WolfGuard Dart test count;
- total pass/fail/skip count;
- coverage numerator, denominator, and percentage;
- analyzer, formatter, web build, Python, JavaScript, and Firebase results;
- inherited M0 result;
- new M0 result, or `Not Verified` if participant evidence is missing;
- platform and reviewer for manual/live checks.

---

## 10. New M0 claim and evaluation instrument

### 10.1 Claim M0-WG

For the team's predefined risky-basket scenarios:

> At least 80% of participants using WolfGuard will reach a basket with no
> unresolved actionable (`blocked`) issue within 60 seconds and without outside
> assistance, and WolfGuard success will be at least 20 percentage points higher
> than the inherited basket plus item-level checkout-help flow.

This is a business/user outcome claim, not a unit-test claim.

### 10.2 Trial design

Use the same scenario for both conditions:

- **baseline**: inherited basket and item-level checkout help;
- **wolfguard**: readiness report, repair preview, and confirmation.

Counterbalance condition order when possible. A participant must not evaluate
their own authored implementation if external classmates are available.

Success requires all of the following:

1. all actionable blocked issues resolved;
2. no unsafe action accepted as covered;
3. elapsed time `<= 60.0` seconds;
4. no outside assistance;
5. final state confirmed by the instrument's scenario oracle.

Unknown evidence may remain only when the participant explicitly identifies it
as requiring review; it must not be counted as covered.

### 10.3 Trial record schema

```json
{
  "trial_id": "P01-baseline-S1",
  "participant_code": "P01",
  "condition": "baseline",
  "scenario_id": "WG-S1",
  "elapsed_seconds": 54.2,
  "actionable_issues_resolved": true,
  "unsafe_coverage_claim": false,
  "unknown_acknowledged": true,
  "outside_assistance": false,
  "completed": true
}
```

Do not store participant name, email, card data, or credentials.

### 10.4 Scorer output

`evaluate_wolfguard_trials.py` must print and optionally emit JSON containing:

- validated trial count by condition;
- success count and rate by condition;
- median elapsed seconds by condition;
- WolfGuard minus baseline percentage-point difference;
- pass/fail for the 80% WolfGuard requirement;
- pass/fail for the +20 percentage-point requirement;
- per-trial failure reasons;
- `synthetic`, `participant`, or `mixed` evidence label.

### 10.5 Instrument acceptance

- Reject missing required fields.
- Reject duplicate trial IDs.
- Reject unknown conditions or scenarios.
- Reject negative, non-finite, or Boolean elapsed time.
- Exactly 60.0 seconds passes; greater than 60.0 fails.
- Any outside assistance fails the trial.
- An unsafe coverage claim fails the trial.
- Known passing fixture passes both thresholds.
- Known failing fixture fails both thresholds.
- Synthetic fixtures validate the instrument only; they do not validate M0.

If real participant trials are not completed, the poster/report must say:

> M0-WG instrument verified with synthetic passing and failing fixtures;
> participant outcome claim Not Verified.

### 10.6 Inherited M0 preservation

The existing checkout-help M0 scorer in `Project2_Work/M0` remains unchanged
unless a genuine compatibility defect is found. Its tests and known fixtures
must run in final evidence. Report its number separately from M0-WG; do not
merge the two metrics.

---

## 11. Five-day execution schedule

### Before Day 1: 60-minute team setup

- Confirm adoption baseline and remote URLs.
- Merge this plan.
- Create bootstrap domain/port stubs.
- Run the full inherited baseline once on the team's default branch.
- Create four worktrees from the same bootstrap SHA.

### Day 1: contracts and failing tests

**Andy**

- Finalize immutable domain types and analyzer port.
- Add fixture schema and at least 10 failing engine tests.
- Freeze shared contracts at noon.

**Wenbo**

- Build planner/applier against fake analyzer and fake state adapter.
- Add fingerprint and cancel/stale-plan tests.

**Feiyang**

- Build candidate-provider fake and Firestore test data.
- Confirm exact APL fields and add failing candidate tests.

**Sihao**

- Build the card/report/preview with fake ports.
- Draft M0 schema/scorer tests.
- Prepare deterministic 60-second demo storyboard.

Day 1 exit gate: contracts compile; each branch has failing tests that describe
its acceptance criteria; no one is blocked on another concrete implementation.

### Day 2: core implementations

**Andy** completes deterministic preflight and 18+ tests.

**Wenbo** completes pure fix-plan projection and 12+ tests.

**Feiyang** completes APL provider and 10+ tests.

**Sihao** completes all UI states with fakes and 8+ widget tests.

Merge small PRs in the daily merge order. Run targeted tests after each merge.

### Day 3: state and UI integration

- Wenbo integrates plan application using the smallest possible `AppState`
  edit and proves cancel/stale/repeat behavior.
- Feiyang integrates real fake-Firestore APL queries and error behavior.
- Sihao inserts WolfGuard into `BasketScreen` and checkout handoff.
- Andy adds adversarial tests from observed integration failures.
- Build one full E2E journey by end of day.

Day 3 exit gate: normal basket -> report -> preview -> confirm -> recalculated
report works in a widget/E2E test.

### Day 4: evidence, M0, and hardening

- Reach at least 60 new Dart tests.
- Complete rehearsal mode and responsive/accessibility tests.
- Complete M0 scorer plus known passing/failing fixtures.
- Run inherited M0 unchanged.
- Run full Flutter suite, analyzer, formatter, scripts, and web build.
- Record screenshots/clips and fix only verified defects.

No new feature scope after Day 4 noon.

### Day 5: release rehearsal

- Fresh-clone or clean-worktree installation check.
- Run every final command in Section 13.
- Record final SHA and counts.
- Record 12–30 second teaser.
- Record 2–5 minute delta walkthrough.
- Update README at top, user guide, testing evidence, and limitations.
- Finish poster before/after panels and URLs.
- Rehearse five-minute tutor demo twice, including one “show it live” run.

---

## 12. Merge and review protocol

### Pull request size

- Prefer fewer than 400 changed source lines per PR, excluding fixtures/tests.
- One milestone concern per PR.
- Every PR description lists owned files, tests run, and acceptance IDs covered.

### Required reviewers

| PR area | Required reviewer |
| --- | --- |
| Domain/engine | Wenbo plus one other member |
| Repair/state | Andy plus Sihao |
| Catalog/data | Andy plus one other member |
| UI/integration | Wenbo plus one other member |
| M0/evidence/claims | All four members |

### Review checklist

- Is this an extension rather than a rewrite?
- Does it stay inside the owner's paths?
- Does unknown stay unknown?
- Is input mutation impossible or tested?
- Does the UI claim more than the evidence supports?
- Are old behaviors and tests preserved?
- Are new tests meaningful rather than assertion inflation?
- Is the code visible in merged history?

### Conflict resolution

If a branch conflicts in an inherited file, the sole owner resolves it in their
worktree. Other members do not resolve by choosing “ours” or “theirs” over code
they do not own.

---

## 13. Final release gate: what must run

The project is ready only when all items below pass on the same final merged
commit.

### 13.1 Automated gate

Run from `Project2/`:

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --no-pub --fatal-infos --fatal-warnings
flutter test --no-pub --coverage --concurrency=1 --reporter expanded
flutter build web --release --no-pub
python -m unittest discover -s scripts -p 'test_*.py' -v
python scripts/verify_firebase_config.py
node --test scripts/test_*.cjs
```

Run from repository root:

```sh
python -m unittest discover -s .github/scripts -p 'test_*.py' -v
node --test .github/scripts/test_publish_ci_evidence.cjs
python -m unittest discover -s Project2_Work/M0 -p 'test_*.py' -v
python -m unittest discover -s Project3_Work/WolfGuard/M0 -p 'test_*.py' -v
python Project3_Work/WolfGuard/M0/evaluate_wolfguard_trials.py \
  Project3_Work/WolfGuard/M0/trial_data/passing_example.json
```

Then run the known failing M0-WG fixture and confirm that the scorer exits or
reports failure exactly as documented. An evaluator that cannot fail is not an
instrument.

### 13.2 Pass thresholds

- Inherited 377 Flutter tests still pass, adjusted upward only by genuine new
  tests discovered in the same suite.
- At least 60 new WolfGuard Dart tests pass.
- 0 failed and 0 unexpectedly skipped tests.
- Coverage report exists and is nonempty; final percentage is reported rather
  than promised in advance.
- Analyzer: 0 warnings/errors/info under fatal settings.
- Formatter: 0 changed files.
- Release web build succeeds.
- All inherited Python/JavaScript/Firebase checks pass.
- Inherited M0 tests and scorer still run.
- M0-WG instrument tests and known fixtures behave correctly.

### 13.3 Live product gate

The final merged app must support this normal flow:

1. Start the app with no code generation or setup during the demo.
2. Sign in or use the preconfigured safe demo account.
3. Add a known APL product.
4. Increase quantity until inherited allowance behavior creates a PAID line.
5. Open Basket and see WolfGuard update automatically.
6. Open the report and identify covered/self-paid/unknown evidence correctly.
7. Request alternatives and show the catalog's honest evidence labels.
8. Preview a repair; show that the basket has not changed.
9. Cancel once and prove no change.
10. Preview again, confirm, and show a recalculated report.
11. Continue to the inherited QR checkout flow.

The deterministic rehearsal must support this offline flow:

1. Open “Try WolfGuard rehearsal.”
2. Show covered, self-pay, blocked, package-mismatch, and unknown scenarios.
3. Preview and apply one repair.
4. Show before/after counts.
5. Close rehearsal and prove the user's real basket is unchanged.

### 13.4 Demo fallback hierarchy

1. Normal signed-in live flow.
2. Deterministic in-app rehearsal using production WolfGuard components.
3. Automated E2E/device test shown live.
4. Walkthrough video only if the tutor does not request the live app.

The feature must never depend on network-only data for its sole demo path.

---

## 14. Walkthrough and teaser storyboard

### 12–30 second teaser

Target: 18–22 seconds.

1. `0–4s`: basket reads “Needs review: 3 issues.”
2. `4–9s`: WolfGuard highlights allowance, self-pay, and unknown evidence.
3. `9–15s`: shopper previews and confirms a repair.
4. `15–20s`: report changes to “Reviewed”; QR checkout action appears.
5. End card: “WolfGuard — fix the basket before the register.”

Place the video at the top of the root README, not buried in docs.

### 2–5 minute walkthrough

Target: 3 minutes 30 seconds.

1. `0:00–0:20`: inherited WolfBite and exact fork/adoption baseline.
2. `0:20–0:55`: M1 whole-basket preflight.
3. `0:55–1:30`: M2 preview/cancel/confirm repair.
4. `1:30–2:00`: M3 real APL candidate and honest package-evidence limitation.
5. `2:00–2:30`: M4 responsive readiness and safe handoff.
6. `2:30–3:00`: old + new automated tests and final build.
7. `3:00–3:20`: inherited M0 and M0-WG results, clearly separating synthetic
   and participant evidence.
8. `3:20–3:30`: audience, impact, and next step.

---

## 15. Poster content checklist

The poster must make the delta understandable in 15 seconds.

### Before

- Individual product lookup.
- Application-managed basket and allowance.
- Nutrition and item-level checkout help.
- 377-test inherited baseline.

### Now

- M1 whole-basket preflight.
- M2 confirmed repair plans.
- M3 evidence-safe APL replacements.
- M4 live readiness and checkout handoff.

### Evidence

- Adoption/fork SHA -> final SHA.
- Old tests passing.
- New test count and coverage.
- Analyzer/build/script results.
- Inherited M0 result.
- New M0-WG result or `Not Verified` wording.
- One architecture diagram and one before/after UI image.

### Audience and market

- Primary audience: WIC shoppers preparing for checkout.
- Problem: product-level lookup does not explain conflicts across the whole
  basket.
- Benefit: earlier, clearer resolution before the register.
- Honest boundary: prototype allowances, not official transaction approval.

### Next

- Verified package-rule source.
- Official/state-authorized balance integration.
- Retailer feedback or online ordering only through approved partnerships.

Include both required repository URLs and the poster PDF in the repository and
shared poster folder.

---

## 16. Definition of done

WolfGuard is complete only when:

- [ ] Adoption baseline and final SHA are recorded.
- [ ] All four milestones are merged and independently visible.
- [ ] File ownership rules were followed or exceptions documented.
- [ ] At least 60 new Dart tests pass.
- [ ] All inherited tests/checks pass.
- [ ] Inherited M0 still runs and is reported.
- [ ] M0-WG instrument has validation tests plus passing/failing fixtures.
- [ ] Participant M0 evidence is either reported honestly or marked Not Verified.
- [ ] Release web build succeeds from a clean merged worktree.
- [ ] Normal live flow and offline rehearsal both run.
- [ ] 12–30 second teaser is at the top of README.
- [ ] 2–5 minute delta walkthrough is linked from README.
- [ ] Poster shows before, after, evidence, audience, limitations, and URLs.
- [ ] Five-minute tutor demo has been rehearsed twice.
- [ ] No card/PIN/credential or personal trial data entered the repository.
- [ ] Git working tree is clean at the tagged submission commit.

---

## 17. Fast decision rules during the five-day build

When time is tight, apply these in order:

1. Preserve old tests and inherited behavior.
2. Preserve truthful evidence handling; never turn unknown into covered.
3. Complete one end-to-end path through all four milestones.
4. Complete 60 meaningful tests and both M0 instruments.
5. Make the demo deterministic and setup-free.
6. Improve styling only after the above gates pass.

Cut in this order if schedule slips:

1. animation and visual polish;
2. more than three candidates per issue;
3. multiple repair-plan variants;
4. optional route changes;
5. performance micro-benchmark UI.

Do **not** cut:

- conservative unknown behavior;
- preview/cancel semantics;
- the offline rehearsal;
- old regression tests;
- 60 new tests;
- inherited M0;
- the new M0 instrument;
- README videos and poster evidence.

---

## 18. Team sign-off

Before implementation begins, each member confirms their owned paths and the
frozen interface contract.

| Member | Milestone | Contract accepted | Day 1 merge complete | Final evidence complete |
| --- | --- | --- | --- | --- |
| Andy | M1 Preflight | [ ] | [ ] | [ ] |
| Wenbo | M2 Repair | [ ] | [ ] | [ ] |
| Feiyang | M3 Catalog replacements | [ ] | [ ] | [ ] |
| Sihao | M4 UI/handoff + M0 integration | [ ] | [ ] | [ ] |

Any change to scope, ownership, public interfaces, M0 claim, or evidence
language must be written into the decision log below.

### Decision log

| Date | Decision | Reason | Approved by |
| --- | --- | --- | --- |
| 2026-11-25 | Adopt WolfGuard as the Project 3 delta with four worktree-isolated milestones. | Five-day scope reuses the inherited product while creating a visible basket-level workflow. | Pending team sign-off |
