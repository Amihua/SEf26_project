// Runs the complete offline WolfGuard rehearsal journey and the inherited
// BasketScreen integration checks with the binding used by real devices and
// desktop builds.
//
//   flutter test integration_test/wolfguard_demo_test.dart -d <device>
//
// These checks use fake or explicitly synthetic data. They never contact
// Firebase, a camera, a retailer, or an official benefit account, and they do
// not claim that the production AppState adapter has been integrated.
import 'package:integration_test/integration_test.dart';

import '../test/e2e/wolfguard_journey_test.dart' as wolfguard_journey;
import '../test/features/wolfguard/presentation/wolfguard_basket_screen_integration_test.dart'
    as basket_screen_integration;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  wolfguard_journey.main();
  basket_screen_integration.main();
}
