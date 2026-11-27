# M2 evidence: confirmed multi-action repair plan

**Owner:** Wenbo Li
**Milestone:** M2, confirmed multi-action repair plan
**Branch:** `p3/wenbo-repair`, cut from the integration branch `Sihao`

---

## 1. What a shopper can now do

Before M2, WolfGuard could explain that a basket was risky. After M2 it
proposes a **suggested repair** for each line that is not covered, shows the
whole proposal with the projected result beside the current one, and changes
nothing until the shopper confirms.

| Kind | Proposed when | What it does |
| --- | --- | --- |
| `reduceQuantity` | Expected coverage reaches part of a line | Keeps exactly the units the application-managed allowance still reaches |
| `keepAsSelfPay` | Evidence is **unknown**, the allowance is spent, or no eligible alternative exists | Moves the line to the `PAID` classification, claiming nothing against the benefit |
| `replaceProduct` | The product is not in current benefits and an evidence-safe alternative exists | Swaps it in, keeping category and quantity |
| `removeLine` | The line is missing the details needed to check it | Takes it out so the rest can be checked |

Cancel is the absence of an apply call: nothing is written during a preview,
so there is nothing to undo.

---

## 2. What was built

| File | Role |
| --- | --- |
| `Project2/lib/features/wolfguard/repair/basket_fingerprint.dart` | Binds a plan to the state it was proposed from; `BasketLineKey`, the line-key contract |
| `Project2/lib/features/wolfguard/repair/fix_planner.dart` | `WolfGuardFixPlanner`, the pure proposal step |
| `Project2/lib/features/wolfguard/repair/fix_plan_applier.dart` | `WolfGuardFixPlanApplier` and the `RepairTarget` port |
| `Project2/lib/state/app_state.dart` | One added entry point, `commitWolfGuardRepair` |
| `Project2/test/features/wolfguard/repair/` | Owned tests and hand-written fakes |

Nothing outside `repair/` and that one entry point was touched. No inherited
test was deleted, skipped, loosened, or rewritten.

---

## 3. Design decisions worth reviewing

### 3.1 There is one definition of basket identity, not two

A plan carries the fingerprint of the state it was proposed from, and Apply
re-snapshots live state and compares before doing anything. That fingerprint
is `PreflightRequest.fingerprint` from the merged domain; the repair layer
adds no hash of its own, so there is nothing to keep in step.

Because the fingerprint covers catalog evidence, the snapshot reaches the
applier as a callback rather than being rebuilt inside it. A snapshot
assembled without the evidence the preview used would fingerprint differently
and make every plan look stale. The caller that built the preview is the only
one that can rebuild it faithfully.

### 3.2 The after-state is computed, not asserted

FR-4 requires the projected after-state to come from running the same analyzer
on a projected basket. The planner rewrites the line snapshots and hands the
rewritten request back to the injected `PreflightAnalyzer`. A test asserts the
analyzer really was called a second time with the rewritten lines, so this
cannot decay into hand-adjusted counts.

### 3.3 Unknown evidence is offered self-pay, never a replacement

This is the decision most worth arguing with.

FR-4 forbids an automatic replacement on unknown evidence, and a reduction
would be the same guess wearing a different label. But proposing *nothing*
has a consequence that is easy to miss: `readyForHandoff` requires zero
unknown units, so a basket whose evidence is missing, stale, or unanswered
could never be made ready, and M2 would have nothing to offer for the most
common real failure.

Self-pay claims nothing against the benefit, so it is the one repair that is
honest about not knowing. Its explanation says WolfGuard could not confirm
expected coverage and tells the shopper to ask store staff before paying if
they believe the item is covered. Verified against the merged engine: a line
moved to `PAID` with its `original_benefit_category` intact is reported
`selfPay`, and the report becomes ready.

### 3.4 A spent allowance is never answered with a swap

Section 6.5 forbids a same-category replacement from pretending to restore an
exhausted allowance. With no room left the planner proposes `keepAsSelfPay`
and says plainly that no swap would bring the line into expected coverage.

### 3.5 A replacement must be evidenced

