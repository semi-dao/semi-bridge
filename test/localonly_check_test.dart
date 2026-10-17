import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/storage_service.dart';
import 'package:bridge_app/services/provider_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('localOnly + storage provider=openai → resolveDefault 仍回 local', () async {
    SharedPreferences.setMockInitialValues({
      'local_only_mode': true,
      'flutter.provider': 'openai',  // 明選雲端
    });
    expect(await StorageService.getLocalOnly(), true);
    final r = await ProviderRouter.instance.resolveDefault();
    expect(r.target, RoutedTarget.local);
    expect(r.providerId, 'local');
  });
}
