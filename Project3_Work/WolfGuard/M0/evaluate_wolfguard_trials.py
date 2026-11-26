#!/usr/bin/env python3
"""Score the WolfGuard M0-WG risky-basket evaluation.

This module evaluates recorded trials; it does not simulate a participant or
run WolfBite. Synthetic records can validate this instrument, but only genuine
participant records can support the M0-WG outcome claim.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from statistics import median
from typing import Any

TIME_LIMIT_SECONDS = 60.0
WOLFGUARD_SUCCESS_THRESHOLD_PERCENT = 80.0
IMPROVEMENT_THRESHOLD_POINTS = 20.0

VALID_CONDITIONS = {"baseline", "wolfguard"}
VALID_SCENARIOS = {"WG-S1", "WG-S2"}
VALID_EVIDENCE_TYPES = {"synthetic", "participant", "mixed"}

REQUIRED_RECORD_FIELDS = {
    "trial_id",
    "participant_code",
    "condition",
    "scenario_id",
    "elapsed_seconds",
    "actionable_issues_resolved",
    "unsafe_coverage_claim",
    "unknown_acknowledged",
    "outside_assistance",
    "completed",
}

BOOLEAN_FIELDS = {
    "actionable_issues_resolved",
    "unsafe_coverage_claim",
    "unknown_acknowledged",
    "outside_assistance",
    "completed",
}


class TrialDataError(ValueError):
    """Raised when trial data cannot be scored honestly."""


def load_dataset(path: str | Path) -> dict[str, Any]:
    """Load and validate a complete M0-WG JSON dataset."""

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
    validate_records(records)
    return dataset


def _non_empty_text(record: dict[str, Any], field: str, location: str) -> str:
    value = record[field]
    if not isinstance(value, str) or not value.strip():
        raise TrialDataError(f"{location}.{field} must be a non-empty string.")
    return value.strip()


def validate_records(records: list[Any]) -> None:
    """Validate record types, identifiers, conditions, and paired trials."""

    if not isinstance(records, list) or not records:
        raise TrialDataError("Records must be a non-empty list.")

    seen_trial_ids: set[str] = set()
    pair_conditions: dict[tuple[str, str], set[str]] = {}

    for index, raw_record in enumerate(records):
        location = f"records[{index}]"
        if not isinstance(raw_record, dict):
            raise TrialDataError(f"{location} must be a JSON object.")
        record: dict[str, Any] = raw_record

        missing = REQUIRED_RECORD_FIELDS - record.keys()
        if missing:
            names = ", ".join(sorted(missing))
            raise TrialDataError(f"{location} is missing required fields: {names}.")

        trial_id = _non_empty_text(record, "trial_id", location)
        if trial_id in seen_trial_ids:
            raise TrialDataError(f"Duplicate trial_id: {trial_id}.")
        seen_trial_ids.add(trial_id)

        participant = _non_empty_text(record, "participant_code", location)
        condition = record["condition"]
        if condition not in VALID_CONDITIONS:
            allowed = ", ".join(sorted(VALID_CONDITIONS))
            raise TrialDataError(
                f"{location}.condition must be one of: {allowed}."
            )

        scenario = _non_empty_text(record, "scenario_id", location)
        if scenario not in VALID_SCENARIOS:
            allowed = ", ".join(sorted(VALID_SCENARIOS))
            raise TrialDataError(
                f"{location}.scenario_id must be one of: {allowed}."
            )

        elapsed = record["elapsed_seconds"]
        if isinstance(elapsed, bool) or not isinstance(elapsed, (int, float)):
            raise TrialDataError(f"{location}.elapsed_seconds must be a number.")
        if not math.isfinite(elapsed) or elapsed < 0:
            raise TrialDataError(
                f"{location}.elapsed_seconds must be finite and non-negative."
            )

        for field in BOOLEAN_FIELDS:
            if not isinstance(record[field], bool):
                raise TrialDataError(f"{location}.{field} must be true or false.")

        key = (participant, scenario)
        conditions = pair_conditions.setdefault(key, set())
        if condition in conditions:
            raise TrialDataError(
                "Each participant/scenario pair may have only one record per "
                f"condition: {participant}/{scenario}/{condition}."
            )
        conditions.add(condition)

    for (participant, scenario), conditions in pair_conditions.items():
        missing_conditions = VALID_CONDITIONS - conditions
        if missing_conditions:
            missing = ", ".join(sorted(missing_conditions))
            raise TrialDataError(
                f"Participant/scenario pair {participant}/{scenario} is missing "
                f"condition(s): {missing}."
            )


def failure_reasons(record: dict[str, Any]) -> list[str]:
    """Return every reason why one trial does not meet M0-WG success."""

    reasons: list[str] = []
    if not record["completed"]:
        reasons.append("trial was not completed")
    if not record["actionable_issues_resolved"]:
        reasons.append("actionable blocked issues remained")
    if record["unsafe_coverage_claim"]:
        reasons.append("unsafe evidence was accepted as covered")
    if not record["unknown_acknowledged"]:
        reasons.append("unknown evidence was not acknowledged")
    if record["elapsed_seconds"] > TIME_LIMIT_SECONDS:
        reasons.append(
            f"elapsed time was {record['elapsed_seconds']:g} seconds "
            f"(limit: {TIME_LIMIT_SECONDS:g})"
        )
    if record["outside_assistance"]:
        reasons.append("outside assistance was used")
    return reasons


def trial_succeeded(record: dict[str, Any]) -> bool:
    """Return true only when every M0-WG success rule is satisfied."""

    return not failure_reasons(record)


def summarize_condition(
    records: list[dict[str, Any]], condition: str
) -> dict[str, Any]:
    """Summarize successes and elapsed time for one condition."""

    selected = [record for record in records if record["condition"] == condition]
    successes = sum(trial_succeeded(record) for record in selected)
    return {
        "condition": condition,
        "successes": successes,
        "total": len(selected),
        "success_rate": successes / len(selected) * 100.0,
        "median_elapsed_seconds": median(
            record["elapsed_seconds"] for record in selected
        ),
    }


def evaluate_records(records: list[dict[str, Any]]) -> dict[str, Any]:
    """Compare WolfGuard with the inherited baseline against both thresholds."""

    validate_records(records)
    baseline = summarize_condition(records, "baseline")
    wolfguard = summarize_condition(records, "wolfguard")
    improvement = wolfguard["success_rate"] - baseline["success_rate"]
    meets_success = (
        wolfguard["success_rate"] >= WOLFGUARD_SUCCESS_THRESHOLD_PERCENT
    )
    meets_improvement = improvement >= IMPROVEMENT_THRESHOLD_POINTS

    failed_trials = [
        {
            "trial_id": record["trial_id"],
            "condition": record["condition"],
            "reasons": failure_reasons(record),
        }
        for record in records
        if not trial_succeeded(record)
    ]

    return {
        "baseline": baseline,
        "wolfguard": wolfguard,
        "improvement_percentage_points": improvement,
        "meets_success_requirement": meets_success,
        "meets_improvement_requirement": meets_improvement,
        "overall_pass": meets_success and meets_improvement,
        "failed_trials": failed_trials,
    }


def _pass_fail(value: bool) -> str:
    return "PASS" if value else "FAIL"


def format_report(dataset: dict[str, Any], evaluation: dict[str, Any]) -> str:
    """Format a human-readable report with thresholds and failure reasons."""

    baseline = evaluation["baseline"]
    wolfguard = evaluation["wolfguard"]
    lines = [
        f"Dataset: {dataset['dataset_name']}",
        f"Evidence type: {dataset['evidence_type'].upper()}",
        "",
        (
            f"Baseline: {baseline['successes']}/{baseline['total']} successful "
            f"({baseline['success_rate']:.1f}%), median "
            f"{baseline['median_elapsed_seconds']:.1f}s"
        ),
        (
            f"WolfGuard: {wolfguard['successes']}/{wolfguard['total']} "
            f"successful ({wolfguard['success_rate']:.1f}%), median "
            f"{wolfguard['median_elapsed_seconds']:.1f}s"
        ),
        (
            "Improvement: "
            f"{evaluation['improvement_percentage_points']:.1f} percentage points"
        ),
        "",
        (
            f"{WOLFGUARD_SUCCESS_THRESHOLD_PERCENT:g}% WolfGuard success "
            "requirement: "
            f"{_pass_fail(evaluation['meets_success_requirement'])}"
        ),
        (
            f"{IMPROVEMENT_THRESHOLD_POINTS:g}-percentage-point improvement "
            "requirement: "
            f"{_pass_fail(evaluation['meets_improvement_requirement'])}"
        ),
        f"Overall result: {_pass_fail(evaluation['overall_pass'])}",
    ]

    failed_trials = evaluation["failed_trials"]
    if failed_trials:
        lines.extend(["", "Failed trials:"])
        for trial in failed_trials:
            lines.append(
                f"- {trial['trial_id']} ({trial['condition']}): "
                + "; ".join(trial["reasons"])
            )

    if dataset["evidence_type"] == "synthetic":
        lines.extend(
            [
                "",
                "Synthetic fixtures validate this instrument only; the participant "
                "outcome claim remains Not Verified.",
            ]
        )
    return "\n".join(lines)


def _json_report(dataset: dict[str, Any], evaluation: dict[str, Any]) -> str:
    payload = {
        "dataset_name": dataset["dataset_name"],
        "evidence_type": dataset["evidence_type"],
        **evaluation,
    }
    return json.dumps(payload, indent=2, sort_keys=True)


def main(argv: list[str] | None = None) -> int:
    """Run the scorer and return 0 pass, 1 threshold fail, or 2 invalid data."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", help="Path to a WolfGuard M0-WG JSON dataset")
    parser.add_argument(
        "--json",
        action="store_true",
        help="print machine-readable JSON instead of the text report",
    )
    args = parser.parse_args(argv)

    try:
        dataset = load_dataset(args.dataset)
        evaluation = evaluate_records(dataset["records"])
    except TrialDataError as error:
        print(f"Invalid trial data: {error}", file=sys.stderr)
        return 2

    print(_json_report(dataset, evaluation) if args.json else format_report(dataset, evaluation))
    return 0 if evaluation["overall_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