A candidate is only proposed when it is eligible, in the same canonical
benefit category, not the product already on the line, carries **current**
rather than stale evidence, and, when the package size was the problem,
matches the permitted size under `PackageRules.compare`. Candidate order from
the catalog is preserved, so M3's ranking decides between equally safe
options. A rejected candidate is not an error: the shopper is offered self-pay
instead.

### 3.6 All of a plan, or none of it

Apply builds one projected basket and one projected balance map and commits
them together. A single action that cannot be carried out refuses the whole
plan, because a partly applied plan is not the one the shopper confirmed.

---

## 4. The one inherited change, and why it was needed

Section 5.5 permits at most one narrowly documented WolfGuard entry point in
`app_state.dart`. M2 needs it for three independent reasons:

1. `decrementItem` always takes from the `PAID` line for a UPC when one
   exists, so it cannot target the benefit line a plan names. "Covered and
   PAID lines share the same UPC" is on the section 9.2 adversarial list, and
   a test covers it.
2. No public mutation moves units from a benefit line to `PAID`, which is
   exactly what `keepAsSelfPay` does.
3. `addItem`, `incrementItem` and `decrementItem` all start `_persist()`
   without awaiting it, so a failed write is invisible. FR-5 requires
   persistence errors to be surfaced, and `ApplyPlanResult.persistenceFailed`
   exists to carry them.

`commitWolfGuardRepair` awaits the write, restores the previous basket and
balances if it throws, and returns false so the caller reports
`persistenceFailed` instead of success. It interprets no plan, derives no
allowance, and applies no repair rules. The inherited mutations are untouched;
`AppState` gains one `implements` clause and two `@override` annotations on
fields it already had.

Diff size in the inherited file: **68 insertions, 1 deletion**.

---

## 5. One finding the team should know about

**`reduceQuantity` is contract-reachable but practically unreachable from live
`AppState` data.**

`PreflightRequestBuilder` subtracts the current basket from each category's
`used` figure. `AppState` never lets `used` exceed `allowed` for a benefit
category, because `addItem` and `incrementItem` push the overflow onto a
`PAID` line instead. Put together, a request built from consistent inherited
state always has at least as much headroom as the basket needs, so the
engine's `blocked` plus `allowanceExceeded` path is not reached. Raw states
that *would* reach it are inconsistent in the inherited sense and come back
`unknown` with `contradictoryEvidence`.

Checked by probing `CheckoutPreflightEngine` directly across eight raw
states. A hand-built request does reach the path and the planner handles it,
which is what the `reduceQuantity` tests use, and the same is true for the
scenario fixture.

So in the live demo the repairs a shopper will actually see are self-pay for
unverified items, replacement for ineligible ones, and removal for unreadable
lines. That is worth knowing before the walkthrough is scripted, and it is an
argument for the rehearsal fixture carrying an explicit overflow basket.

The related contract question is **resolved, not open**: the planner reads
`BenefitCategorySnapshot.used` as allowance spent outside the current basket,
and `PreflightRequestBuilder` documents and implements exactly that. The
applier works on the raw `AppState.balances` map, where `used` does include
basket contents, and mirrors the inherited bookkeeping there.

---

## 6. Tests

All under `Project2/test/features/wolfguard/repair/`. A test means one
independently reported `test`, not one assertion.

| File | Tests | Covers |
| --- | ---: | --- |
| `basket_fingerprint_test.dart` | 10 | key round trip against the real builder, malformed keys, blank UPC, quantity, allowance, evidence changes, evaluation time, plan binding |
| `fix_planner_test.dart` | 32 | every fix kind, unknown evidence, covered and PAID lines left alone, replacement safety, preview projection, non-mutation, plan identity, mismatched report |
| `fix_plan_applier_test.dart` | 30 | stale fingerprint, repeated apply, double tap, cancel, every fix kind applied, PAID twin lines, merging, eleven unsupported operations, persistence failure and retry |
| **Total** | **72** | Minimum required for M2: **16** |

The planner tests run against `CheckoutPreflightEngine`, not a fake. Section
5.7 asked M2 to develop against fakes while M1 was in progress; now that the
engine is merged, `RecordingAnalyzer` wraps the real one so allocation rules
are real and the projected request is still observable. Where a scenario
cannot be expressed through `PreflightRequestBuilder`, the test builds the
request directly and says why.

