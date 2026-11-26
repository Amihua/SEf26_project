"""Tests for incremental, evidence-safe M0-WG trial recording."""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from evaluate_wolfguard_trials import TrialDataError, validate_records
from record_wolfguard_trial import (
    append_trial,
    load_recording_dataset,
    main,
    new_dataset,
    pair_counts,
    write_dataset_atomic,
)


def record(
    *,
    trial_id: str = "P01-baseline-WG-S1",
    condition: str = "baseline",
) -> dict[str, object]:
    return {
        "trial_id": trial_id,
        "participant_code": "P01",
        "condition": condition,
        "scenario_id": "WG-S1",
        "elapsed_seconds": 42.5,
        "actionable_issues_resolved": True,
        "unsafe_coverage_claim": False,
        "unknown_acknowledged": True,
        "outside_assistance": False,
        "completed": True,
    }


def cli_args(path: Path, *, condition: str = "baseline") -> list[str]:
    return [
        str(path),
        "--dataset-name",
        "Observed M0 session",
        "--evidence-type",
        "participant",
        "--participant-code",
        "P01",
        "--condition",
        condition,
        "--scenario",
        "WG-S1",
        "--elapsed-seconds",
        "42.5",
        "--actionable-issues-resolved",
        "--no-unsafe-coverage-claim",
        "--unknown-acknowledged",
        "--no-outside-assistance",
        "--completed",
    ]


class RecordingTests(unittest.TestCase):
    def test_new_dataset_keeps_explicit_evidence_provenance(self) -> None:
        dataset = new_dataset("Observed session", "participant")
        self.assertEqual(dataset["schema_version"], 1)
        self.assertEqual(dataset["evidence_type"], "participant")
        self.assertEqual(dataset["records"], [])

    def test_first_half_of_pair_can_be_recorded(self) -> None:
        updated = append_trial(new_dataset("Session", "participant"), record())
        self.assertEqual(len(updated["records"]), 1)
        self.assertEqual(pair_counts(updated["records"]), (0, 1))

    def test_completed_pair_is_accepted_by_the_evaluator(self) -> None:
        dataset = append_trial(new_dataset("Session", "participant"), record())
        dataset = append_trial(
            dataset,
            record(trial_id="P01-wolfguard-WG-S1", condition="wolfguard"),
        )
        self.assertEqual(pair_counts(dataset["records"]), (1, 0))
        validate_records(dataset["records"])

    def test_duplicate_trial_id_is_rejected_without_mutating_dataset(self) -> None:
        dataset = append_trial(new_dataset("Session", "participant"), record())
        before = json.loads(json.dumps(dataset))
        with self.assertRaisesRegex(TrialDataError, "Duplicate trial_id"):
            append_trial(dataset, record())
        self.assertEqual(dataset, before)

    def test_duplicate_pair_condition_is_rejected(self) -> None:
        dataset = append_trial(new_dataset("Session", "participant"), record())
        duplicate = record(trial_id="different-id")
        with self.assertRaisesRegex(TrialDataError, "only one record"):
            append_trial(dataset, duplicate)

    def test_atomic_write_round_trip_supports_incomplete_pair(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "session.json"
            dataset = append_trial(new_dataset("Session", "participant"), record())
            write_dataset_atomic(destination, dataset)
            self.assertEqual(load_recording_dataset(destination), dataset)
            self.assertEqual(list(Path(directory).glob("*.tmp")), [])

    def test_cli_creates_participant_dataset_and_reports_pending_pair(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "session.json"
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = main(cli_args(destination))
            self.assertEqual(exit_code, 0)
            self.assertIn("pending pairs: 1", stdout.getvalue())
            dataset = load_recording_dataset(destination)
            self.assertEqual(dataset["evidence_type"], "participant")

    def test_cli_duplicate_does_not_overwrite_existing_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "session.json"
            self.assertEqual(main(cli_args(destination)), 0)
            before = destination.read_bytes()
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                exit_code = main(cli_args(destination))
            self.assertEqual(exit_code, 2)
            self.assertIn("Duplicate trial_id", stderr.getvalue())
            self.assertEqual(destination.read_bytes(), before)

    def test_cli_refuses_to_relabel_existing_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "session.json"
            self.assertEqual(main(cli_args(destination)), 0)
            changed = cli_args(destination, condition="wolfguard")
            changed[changed.index("participant")] = "synthetic"
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                exit_code = main(changed)
            self.assertEqual(exit_code, 2)
            self.assertIn("evidence type", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
