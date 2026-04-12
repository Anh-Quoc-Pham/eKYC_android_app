enum DecisionStatus { pass, review, reject }

enum RetryPolicy {
  immediate,
  userCorrection,
  waitBeforeRetry,
  manualReview,
  noRetry,
}

class ReasonCodes {
  ReasonCodes._();

  static const String ocrLowConfidence = 'OCR_LOW_CONFIDENCE';
  static const String ocrFieldMismatch = 'OCR_FIELD_MISMATCH';
  static const String documentGlare = 'DOCUMENT_GLARE';
  static const String documentBlur = 'DOCUMENT_BLUR';
  static const String documentCropInvalid = 'DOCUMENT_CROP_INVALID';
  static const String faceMismatch = 'FACE_MISMATCH';
  static const String livenessLowConfidence = 'LIVENESS_LOW_CONFIDENCE';
  static const String deviceTrustUnavailable = 'DEVICE_TRUST_UNAVAILABLE';
  static const String deviceTrustLow = 'DEVICE_TRUST_LOW';
  static const String sessionRetryLimit = 'SESSION_RETRY_LIMIT';
  static const String networkInterrupted = 'NETWORK_INTERRUPTED';
  static const String internalReviewRequired = 'INTERNAL_REVIEW_REQUIRED';
  static const String unknownErrorSafeFallback = 'UNKNOWN_ERROR_SAFE_FALLBACK';
}

enum DeviceTrustStatus { trusted, low, unavailable, unknown }

class OcrRiskSignals {
  const OcrRiskSignals({
    this.confidence,
    this.fieldMismatch = false,
    this.glareDetected = false,
    this.blurDetected = false,
    this.cropInvalid = false,
  });

  final double? confidence;
  final bool fieldMismatch;
  final bool glareDetected;
  final bool blurDetected;
  final bool cropInvalid;

  Map<String, dynamic> toJson() {
    return {
      'confidence': confidence,
      'field_mismatch': fieldMismatch,
      'glare_detected': glareDetected,
      'blur_detected': blurDetected,
      'crop_invalid': cropInvalid,
    };
  }

  OcrRiskSignals copyWith({
    double? confidence,
    bool? fieldMismatch,
    bool? glareDetected,
    bool? blurDetected,
    bool? cropInvalid,
  }) {
    return OcrRiskSignals(
      confidence: confidence ?? this.confidence,
      fieldMismatch: fieldMismatch ?? this.fieldMismatch,
      glareDetected: glareDetected ?? this.glareDetected,
      blurDetected: blurDetected ?? this.blurDetected,
      cropInvalid: cropInvalid ?? this.cropInvalid,
    );
  }
}

class FaceRiskSignals {
  const FaceRiskSignals({this.matchScore, this.livenessConfidence});

  final double? matchScore;
  final double? livenessConfidence;

  Map<String, dynamic> toJson() {
    return {
      'match_score': matchScore,
      'liveness_confidence': livenessConfidence,
    };
  }
}

class DeviceTrustSignal {
  const DeviceTrustSignal({
    required this.status,
    this.score,
    this.provider,
    this.detail,
  });

  final DeviceTrustStatus status;
  final double? score;
  final String? provider;
  final String? detail;

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'score': score,
      'provider': provider,
      'detail': detail,
    };
  }

  static const DeviceTrustSignal unavailable = DeviceTrustSignal(
    status: DeviceTrustStatus.unavailable,
    detail: 'device_trust_unavailable',
  );
}

class RetrySignals {
  const RetrySignals({required this.attemptCount, required this.maxAttempts});

  final int attemptCount;
  final int maxAttempts;

  Map<String, dynamic> toJson() {
    return {'attempt_count': attemptCount, 'max_attempts': maxAttempts};
  }
}

class VerificationRiskContext {
  const VerificationRiskContext({
    this.ocr,
    this.face,
    this.deviceTrust,
    this.retry,
    this.networkInterrupted = false,
  });

  final OcrRiskSignals? ocr;
  final FaceRiskSignals? face;
  final DeviceTrustSignal? deviceTrust;
  final RetrySignals? retry;
  final bool networkInterrupted;

  Map<String, dynamic> toJson() {
    return {
      'ocr': ocr?.toJson(),
      'face': face?.toJson(),
      'device_trust': deviceTrust?.toJson(),
      'retry': retry?.toJson(),
      'network_interrupted': networkInterrupted,
    };
  }
}

class DecisionOutcome {
  const DecisionOutcome({
    required this.status,
    required this.reasonCodes,
    required this.userMessageKey,
    required this.retryAllowed,
    required this.retryReason,
    required this.retryPolicy,
    required this.correlationId,
    required this.riskSignals,
    required this.verified,
  });

