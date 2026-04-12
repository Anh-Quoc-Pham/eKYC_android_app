import 'package:ekyc_app/models/decision_models.dart';
import 'package:ekyc_app/services/device_trust_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingProvider implements DeviceTrustProvider {
  @override
  Future<DeviceTrustSignal> evaluate({required String requestHash}) async {
    throw StateError('provider crashed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'ekyc/play_integrity_test';
  const requestHash =
      'abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abcd';
  const cloudProjectNumber = 1234567890123;
  const channel = MethodChannel(channelName);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('DeviceTrust providers', () {
    test('mock provider unknown mode falls back to unavailable', () async {
      const provider = MockDeviceTrustProvider(mode: 'unexpected_mode');
      final signal = await provider.evaluate(requestHash: requestHash);

      expect(signal.status, DeviceTrustStatus.unavailable);
      expect(signal.provider, 'mock');
      expect(signal.detail, 'mock_unavailable_for_dev');
      expect(signal.requestHash, requestHash);
    });

    test('play integrity scaffold provider is always unavailable', () async {
      const provider = PlayIntegrityScaffoldProvider();
      final signal = await provider.evaluate(requestHash: requestHash);

      expect(signal.status, DeviceTrustStatus.unavailable);
      expect(signal.provider, 'play_integrity_scaffold');
      expect(signal.detail, 'integration_not_configured');
      expect(signal.errorCategory, 'configuration_error');
    });

    test(
      'service fail-safe returns unavailable when provider throws',
      () async {
        final service = DeviceTrustService(devProvider: _ThrowingProvider());
        final signal = await service.evaluate(requestHash: requestHash);

        expect(signal.status, DeviceTrustStatus.unavailable);
        expect(signal.detail, 'provider_error_fallback');
      },
    );

    test('method channel provider returns token evidence on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'prepareProvider') {
              return <String, dynamic>{
                'ok': true,
                'detail': 'provider_prepared',
              };
            }
            if (call.method == 'requestToken') {
              return <String, dynamic>{
                'ok': true,
                'detail': 'token_issued',
                'token': 'native_play_integrity_token',
              };
            }
            return null;
          });

      final provider = PlayIntegrityMethodChannelProvider(
        cloudProjectNumber: cloudProjectNumber,
        channelName: channelName,
        methodChannel: channel,
      );

      final signal = await provider.evaluate(requestHash: requestHash);
      expect(signal.status, DeviceTrustStatus.unknown);
      expect(signal.integrityToken, 'native_play_integrity_token');
      expect(signal.requestHash, requestHash);
      expect(signal.tokenSource, 'play_integrity_standard');
    });

    test('method channel provider maps transient error as retryable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'prepareProvider') {
              return <String, dynamic>{
                'ok': true,
                'detail': 'provider_prepared',
              };
            }
            if (call.method == 'requestToken') {
              return <String, dynamic>{
                'ok': false,
                'detail': 'transient_integrity_error',
                'errorCategory': 'transient_error',
                'retryable': true,
                'errorCode': '-3',
              };
            }
            return null;
          });

      final provider = PlayIntegrityMethodChannelProvider(
        cloudProjectNumber: cloudProjectNumber,
        channelName: channelName,
        methodChannel: channel,
      );

      final signal = await provider.evaluate(requestHash: requestHash);
      expect(signal.status, DeviceTrustStatus.unavailable);
      expect(signal.errorCategory, 'transient_error');
      expect(signal.retryable, isTrue);
      expect(signal.errorCode, '-3');
    });
  });
}
