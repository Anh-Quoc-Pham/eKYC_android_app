import '../models/decision_models.dart';

class EkycSession {
  EkycSession._();

  static final EkycSession instance = EkycSession._();

  String cccd = '';
  String fullName = '';
  String dateOfBirth = '';
  String cccdHash = '';

  bool livenessPassed = false;
  bool faceMatchPassed = false;
  double faceMatchScore = 0;

  bool verificationSucceeded = false;
  int verificationStatusCode = 0;
  String verificationMessage = '';
  Map<String, dynamic> verificationPayload = <String, dynamic>{};
  DecisionOutcome? decisionOutcome;

  OcrRiskSignals ocrRiskSignals = const OcrRiskSignals();
  int verificationAttemptCount = 0;
  String correlationId = '';

  DateTime? updatedAt;

  bool get hasOcrData {
    return cccd.isNotEmpty &&
        fullName.isNotEmpty &&
        dateOfBirth.isNotEmpty &&
        cccdHash.isNotEmpty;
  }

  void setOcrData({
    required String cccd,
    required String fullName,
    required String dateOfBirth,
    required String cccdHash,
    OcrRiskSignals ocrRiskSignals = const OcrRiskSignals(),
  }) {
    this.cccd = cccd;
    this.fullName = fullName;
    this.dateOfBirth = dateOfBirth;
    this.cccdHash = cccdHash;
    this.ocrRiskSignals = ocrRiskSignals;
    verificationAttemptCount = 0;
    updatedAt = DateTime.now();
    resetFaceAndVerification();
  }

  void setFaceState({
    required bool livenessPassed,
    required bool faceMatchPassed,
    required double faceMatchScore,
  }) {
    this.livenessPassed = livenessPassed;
    this.faceMatchPassed = faceMatchPassed;
    this.faceMatchScore = faceMatchScore;
    updatedAt = DateTime.now();
  }

  void setVerificationResult({
    required bool succeeded,
    required int statusCode,
    required String message,
    required Map<String, dynamic> payload,
    DecisionOutcome? decision,
  }) {
    verificationSucceeded = succeeded;
    verificationStatusCode = statusCode;
    verificationMessage = message;
    verificationPayload = payload;
    decisionOutcome = decision;
    if (decision != null && decision.correlationId.isNotEmpty) {
      correlationId = decision.correlationId;
    }
    updatedAt = DateTime.now();
  }

  void registerVerificationAttempt() {
    verificationAttemptCount += 1;
    updatedAt = DateTime.now();
  }

  void resetFaceAndVerification() {
    livenessPassed = false;
    faceMatchPassed = false;
    faceMatchScore = 0;

    verificationSucceeded = false;
    verificationStatusCode = 0;
    verificationMessage = '';
    verificationPayload = <String, dynamic>{};
    decisionOutcome = null;
    correlationId = '';
  }

  void clearAll() {
    cccd = '';
    fullName = '';
    dateOfBirth = '';
    cccdHash = '';
    ocrRiskSignals = const OcrRiskSignals();
    verificationAttemptCount = 0;
    correlationId = '';
    updatedAt = null;
    resetFaceAndVerification();
  }
}
