/// Binding a repair plan to the exact state it was proposed from.
library;

import '../domain/wolfguard_models.dart';

/// The identity of the basket and allowances a [FixPlan] was built from.
///
/// A plan is only safe to apply against the state it was proposed for.
/// Between the preview opening and the shopper confirming, another item can be
/// scanned, another device can change the same record, or catalog evidence can
/// be refreshed. Comparing fingerprints is how [FixPlanApplier] notices and
/// refuses, instead of applying a plan whose preview is no longer true.
///
/// The fingerprint itself belongs to the domain: [PreflightRequest.fingerprint]
/// computes it, and the engine copies it into
/// [PreflightReport.requestFingerprint]. This class deliberately adds no
/// second hash of its own, because two implementations of one identity would
/// be two things to keep in step.
abstract final class BasketFingerprint {
  /// The fingerprint of the state [request] describes.
  static String of(PreflightRequest request) => request.fingerprint;

  /// Whether [plan] was built from the state [current] identifies.
  ///
  /// [current] comes from re-snapshotting live application state the same way
  /// the previewed report was built, evidence included: a request rebuilt
  /// without the evidence the preview used fingerprints differently and would
  /// make every plan look stale.
  static bool matches(FixPlan plan, String current) =>
      plan.sourceFingerprint == current;
}

/// One basket line's position, as named by a `lineKey`.
///
/// `PreflightRequestBuilder` keys each snapshot `index:upc:canonicalCategory`.
/// The planner only passes those keys through, but the applier has to turn one
/// back into the basket line it names, so the shape is a contract rather than
/// an example and both sides go through this class.
///
/// The index alone is never trusted on the way back: the applier also checks
/// the UPC and the category recorded in the key against the line actually
/// sitting at that index.
class BasketLineKey {
  const BasketLineKey({
    required this.index,
    required this.upc,
    required this.basketCategory,
  });

  final int index;
  final String upc;
  final String basketCategory;

  /// The key for the line at [index] of `AppState.basket`.
  ///
  /// This mirrors `PreflightRequestBuilder.fromAppState`, which is where real
  /// keys are issued.
  static String of({
    required int index,
    required String upc,
    required String basketCategory,
  }) => '$index:$upc:$basketCategory';

  /// The parsed key, or null when [key] was not built by [of].
  ///
  /// A UPC never contains a colon, so the first two colons delimit the index
  /// and the UPC, and everything after them belongs to the category.
  static BasketLineKey? parse(String key) {
    final parts = key.split(':');
    if (parts.length < 3) return null;
    final index = int.tryParse(parts[0]);
    if (index == null || index < 0) return null;
    return BasketLineKey(
      index: index,
      upc: parts[1],
      basketCategory: parts.sublist(2).join(':'),
    );
  }

  String get value =>
      of(index: index, upc: upc, basketCategory: basketCategory);
}
