import 'dart:convert';
import 'dart:io';

import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';

import 'preflight_builders.dart';

/// Path of the shared synthetic scenario fixture, relative to `Project2/`.
const String scenarioFixturePath = 'test/fixtures/wolfguard_scenarios.json';

/// One decoded scenario from `wolfguard_scenarios.json`.
class PreflightScenario {
  PreflightScenario(this.json)
    : id = json['id'] as String,
      use = json['use'] as String,
      request = PreflightRequest(
        lines: [
          for (final raw in json['lines'] as List)
            _line(raw as Map<String, dynamic>),
        ],
        benefits: {
          for (final entry
              in (json['benefits'] as Map<String, dynamic>).entries)
            entry.key: _benefit(entry.key, entry.value as Map<String, dynamic>),
        },
        evaluatedAt: evaluatedAt,
      );

  final Map<String, dynamic> json;
  final String id;
  final String use;
  final PreflightRequest request;

  Map<String, dynamic> get expected => json['expected'] as Map<String, dynamic>;
  Map<String, dynamic>? get oracle => json['oracle'] as Map<String, dynamic>?;
}

/// The decoded fixture file.
Map<String, dynamic> loadScenarioFile() =>
    jsonDecode(File(scenarioFixturePath).readAsStringSync())
        as Map<String, dynamic>;

/// Every scenario in the fixture, in file order.
List<PreflightScenario> loadScenarios() => [
  for (final raw in loadScenarioFile()['scenarios'] as List)
    PreflightScenario(raw as Map<String, dynamic>),
];

BasketLineSnapshot _line(Map<String, dynamic> json) {
  final evidence = json['evidence'] as Map<String, dynamic>?;
  return BasketLineSnapshot(
    lineKey: json['lineKey'] as String,
    upc: json['upc'] as String,
    name: json['name'] as String,
    basketCategory: json['basketCategory'] as String,
    originalBenefitCategory: json['originalBenefitCategory'] as String?,
    quantity: json['quantity'] as int,
    evidence: evidence == null
        ? null
        : ProductEvidence(
            aplEligible: evidence['aplEligible'] as bool?,
            canonicalCategory: evidence['canonicalCategory'] as String?,
            packageSize: _package(evidence['packageSize']),
            freshness: EvidenceFreshness.values.byName(
              evidence['freshness'] as String,
            ),
            sourceLabel: evidence['sourceLabel'] as String,
          ),
  );
}

BenefitCategorySnapshot _benefit(String category, Map<String, dynamic> json) =>
    BenefitCategorySnapshot(
      category: category,
      allowed: json['allowed'] as int?,
      used: json['used'] as int,
      permittedPackageSize: _package(json['permittedPackageSize']),
      freshness: EvidenceFreshness.values.byName(json['freshness'] as String),
    );

PackageAmount? _package(Object? json) {
  if (json == null) return null;
  final map = json as Map<String, dynamic>;
  return PackageAmount(map['value'] as num, map['unit'] as String);
}
