from pathlib import Path
import sys

# Ensure backend modules are importable when tests are run from repo root.
sys.path.append(str(Path(__file__).resolve().parents[1]))

from integrity_verifier import (  # noqa: E402
    IntegrityVerifierMode,
    IntegrityVerifierSettings,
    IntegrityVerificationStatus,
    verify_play_integrity,
)


def _mock_settings() -> IntegrityVerifierSettings:
    return IntegrityVerifierSettings(
        mode=IntegrityVerifierMode.MOCK,
        backend_env='dev',
        android_package_name='com.aq.ekyc.ekyc_app',
        credentials_file='',
        credentials_json='',
        request_timeout_seconds=8.0,
        allow_basic_integrity=False,
        require_licensed_app=True,
    )


def _google_settings() -> IntegrityVerifierSettings:
    return IntegrityVerifierSettings(
        mode=IntegrityVerifierMode.GOOGLE,
        backend_env='staging',
        android_package_name='com.aq.ekyc.ekyc_app',
        credentials_file='unused-in-unit-test',
        credentials_json='',
        request_timeout_seconds=8.0,
        allow_basic_integrity=False,
        require_licensed_app=True,
    )


def _trusted_google_payload(request_hash: str) -> dict:
    return {
        'tokenPayloadExternal': {
            'requestDetails': {
                'requestHash': request_hash,
                'requestPackageName': 'com.aq.ekyc.ekyc_app',
            },
            'appIntegrity': {'appRecognitionVerdict': 'PLAY_RECOGNIZED'},
            'deviceIntegrity': {
                'deviceRecognitionVerdict': ['MEETS_DEVICE_INTEGRITY'],
            },
            'accountDetails': {'appLicensingVerdict': 'LICENSED'},
        },
    }


def test_mock_trusted_token_maps_to_trusted_result():
    result = verify_play_integrity(
        evidence={'integrity_token': 'mock_trusted_token'},
        correlation_id='corr-integrity-001',
        expected_request_hash='hash-001',
        settings=_mock_settings(),
    )

    assert result.status == IntegrityVerificationStatus.TRUSTED
    assert result.to_device_trust_signal()['status'] == 'trusted'


def test_mock_invalid_token_maps_to_low_trust_signal():
    result = verify_play_integrity(
        evidence={'integrity_token': 'mock_invalid_token'},
        correlation_id='corr-integrity-002',
        expected_request_hash='hash-002',
        settings=_mock_settings(),
    )

    assert result.status == IntegrityVerificationStatus.INVALID
    assert result.to_device_trust_signal()['status'] == 'low'


def test_non_dev_rejects_mock_mode_as_configuration_error():
    settings = _mock_settings()
    settings.backend_env = 'prod'

    result = verify_play_integrity(
        evidence={'integrity_token': 'mock_trusted_token'},
        correlation_id='corr-integrity-003',
        expected_request_hash='hash-003',
        settings=settings,
    )

    assert result.status == IntegrityVerificationStatus.CONFIGURATION_ERROR
    assert result.to_device_trust_signal()['status'] == 'unavailable'


def test_google_mode_matching_payload_maps_to_trusted():
    expected_hash = 'hash-google-001'

    def decoder(_token: str, _settings: IntegrityVerifierSettings):
        return _trusted_google_payload(expected_hash)

    result = verify_play_integrity(
        evidence={'integrity_token': 'real_token_placeholder'},
        correlation_id='corr-integrity-004',
        expected_request_hash=expected_hash,
        settings=_google_settings(),
        decoder=decoder,
    )

    assert result.status == IntegrityVerificationStatus.TRUSTED
    assert result.to_device_trust_signal()['status'] == 'trusted'


def test_google_mode_hash_mismatch_maps_to_invalid():
    def decoder(_token: str, _settings: IntegrityVerifierSettings):
        return _trusted_google_payload('different_hash')

    result = verify_play_integrity(
        evidence={'integrity_token': 'real_token_placeholder'},
        correlation_id='corr-integrity-005',
        expected_request_hash='expected_hash',
        settings=_google_settings(),
        decoder=decoder,
    )

    assert result.status == IntegrityVerificationStatus.INVALID
    assert result.to_device_trust_signal()['status'] == 'low'


def test_google_mode_missing_token_transient_category_is_retryable():
    result = verify_play_integrity(
        evidence={'error_category': 'transient_error', 'error_code': '-3'},
        correlation_id='corr-integrity-006',
        expected_request_hash='hash-006',
        settings=_google_settings(),
    )

    assert result.status == IntegrityVerificationStatus.TRANSIENT_ERROR
    assert result.retryable is True
    assert result.to_device_trust_signal()['status'] == 'unavailable'
