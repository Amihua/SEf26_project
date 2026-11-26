"""Unit tests for the WolfGuard M0-WG scoring rules."""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from evaluate_wolfguard_trials import (
    TrialDataError,
    evaluate_records,
    failure_reasons,
    format_report,
    load_dataset,
    main,
    trial_succeeded,
    validate_records,
)

M0_DIRECTORY = Path(__file__).resolve().parent
PASSING_DATASET = M0_DIRECTORY / "trial_data" / "passing_example.json"
FAILING_DATASET = M0_DIRECTORY / "trial_data" / "failing_example.json"


def make_record(
    *,
    trial_id: str,
    participant: str = "P01",
    condition: str = "baseline",
    scenario: str = "WG-S1",
    elapsed: float = 30.0,
    resolved: bool = True,
    unsafe: bool = False,
    acknowledged: bool = True,
    assisted: bool = False,
    completed: bool = True,
) -> dict[str, object]:
    return {
        "trial_id": trial_id,
        "participant_code": participant,
        "condition": condition,
        "scenario_id": scenario,
        "elapsed_seconds": elapsed,
        "actionable_issues_resolved": resolved,
        "unsafe_coverage_claim": unsafe,
        "unknown_acknowledged": acknowledged,
        "outside_assistance": assisted,
        "completed": completed,
    }


def paired_records(**baseline_changes: object) -> list[dict[str, object]]:
    baseline = make_record(trial_id="P01-baseline", **baseline_changes)
    wolfguard = make_record(
        trial_id="P01-wolfguard",
        condition="wolfguard",
    )
    return [baseline, wolfguard]


class TrialRuleTests(unittest.TestCase):
    def test_exactly_sixty_seconds_succeeds(self) -> None:
        record = make_record(trial_id="trial", elapsed=60.0)
        self.assertTrue(trial_succeeded(record))

    def test_more_than_sixty_seconds_fails(self) -> None:
        record = make_record(trial_id="trial", elapsed=60.01)
        self.assertFalse(trial_succeeded(record))
        self.assertIn("elapsed time", failure_reasons(record)[0])

    def test_unresolved_issue_fails(self) -> None:
        record = make_record(trial_id="trial", resolved=False)
        self.assertIn("blocked issues", failure_reasons(record)[0])

    def test_unsafe_coverage_claim_fails(self) -> None:
        record = make_record(trial_id="trial", unsafe=True)
        self.assertIn("unsafe evidence", failure_reasons(record)[0])

    def test_unacknowledged_unknown_fails(self) -> None:
        record = make_record(trial_id="trial", acknowledged=False)
        self.assertIn("not acknowledged", failure_reasons(record)[0])

    def test_outside_assistance_fails(self) -> None:
        record = make_record(trial_id="trial", assisted=True)
        self.assertIn("outside assistance", failure_reasons(record)[0])

    def test_incomplete_trial_fails(self) -> None:
        record = make_record(trial_id="trial", completed=False)
        self.assertIn("not completed", failure_reasons(record)[0])

    def test_one_trial_can_report_every_failure_reason(self) -> None:
        record = make_record(
            trial_id="trial",
            elapsed=61.0,
            resolved=False,
            unsafe=True,
            acknowledged=False,
            assisted=True,
            completed=False,
        )
        self.assertEqual(len(failure_reasons(record)), 6)


class ValidationTests(unittest.TestCase):
    def test_missing_required_field_is_rejected(self) -> None:
        records = paired_records()
        del records[0]["completed"]
        with self.assertRaisesRegex(TrialDataError, "completed"):
            validate_records(records)

    def test_duplicate_trial_id_is_rejected(self) -> None:
        records = paired_records()
        records[1]["trial_id"] = records[0]["trial_id"]
        with self.assertRaisesRegex(TrialDataError, "Duplicate trial_id"):
            validate_records(records)

    def test_unknown_condition_is_rejected(self) -> None:
        records = paired_records()
        records[1]["condition"] = "future"
        with self.assertRaisesRegex(TrialDataError, "condition must be one of"):
            validate_records(records)

    def test_unknown_scenario_is_rejected(self) -> None:
        records = paired_records()
        records[0]["scenario_id"] = "WG-UNKNOWN"
        with self.assertRaisesRegex(TrialDataError, "scenario_id"):
            validate_records(records)

    def test_boolean_elapsed_time_is_rejected(self) -> None:
        records = paired_records()
        records[0]["elapsed_seconds"] = True
        with self.assertRaisesRegex(TrialDataError, "must be a number"):
            validate_records(records)

    def test_non_finite_elapsed_time_is_rejected(self) -> None:
        records = paired_records(elapsed=float("inf"))
        with self.assertRaisesRegex(TrialDataError, "finite and non-negative"):
            validate_records(records)

    def test_negative_elapsed_time_is_rejected(self) -> None:
        records = paired_records(elapsed=-1.0)
        with self.assertRaisesRegex(TrialDataError, "finite and non-negative"):
            validate_records(records)

    def test_non_boolean_outcome_is_rejected(self) -> None:
        records = paired_records()
        records[0]["completed"] = 1
        with self.assertRaisesRegex(TrialDataError, "must be true or false"):
            validate_records(records)

    def test_unpaired_condition_is_rejected(self) -> None:
        with self.assertRaisesRegex(TrialDataError, "missing condition"):
            validate_records([make_record(trial_id="baseline")])

    def test_duplicate_pair_condition_is_rejected(self) -> None:
        records = paired_records()
        records.append(make_record(trial_id="second-baseline"))
        with self.assertRaisesRegex(TrialDataError, "only one record"):
            validate_records(records)


