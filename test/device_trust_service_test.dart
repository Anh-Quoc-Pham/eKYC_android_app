import 'package:ekyc_app/models/decision_models.dart';
import 'package:ekyc_app/services/device_trust_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingProvider implements DeviceTrustProvider {
  @override
  Future<DeviceTrustSignal> evaluate() async {
    throw StateError('provider crashed');
  }
}

void main() {
  group('DeviceTrust providers', () {
    test('mock provider unknown mode falls back to unavailable', () async {
      const provider = MockDeviceTrustProvider(mode: 'unexpected_mode');
      final signal = await provider.evaluate();

      expect(signal.status, DeviceTrustStatus.unavailable);
      expect(signal.provider, 'mock');
      expect(signal.detail, 'mock_unavailable_for_dev');
    });

    test('play integrity scaffold provider is always unavailable', () async {
      const provider = PlayIntegrityScaffoldProvider();
      final signal = await provider.evaluate();

      expect(signal.status, DeviceTrustStatus.unavailable);
      expect(signal.provider, 'play_integrity_scaffold');
      expect(signal.detail, 'integration_not_configured');
    });

    test(
      'service fail-safe returns unavailable when provider throws',
      () async {
        final service = DeviceTrustService(devProvider: _ThrowingProvider());
        final signal = await service.evaluate();

        expect(signal.status, DeviceTrustStatus.unavailable);
        expect(signal.detail, 'provider_error_fallback');
      },
    );
  });
}
