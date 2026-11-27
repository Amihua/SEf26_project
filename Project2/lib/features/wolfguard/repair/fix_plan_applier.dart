import '../../../utils/nutritional_utils.dart';
import '../domain/wolfguard_models.dart';
import '../domain/wolfguard_ports.dart';
import '../engine/preflight_rules.dart';
import 'basket_fingerprint.dart';

/// The slice of application state a confirmed repair plan reads and writes.
///
/// The applier depends on this rather than on `AppState` so that it can be
/// tested without Firebase. `AppState` implements it through the single
/// WolfGuard entry point section 5.5 of the plan permits.
abstract interface class RepairTarget {
  /// Live basket lines, in the shape `AppState.basket` documents.
  List<Map<String, dynamic>> get basket;

  /// Live allowances, in the shape `AppState.balances` documents.
  Map<String, Map<String, dynamic>> get balances;

  /// Replaces basket and balances in one awaited write.
  ///
  /// Returns false when the write failed, in which case the implementation
  /// must leave the previous state in place. The result is awaited precisely
  /// so a failure can be reported instead of lost, which is what the
  /// inherited fire-and-forget mutations do with theirs.
  Future<bool> commitWolfGuardRepair({
    required List<Map<String, dynamic>> basket,
    required Map<String, Map<String, dynamic>> balances,
  });
}

/// Carries out a confirmed [FixPlan] against live application state.
///
/// ## Why this does not call the inherited mutations
///
/// `AppState.incrementItem`, `decrementItem` and `swapItem` cannot satisfy the
/// M2 contract, for three independent reasons:
///
/// 1. `decrementItem` always takes from the `PAID` line for a UPC when one
///    exists, so it cannot target the benefit line a plan names. A covered
///    line and a PAID line sharing a UPC is on the section 9.2 adversarial
///    list.
/// 2. No public mutation moves units from a benefit line to `PAID`, which is
///    exactly what [FixKind.keepAsSelfPay] has to do.
/// 3. All three start persistence without awaiting it, so a failed write is
///    invisible. FR-5 requires persistence errors to be surfaced, and
///    [ApplyPlanResult.persistenceFailed] exists to carry them.
///
/// So a confirmed plan becomes one projected basket and one projected balance
/// map, committed together through [RepairTarget]. Every action lands or none
/// does.
///
/// ## What `used` means here
///
/// `AppState` counts basket contents in `balances[category]['used']`, so a
/// removal or a reduction gives units back and a self-pay move shifts them
/// between two rows. That is the raw counter, not the headroom reading
/// `PreflightRequestBuilder` hands the planner; each side mirrors its own
/// source.
final class WolfGuardFixPlanApplier implements FixPlanApplier {
  /// [snapshot] re-reads live state as a [PreflightRequest], built exactly the
  /// way the previewed report was built, catalog evidence included. Its
  /// fingerprint is what a plan is checked against, so a snapshot assembled
  /// differently from the preview would make every plan look stale.
  WolfGuardFixPlanApplier({
    required RepairTarget target,
    required PreflightRequest Function() snapshot,
  }) : _target = target,
       _snapshot = snapshot;

  final RepairTarget _target;
  final PreflightRequest Function() _snapshot;

  /// The inherited clamp on a used counter, mirrored so a repair cannot push
  /// a balance somewhere the inherited mutations never could.
  static const int _maxUsed = 999;

  /// The apply currently running, so a double tap executes at most once.
  Future<ApplyPlanResult>? _inFlight;

  /// The plan [_inFlight] is applying.
  String? _inFlightPlanId;

  @override
  Future<ApplyPlanResult> apply(FixPlan plan) {
    final running = _inFlight;
    if (running != null) {
      // FR-5: rapid repeated taps execute at most once. A second tap on the
      // same plan joins the first attempt and reports its result, so the UI
      // still hears what happened. A different plan cannot be interleaved
      // with one already in flight.
      return _inFlightPlanId == plan.planId
          ? running
          : Future.value(ApplyPlanResult.stalePlan);
    }
    final attempt = _apply(plan).whenComplete(() {
      _inFlight = null;
      _inFlightPlanId = null;
    });
    _inFlight = attempt;
    _inFlightPlanId = plan.planId;
    return attempt;
  }

  Future<ApplyPlanResult> _apply(FixPlan plan) async {
    // The basket must still be the one the shopper previewed.
    if (!BasketFingerprint.matches(plan, BasketFingerprint.of(_snapshot()))) {
      return ApplyPlanResult.stalePlan;
    }

    // An empty plan has nothing to confirm, so it writes nothing. Reporting
    // success is honest: the basket already looks the way the plan said.
    if (plan.actions.isEmpty) return ApplyPlanResult.applied;

    final projection = _project(plan);
    if (projection == null) return ApplyPlanResult.unsupportedAction;

    final committed = await _target.commitWolfGuardRepair(
      basket: projection.basket,
      balances: projection.balances,
    );
    return committed
        ? ApplyPlanResult.applied
        : ApplyPlanResult.persistenceFailed;
  }

