#!/usr/bin/env python3
"""Append one observed trial to a WolfGuard M0-WG recording dataset."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

from evaluate_wolfguard_trials import (
    TrialDataError,
    VALID_CONDITIONS,
    VALID_EVIDENCE_TYPES,
    VALID_SCENARIOS,
    validate_trial_record,
)


def new_dataset(dataset_name: str, evidence_type: str) -> dict[str, Any]:
    """Create an empty recording container with explicit evidence provenance."""

    if not dataset_name.strip():
        raise TrialDataError("The dataset must have a non-empty dataset_name.")
    if evidence_type not in VALID_EVIDENCE_TYPES:
        allowed = ", ".join(sorted(VALID_EVIDENCE_TYPES))
        raise TrialDataError(f"Dataset evidence_type must be one of: {allowed}.")
    return {
        "schema_version": 1,
        "dataset_name": dataset_name.strip(),
        "evidence_type": evidence_type,
        "records": [],
    }


def load_recording_dataset(path: str | Path) -> dict[str, Any]:
    """Load a recording dataset, including one with an incomplete pair."""

    dataset_path = Path(path)
    try:
        with dataset_path.open(encoding="utf-8") as input_file:
            dataset = json.load(input_file)
    except FileNotFoundError as error:
        raise TrialDataError(f"Dataset not found: {dataset_path}") from error
    except json.JSONDecodeError as error:
        raise TrialDataError(
            f"Invalid JSON in {dataset_path}: line {error.lineno}, "
            f"column {error.colno}."
        ) from error

    if not isinstance(dataset, dict):
        raise TrialDataError("The dataset must be a JSON object.")
    if dataset.get("schema_version") != 1:
        raise TrialDataError("The dataset schema_version must be 1.")

    name = dataset.get("dataset_name")
    if not isinstance(name, str) or not name.strip():
        raise TrialDataError("The dataset must have a non-empty dataset_name.")
    evidence_type = dataset.get("evidence_type")
    if evidence_type not in VALID_EVIDENCE_TYPES:
        allowed = ", ".join(sorted(VALID_EVIDENCE_TYPES))
        raise TrialDataError(f"Dataset evidence_type must be one of: {allowed}.")

    records = dataset.get("records")
    if not isinstance(records, list):
        raise TrialDataError("Records must be a list while trials are recorded.")
    for index, record in enumerate(records):
        validate_trial_record(record, index=index)
    return dataset


def append_trial(
    dataset: dict[str, Any], record: dict[str, Any]
) -> dict[str, Any]:
    """Return a copy with one valid, non-duplicate trial appended."""

    records = dataset.get("records")
    if not isinstance(records, list):
        raise TrialDataError("Records must be a list while trials are recorded.")
    validate_trial_record(record, index=len(records))

    trial_id = str(record["trial_id"]).strip()
    participant = str(record["participant_code"]).strip()
    scenario = str(record["scenario_id"]).strip()
    condition = record["condition"]
    for existing in records:
        if str(existing["trial_id"]).strip() == trial_id:
            raise TrialDataError(f"Duplicate trial_id: {trial_id}.")
        same_pair_condition = (
            str(existing["participant_code"]).strip() == participant
            and str(existing["scenario_id"]).strip() == scenario
            and existing["condition"] == condition
        )
        if same_pair_condition:
            raise TrialDataError(
                "Each participant/scenario pair may have only one record per "
                f"condition: {participant}/{scenario}/{condition}."
            )

    return {**dataset, "records": [*records, dict(record)]}


def pair_counts(records: list[dict[str, Any]]) -> tuple[int, int]:
    """Return complete and pending participant/scenario pair counts."""

    pairs: dict[tuple[str, str], set[str]] = {}
    for record in records:
        key = (
            str(record["participant_code"]).strip(),
            str(record["scenario_id"]).strip(),
        )
        pairs.setdefault(key, set()).add(str(record["condition"]))
    complete = sum(conditions == VALID_CONDITIONS for conditions in pairs.values())
    return complete, len(pairs) - complete


def write_dataset_atomic(path: str | Path, dataset: dict[str, Any]) -> None:
    """Write JSON in the destination directory, then atomically replace it."""

    destination = Path(path)
    if not destination.parent.is_dir():
        raise TrialDataError(
            f"Destination directory does not exist: {destination.parent}"
        )

    temporary_path: Path | None = None
    try:
        descriptor, raw_path = tempfile.mkstemp(
            prefix=f".{destination.name}.",
            suffix=".tmp",
            dir=destination.parent,
            text=True,
        )
        temporary_path = Path(raw_path)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output_file:
            json.dump(dataset, output_file, indent=2, sort_keys=True)
            output_file.write("\n")
            output_file.flush()
            os.fsync(output_file.fileno())
        os.replace(temporary_path, destination)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", help="JSON dataset to create or append")
    parser.add_argument("--dataset-name", required=True)
    parser.add_argument(
        "--evidence-type",
        required=True,
        choices=sorted(VALID_EVIDENCE_TYPES),
        help="participant for observed trials; synthetic for instrument checks",
    )
    parser.add_argument("--participant-code", required=True)
    parser.add_argument("--condition", required=True, choices=sorted(VALID_CONDITIONS))
    parser.add_argument("--scenario", required=True, choices=sorted(VALID_SCENARIOS))
    parser.add_argument("--elapsed-seconds", required=True, type=float)
    parser.add_argument("--trial-id")
    parser.add_argument(
        "--actionable-issues-resolved",
        action=argparse.BooleanOptionalAction,
        required=True,
    )
    parser.add_argument(
        "--unsafe-coverage-claim",
        action=argparse.BooleanOptionalAction,
        required=True,
    )
    parser.add_argument(
        "--unknown-acknowledged",
        action=argparse.BooleanOptionalAction,
        required=True,
    )
    parser.add_argument(
        "--outside-assistance",
        action=argparse.BooleanOptionalAction,
        required=True,
    )
    parser.add_argument(
        "--completed",
        action=argparse.BooleanOptionalAction,
        required=True,
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Record one trial, returning 0 on success or 2 for unsafe input."""

    args = _parser().parse_args(argv)
    destination = Path(args.dataset)
    try:
        if destination.exists():
            dataset = load_recording_dataset(destination)
            if dataset["dataset_name"] != args.dataset_name.strip():
                raise TrialDataError(
                    "The supplied dataset name does not match the existing file."
                )
            if dataset["evidence_type"] != args.evidence_type:
                raise TrialDataError(
                    "The supplied evidence type does not match the existing file."
                )
        else:
            dataset = new_dataset(args.dataset_name, args.evidence_type)

        trial_id = args.trial_id or (
            f"{args.participant_code}-{args.condition}-{args.scenario}"
        )
        record = {
            "trial_id": trial_id,
            "participant_code": args.participant_code,
            "condition": args.condition,
            "scenario_id": args.scenario,
            "elapsed_seconds": args.elapsed_seconds,
            "actionable_issues_resolved": args.actionable_issues_resolved,
            "unsafe_coverage_claim": args.unsafe_coverage_claim,
            "unknown_acknowledged": args.unknown_acknowledged,
            "outside_assistance": args.outside_assistance,
            "completed": args.completed,
        }
        updated = append_trial(dataset, record)
        write_dataset_atomic(destination, updated)
    except (OSError, TrialDataError) as error:
        print(f"Trial was not recorded: {error}", file=sys.stderr)
        return 2

    complete, pending = pair_counts(updated["records"])
    print(
        f"Recorded {trial_id} in {destination}. "
        f"Complete pairs: {complete}; pending pairs: {pending}."
    )
    if pending:
        print("The dataset is not score-ready until every pair is complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
