# WolfGuard M0-WG Evaluation Protocol

M0-WG tests the user-outcome claim defined in the all-in-one plan:

> At least 80% of participants using WolfGuard resolve every actionable blocked
> issue within 60 seconds without outside assistance, and WolfGuard success is
> at least 20 percentage points higher than the inherited flow.

This directory contains an evaluation instrument, not evidence that the claim
is already true. Synthetic fixtures validate the instrument only.

## Files

- `evaluate_wolfguard_trials.py`: validates complete paired data and scores it.
- `record_wolfguard_trial.py`: atomically appends one observed trial.
- `test_evaluate_wolfguard_trials.py`: scorer and schema tests.
- `test_record_wolfguard_trial.py`: recorder and data-integrity tests.
- `trial_data/passing_example.json`: known passing synthetic fixture.
- `trial_data/failing_example.json`: known failing synthetic fixture.

## Participant protocol

1. Use participant codes such as `P01`. Never record names, email addresses,
   card data, credentials, or free-text notes that identify a participant.
2. Use the same predefined scenario and oracle for both conditions:
   `baseline` is the inherited basket plus item-level checkout help;
   `wolfguard` is the readiness report, repair preview, and confirmation flow.
3. Do not change the scenario, expected blocked issues, or evidence oracle
   between conditions. Use only `WG-S1` or `WG-S2` from the team fixture.
4. Counterbalance order. Odd participant codes should run baseline first and
   even codes WolfGuard first; reverse that order for the next scenario.
5. Read the same neutral instruction: "Review this basket and make it ready for
   checkout. Tell me when you are finished."
6. Start timing when the participant can first interact with the basket. Stop
   when they declare completion. At 60 seconds, stop the trial and record
   `completed=false` if the task is unfinished.
7. Do not coach, point, answer product questions, or explain controls after the
   timer starts. If assistance occurs, record `outside_assistance=true`.
8. Use the scenario oracle—not participant confidence—to record whether all
   actionable issues were resolved and whether unsafe evidence was claimed as
   covered. Unknown evidence succeeds only when the participant explicitly
   acknowledges that it still requires review.
9. Reset all basket and scenario state before the paired condition.

Each participant/scenario pair must contain exactly one `baseline` and one
`wolfguard` trial. A participant should not evaluate their own authored code
when an external classmate is available.

## Record a trial

Run from this directory. Every Boolean outcome is explicit; omitting one is a
command error.

```sh
python3 record_wolfguard_trial.py trial_data/observed_session.json \
  --dataset-name "WolfGuard observed session 2026-11-26" \
  --evidence-type participant \
  --participant-code P01 \
  --condition baseline \
  --scenario WG-S1 \
  --elapsed-seconds 54.2 \
  --actionable-issues-resolved \
  --no-unsafe-coverage-claim \
  --unknown-acknowledged \
  --no-outside-assistance \
  --completed
```

Use the corresponding `--no-...` form when a Boolean is false. For example,
an unfinished trial uses `--no-completed`. The recorder:

- permits a temporarily incomplete pair while data is being collected;
- rejects duplicate trial IDs and duplicate condition records;
- refuses to relabel an existing dataset's evidence provenance;
- writes through a temporary file and atomically replaces the destination;
- reports how many pairs are complete or still pending.

Do not edit the JSON by hand after collection. Keep observed participant data
out of public commits unless consent and course policy explicitly allow it.

## Verify the instrument

```sh
python3 -m unittest -v \
  test_evaluate_wolfguard_trials.py \
  test_record_wolfguard_trial.py

python3 evaluate_wolfguard_trials.py trial_data/passing_example.json
python3 evaluate_wolfguard_trials.py trial_data/failing_example.json
```

Expected exit codes:

- `0`: valid complete data and both M0-WG thresholds pass;
- `1`: valid complete data but one or both thresholds fail;
- `2`: invalid, incomplete, duplicate, or unreadable data.

The known failing fixture intentionally exits `1`; that is evidence the scorer
rejects a weak result, not a broken test.

## Score observed data

```sh
python3 evaluate_wolfguard_trials.py trial_data/observed_session.json
python3 evaluate_wolfguard_trials.py \
  trial_data/observed_session.json --json
```

Report all of the following without rounding away a failed threshold:

- baseline and WolfGuard success numerator, denominator, and percentage;
- median elapsed seconds for both conditions;
- WolfGuard minus baseline percentage-point improvement;
- separate pass/fail results for 80% success and +20 percentage points;
- evidence type and every failed trial reason.

If genuine participant trials are missing, incomplete, or not consented for
reporting, use this exact conclusion:

> M0-WG instrument verified with synthetic passing and failing fixtures;
> participant outcome claim Not Verified.

The inherited Project 2 M0 remains a separate release gate and result. Never
merge its metric with M0-WG.
