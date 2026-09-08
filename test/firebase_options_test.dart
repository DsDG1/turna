import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/firebase_options.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android FirebaseOptions match turna-d0d5e google-services.json', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final options = DefaultFirebaseOptions.currentPlatform;
    expect(options.apiKey, 'AIzaSyDL4jPsphIbpZGICOKybt_2dhsYhFtcz1s');
    expect(
      options.appId,
      '1:644663272231:android:4b600e3bcdef21a051bf02',
    );
    expect(options.messagingSenderId, '644663272231');
    expect(options.projectId, 'turna-d0d5e');
    expect(options.storageBucket, 'turna-d0d5e.firebasestorage.app');
    expect(options, same(DefaultFirebaseOptions.android));
  });

  test('currentPlatform throws until other Firebase apps are registered', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      () => DefaultFirebaseOptions.currentPlatform,
      throwsA(isA<UnsupportedError>()),
    );
  });
}