### Section 9.2 adversarial cases covered here

| Case | Test |
| --- | --- |
| Covered and PAID lines share the same UPC | `a benefit line is reduced even when a PAID twin shares its UPC` |
| Basket has two category spelling variants | `a category spelling variant still resolves to its line` |
| Allowed is zero or already spent | `an exhausted allowance gets self-pay, never a same-category swap` |
| Quantity is zero, negative, or not an integer | `a nonpositive quantity is removed, not silently clamped`; `a quantity that is not an integer is removed as unreadable` |
| UPC is blank | `removeLine is proposed for a line the app cannot read` |
| Category is `PAID`, `UNKNOWN`, or missing | `an acknowledged self-pay line is not repaired again`; `a PAID line of unknown origin is left to the report`; `a line with no benefit category gets no action` |
| APL says ineligible | `replaceProduct is proposed for an ineligible product`; `an ineligible candidate is rejected` |
| Evidence is stale | `stale evidence is treated as unverified, not as proof`; `a candidate whose evidence is stale is rejected` |
| Evidence changes while preview is open | `changes when catalog evidence changes`; `a plan is refused once the basket changed` |
| User taps Apply twice quickly | `a double tap on one plan commits exactly once` |
| Persistence reports failure | `a failed write is reported, never as success` |

Left to other owners: candidate fetch failure and retry are M3's; the 320 px
viewport with 200% text is M4's.

---

## 7. Verified results

Run locally on macOS (darwin arm64), on the toolchain the CI workflow pins.

| Tool | Version |
| --- | --- |
| Flutter | 3.47.2 |
| Dart | 3.13.2 |
| Node | 24.20.0 |
| Python | 3.12.7 |

| Gate | Command | Result |
| --- | --- | --- |
| Formatter | `dart format --output=none --set-exit-if-changed lib test tool` | PASS, 105 files unchanged |
| Analyzer | `flutter analyze --no-pub --fatal-infos --fatal-warnings` | PASS, no issues |
| Dart tests | `flutter test --no-pub --coverage --concurrency=1` | PASS, 604 passed, 0 failed, 0 skipped |
| Web build | `flutter build web --release --no-pub` | PASS |
| Python | `python -m unittest discover -s scripts -p 'test_*.py'` | PASS |
| JavaScript | `node --test scripts/test_*.cjs` | PASS, 16 tests |
| Firebase config | `python scripts/verify_firebase_config.py` | PASS |

**Dart test counts.** The branch point `Sihao` reports **532** passing tests.
This branch reports **604**, so M2 adds **72** and no inherited or teammate
test was lost.

**Coverage.** `coverage/lcov.info` records **3,747** of **4,069** lines,
**92.1%**. That is the whole project rather than M2 alone; section 9.4 asks
for the numerator, the denominator, and the percentage.

---

## 8. Commits

| Commit | Subject |
| --- | --- |
| `a2195ff` | Bind a repair plan to the state it was proposed from |
| `bb03dcc` | Add the WolfGuard repair planner |
| `3046703` | Apply confirmed repair plans against live state |

---

## 9. Milestone completion status

Against the six-point rule in section 4:

| Requirement | Status |
| --- | --- |
| 1. User-visible behaviour | Planner and applier complete; the sheet that shows them is M4 |
| 2. Passing owned tests | Done, 72 tests |
| 3. No analyzer or formatter failures | Done |
| 4. One screenshot or short clip | Pending the M4 sheet wiring to these implementations |
| 5. Evidence note | This file |
| 6. Merged commit on the team's branch | Pending review |

---

## 10. Honest limitations

- The before/after preview is only as good as the analyzer behind it. The
  numbers a shopper sees come from M1's engine and are its responsibility.
- A fingerprint is a change detector, not a lock. Nothing stops state from
  changing between the check and the write; the check narrows the window
  rather than closing it.
- `removeLine` is only proposed for a line that cannot be read. A shopper who
  wants a covered item taken out does that through the basket, not through a
  suggested repair.
- Self-pay is a real cost to the shopper. It is proposed because it is the
  only honest repair for unverified evidence, not because it is free, and the
  explanation says so.
- Fixture-driven runs of this flow are **synthetic rehearsal**, not
  participant results.
