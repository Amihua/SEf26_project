// Runs the complete offline WolfGuard rehearsal journey with the integration
// test binding used by real devices and desktop builds.
//
//   flutter test integration_test/wolfguard_demo_test.dart -d <device>
//
// The journey uses injected fake ports. It never contacts Firebase, a camera,
// a retailer, or an official benefit account, and it does not claim that the
// production AppState adapter has been integrated.
import 'package:integration_test/integration_test.dart';

import '../test/e2e/wolfguard_journey_test.dart' as wolfguard_journey;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  wolfguard_journey.main();
}
