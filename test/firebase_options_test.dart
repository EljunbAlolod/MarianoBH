import 'package:boarding_house_manager/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Firebase options target the MarianoBH project', () {
    final options = DefaultFirebaseOptions.currentPlatform;

    expect(options.projectId, 'marianobh-fcc1b');
    expect(options.appId, '1:200568608153:android:261d8e57b9b807db5e6f08');
  });
}