  final DecisionStatus status;
  final List<String> reasonCodes;
  final String userMessageKey;
  final bool retryAllowed;
  final String retryReason;
  final RetryPolicy retryPolicy;
  final String correlationId;
  final Map<String, dynamic> riskSignals;
  final bool verified;

  bool get isPass => status == DecisionStatus.pass;

  factory DecisionOutcome.fromBackendPayload(
    Map<String, dynamic> payload, {
    required int fallbackStatusCode,
    required String fallbackMessage,
    String fallbackCorrelationId = '',
  }) {
    final verified =
        payload['verified'] as bool? ??
        (fallbackStatusCode >= 200 && fallbackStatusCode < 300);

    final status = _statusFromRaw(
      payload['decision_status']?.toString(),
      verified,
    );
    final reasonCodes = _reasonCodesFromPayload(
      payload,
      fallbackMessage,
      verified,
    );

    final retryPolicy = _retryPolicyFromRaw(
      payload['retry_policy']?.toString(),
    );
    final retryAllowed =
        payload['retry_allowed'] as bool? ?? (status != DecisionStatus.pass);

    final correlationId =
        payload['correlation_id']?.toString() ?? fallbackCorrelationId;

    final userMessageKey =
        payload['user_message_key']?.toString() ??
        _defaultUserMessageKey(status);

    final retryReason =
        payload['retry_reason']?.toString() ??
        (retryAllowed ? 'retry_recommended' : 'no_retry');

    final riskSignals = payload['risk_signals'] is Map<String, dynamic>
        ? payload['risk_signals'] as Map<String, dynamic>
        : <String, dynamic>{};

    return DecisionOutcome(
      status: status,
      reasonCodes: reasonCodes,
      userMessageKey: userMessageKey,
      retryAllowed: retryAllowed,
      retryReason: retryReason,
      retryPolicy: retryPolicy,
      correlationId: correlationId,
      riskSignals: riskSignals,
      verified: verified,
    );
  }

  static DecisionOutcome networkInterrupted({String correlationId = ''}) {
    return DecisionOutcome(
      status: DecisionStatus.review,
      reasonCodes: const [ReasonCodes.networkInterrupted],
      userMessageKey: 'decision.review.network_retry',
      retryAllowed: true,
      retryReason: 'network_interrupted',
      retryPolicy: RetryPolicy.immediate,
      correlationId: correlationId,
      riskSignals: const <String, dynamic>{'network_interrupted': true},
      verified: false,
    );
  }

  static DecisionStatus _statusFromRaw(String? rawStatus, bool verified) {
    switch ((rawStatus ?? '').trim().toUpperCase()) {
      case 'PASS':
        return DecisionStatus.pass;
      case 'REJECT':
        return DecisionStatus.reject;
      case 'REVIEW':
        return DecisionStatus.review;
      default:
        return verified ? DecisionStatus.pass : DecisionStatus.review;
    }
  }

  static List<String> _reasonCodesFromPayload(
    Map<String, dynamic> payload,
    String fallbackMessage,
    bool verified,
  ) {
    final rawCodes = payload['reason_codes'];
    if (rawCodes is List) {
      final parsed = rawCodes
          .map((item) => item.toString())
          .where((code) => code.isNotEmpty)
          .toList(growable: false);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    final reason = payload['reason']?.toString() ?? '';
    final normalizedMessage = fallbackMessage.toLowerCase();
    if (reason == 'rate_limited') {
      return const [ReasonCodes.sessionRetryLimit];
    }

    if (reason == 'network_error' ||
        normalizedMessage.contains('network_error')) {
      return const [ReasonCodes.networkInterrupted];
    }

    if (verified) {
      return const <String>[];
    }

    return const [ReasonCodes.unknownErrorSafeFallback];
  }

  static RetryPolicy _retryPolicyFromRaw(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'IMMEDIATE':
        return RetryPolicy.immediate;
      case 'USER_CORRECTION':
        return RetryPolicy.userCorrection;
      case 'WAIT_BEFORE_RETRY':
        return RetryPolicy.waitBeforeRetry;
      case 'MANUAL_REVIEW':
        return RetryPolicy.manualReview;
      case 'NO_RETRY':
      default:
        return RetryPolicy.noRetry;
    }
  }

  static String _defaultUserMessageKey(DecisionStatus status) {
    switch (status) {
      case DecisionStatus.pass:
        return 'decision.pass';
      case DecisionStatus.review:
        return 'decision.review.generic';
      case DecisionStatus.reject:
        return 'decision.reject.generic';
    }
  }
}