class EvaluationTests(unittest.TestCase):
    def test_thresholds_use_percentage_points(self) -> None:
        records: list[dict[str, object]] = []
        for index in range(5):
            participant = f"P{index + 1:02d}"
            records.append(
                make_record(
                    trial_id=f"{participant}-baseline",
                    participant=participant,
                    resolved=index < 3,
                )
            )
            records.append(
                make_record(
                    trial_id=f"{participant}-wolfguard",
                    participant=participant,
                    condition="wolfguard",
                    resolved=index < 4,
                )
            )

        result = evaluate_records(records)
        self.assertEqual(result["baseline"]["success_rate"], 60.0)
        self.assertEqual(result["wolfguard"]["success_rate"], 80.0)
        self.assertEqual(result["improvement_percentage_points"], 20.0)
        self.assertTrue(result["overall_pass"])

    def test_median_elapsed_time_is_reported_by_condition(self) -> None:
        records = paired_records(elapsed=20.0)
        records[1]["elapsed_seconds"] = 10.0
        result = evaluate_records(records)
        self.assertEqual(result["baseline"]["median_elapsed_seconds"], 20.0)
        self.assertEqual(result["wolfguard"]["median_elapsed_seconds"], 10.0)

    def test_failed_trials_include_all_reasons(self) -> None:
        result = evaluate_records(paired_records(resolved=False, assisted=True))
        self.assertEqual(len(result["failed_trials"]), 1)
        self.assertEqual(len(result["failed_trials"][0]["reasons"]), 2)


class DatasetAndCliTests(unittest.TestCase):
    def test_known_passing_fixture_meets_both_thresholds(self) -> None:
        dataset = load_dataset(PASSING_DATASET)
        result = evaluate_records(dataset["records"])
        self.assertTrue(result["overall_pass"])
        self.assertEqual(result["baseline"]["success_rate"], 60.0)
        self.assertEqual(result["wolfguard"]["success_rate"], 80.0)

    def test_known_failing_fixture_misses_both_thresholds(self) -> None:
        dataset = load_dataset(FAILING_DATASET)
        result = evaluate_records(dataset["records"])
        self.assertFalse(result["overall_pass"])
        self.assertFalse(result["meets_success_requirement"])
        self.assertFalse(result["meets_improvement_requirement"])

    def test_text_report_labels_synthetic_evidence(self) -> None:
        dataset = load_dataset(PASSING_DATASET)
        report = format_report(dataset, evaluate_records(dataset["records"]))
        self.assertIn("Evidence type: SYNTHETIC", report)
        self.assertIn("participant outcome claim remains Not Verified", report)

    def test_loader_rejects_unknown_evidence_type(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "dataset.json"
            path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "dataset_name": "bad source",
                        "evidence_type": "guessed",
                        "records": paired_records(),
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(TrialDataError, "evidence_type"):
                load_dataset(path)

    def test_cli_returns_zero_for_passing_fixture(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exit_code = main([str(PASSING_DATASET)])
        self.assertEqual(exit_code, 0)
        self.assertIn("Overall result: PASS", output.getvalue())

    def test_cli_returns_one_for_failing_fixture(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exit_code = main([str(FAILING_DATASET)])
        self.assertEqual(exit_code, 1)
        self.assertIn("Overall result: FAIL", output.getvalue())

    def test_cli_json_output_is_machine_readable(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exit_code = main([str(PASSING_DATASET), "--json"])
        payload = json.loads(output.getvalue())
        self.assertEqual(exit_code, 0)
        self.assertEqual(payload["evidence_type"], "synthetic")
        self.assertTrue(payload["overall_pass"])


if __name__ == "__main__":
    unittest.main()
