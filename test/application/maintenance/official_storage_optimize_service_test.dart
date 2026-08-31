import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/maintenance/official_storage_optimize_service.dart';

void main() {
  test('force compact fails closed without catalog or paths', () async {
    final result =
        await const OfficialStorageOptimizeService().runForceCompact();
    expect(result.ok, isFalse);
    expect(result.errorCode, 'capability_missing');
    expect(result.completedJobs, 0);
  });
}