  /// The basket and balances the plan describes, or null when the plan holds
  /// an action this applier cannot carry out.
  ///
  /// Live state is only read here; nothing is written until the commit.
  _Projection? _project(FixPlan plan) {
    final working = _target.basket
        .map<Map<String, dynamic>?>(Map<String, dynamic>.from)
        .toList();
    final usedDelta = <String, int>{};
    final touched = <int>{};

    for (final action in plan.actions) {
      final key = BasketLineKey.parse(action.lineKey);
      if (key == null) return null;
      if (key.index >= working.length) return null;
      if (!touched.add(key.index)) return null;

      final item = working[key.index];
      if (item == null) return null;
      // The key has to name the line it points at. The fingerprint check
      // already proved the basket is unchanged, so a mismatch means the key
      // did not come from PreflightRequestBuilder.
      if ((item['upc'] ?? '').toString() != key.upc) return null;
      final category = PreflightCategories.canonical(item['category']);
      if (category != PreflightCategories.canonical(key.basketCategory)) {
        return null;
      }

      final quantity = item['qty'];
      if (quantity is! int || quantity <= 0) return null;

      switch (action.kind) {
        case FixKind.removeLine:
          working[key.index] = null;
          _addDelta(usedDelta, category, -quantity);

        case FixKind.reduceQuantity:
          final target = action.targetQuantity;
          // Reducing to zero or below is a removal, and reducing upwards is
          // not a reduction. Either means the plan and the applier disagree.
          if (target == null || target <= 0 || target >= quantity) return null;
          item['qty'] = target;
          _addDelta(usedDelta, category, target - quantity);

        case FixKind.keepAsSelfPay:
          // PAID is a payment classification, so the benefit category the
          // line came from is kept for later help and reporting.
          if (category == wolfGuardPaidCategory) return null;
          item['original_benefit_category'] =
              (item['original_benefit_category'] ?? category).toString();
          item['category'] = wolfGuardPaidCategory;
          _addDelta(usedDelta, category, -quantity);
          _addDelta(usedDelta, wolfGuardPaidCategory, quantity);

        case FixKind.replaceProduct:
          final replacement = action.replacement;
          if (replacement == null) return null;
          if (replacement.upc.trim().isEmpty) return null;
          if (replacement.upc == item['upc']) return null;
          // A swap keeps the line's category and quantity, so no allowance
          // moves. Nutrition belongs to the product and the catalog carries
          // none, so it becomes unknown rather than the previous product's.
          item['upc'] = replacement.upc;
          item['name'] = replacement.name;
          item['nutrition'] = NutritionalUtils.unknownNutrition;
      }
    }

    return _Projection(
      basket: _compact(working),
      balances: _applyDeltas(usedDelta),
    );
  }

  /// Drops removed lines and merges lines that now describe the same product
  /// in the same category, which is how the inherited mutations keep one line
  /// per product and category.
  List<Map<String, dynamic>> _compact(List<Map<String, dynamic>?> working) {
    final result = <Map<String, dynamic>>[];
    final indexByIdentity = <String, int>{};
    for (final item in working) {
      if (item == null) continue;
      final identity =
          '${item['upc']}\u001f'
          '${PreflightCategories.canonical(item['category'])}';
      final existing = indexByIdentity[identity];
      if (existing == null) {
        indexByIdentity[identity] = result.length;
        result.add(item);
        continue;
      }
      final merged = result[existing];
      final left = merged['qty'];
      final right = item['qty'];
      merged['qty'] = (left is int ? left : 0) + (right is int ? right : 0);
    }
    return result;
  }

  /// Live balances with the plan's changes applied, as a fresh map.
  ///
  /// A category a plan moves units into may not have a row yet. `PAID` is
  /// uncapped in the inherited model, which is why a created row carries a
  /// null allowance, exactly as `AppState._deriveAllowed` would.
  Map<String, Map<String, dynamic>> _applyDeltas(Map<String, int> usedDelta) {
    final balances = <String, Map<String, dynamic>>{
      for (final entry in _target.balances.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    usedDelta.forEach((category, delta) {
      final row = balances.putIfAbsent(
        category,
        () => <String, dynamic>{'allowed': null, 'used': 0},
      );
      final used = row['used'];
      row['used'] = ((used is int ? used : 0) + delta).clamp(0, _maxUsed);
    });
    return balances;
  }

  static void _addDelta(Map<String, int> deltas, String category, int change) {
    deltas[category] = (deltas[category] ?? 0) + change;
  }
}

/// The state a confirmed plan produces, before it is committed.
class _Projection {
  const _Projection({required this.basket, required this.balances});

  final List<Map<String, dynamic>> basket;
  final Map<String, Map<String, dynamic>> balances;
}
