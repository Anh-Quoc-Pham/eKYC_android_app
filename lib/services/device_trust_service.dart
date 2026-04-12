import '../config/app_config.dart';
import '../models/decision_models.dart';

abstract class DeviceTrustProvider {
  Future<DeviceTrustSignal> evaluate();
}

class DeviceTrustService {
  DeviceTrustService({
    DeviceTrustProvider? devProvider,
    DeviceTrustProvider? productionProvider,
  }) : _devProvider = devProvider,
       _productionProvider = productionProvider;

  final DeviceTrustProvider? _devProvider;
  final DeviceTrustProvider? _productionProvider;

  Future<DeviceTrustSignal> evaluate() async {
    if (AppConfig.environment == AppEnvironment.dev) {
      final provider =
          _devProvider ??
          MockDeviceTrustProvider(mode: AppConfig.deviceTrustMode);
      return _safeEvaluate(provider, providerLabel: 'dev_mock');
    }

    final provider =
        _productionProvider ?? const PlayIntegrityScaffoldProvider();
    return _safeEvaluate(provider, providerLabel: 'prod_scaffold');
  }

  Future<DeviceTrustSignal> _safeEvaluate(
    DeviceTrustProvider provider, {
    required String providerLabel,
  }) async {
    try {
      return await provider.evaluate();
    } catch (_) {
      return DeviceTrustSignal(
        status: DeviceTrustStatus.unavailable,
        provider: providerLabel,
        detail: 'provider_error_fallback',
      );
    }
  }
}

class MockDeviceTrustProvider implements DeviceTrustProvider {
  const MockDeviceTrustProvider({required this.mode});

  final String mode;

  @override
  Future<DeviceTrustSignal> evaluate() async {
    switch (mode) {
      case 'mock_trusted':
        return const DeviceTrustSignal(
          status: DeviceTrustStatus.trusted,
          score: 0.95,
          provider: 'mock',
          detail: 'mock_trusted_for_dev',
        );
      case 'mock_low':
        return const DeviceTrustSignal(
          status: DeviceTrustStatus.low,
          score: 0.35,
          provider: 'mock',
          detail: 'mock_low_for_dev',
        );
      case 'mock_unavailable':
      default:
        return const DeviceTrustSignal(
          status: DeviceTrustStatus.unavailable,
          provider: 'mock',
          detail: 'mock_unavailable_for_dev',
        );
    }
  }
}

class PlayIntegrityScaffoldProvider implements DeviceTrustProvider {
  const PlayIntegrityScaffoldProvider();

  @override
  Future<DeviceTrustSignal> evaluate() async {
    return const DeviceTrustSignal(
      status: DeviceTrustStatus.unavailable,
      provider: 'play_integrity_scaffold',
      detail: 'integration_not_configured',
    );
  }
}
