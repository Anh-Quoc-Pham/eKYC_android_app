import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  OcrResult({this.cccd, this.fullName, this.dateOfBirth});

  final String? cccd;
  final String? fullName;
  final String? dateOfBirth;

  bool get isComplete =>
      cccd != null &&
      cccd!.isNotEmpty &&
      fullName != null &&
      fullName!.isNotEmpty &&
      dateOfBirth != null &&
      dateOfBirth!.isNotEmpty;
}

class OcrService {
  OcrService()
    : _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _textRecognizer;

  static final RegExp _cccdRegex = RegExp(r'\b(?:\d{9}|\d{12})\b');
  static final RegExp _dobRegex = RegExp(
    r'\b(?:0[1-9]|[12]\d|3[01])[\/-](?:0[1-9]|1[0-2])[\/-](?:19|20)\d{2}\b',
  );
  static final RegExp _uppercaseNameRegex = RegExp(
    r'^[A-ZÀÁẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬĐÈÉẺẼẸÊẾỀỂỄỆÌÍỈĨỊÒÓỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢÙÚỦŨỤƯỨỪỬỮỰỲÝỶỸỴ ]{4,}$',
  );

  Future<OcrResult> recognize(InputImage inputImage) async {
    final recognizedText = await _textRecognizer.processImage(inputImage);
    final allText = recognizedText.text;
    final lines = _extractLines(recognizedText);

    final cccd = _extractCccd(allText);
    final dob = _extractDateOfBirth(allText);
    final fullName = _extractFullName(lines);

    return OcrResult(cccd: cccd, fullName: fullName, dateOfBirth: dob);
  }

  String? _extractCccd(String input) {
    final match = _cccdRegex.firstMatch(input);
    if (match == null) {
      return null;
    }

    final candidate = match.group(0);
    return candidate;
  }

  String? _extractDateOfBirth(String input) {
    final match = _dobRegex.firstMatch(input);
    if (match == null) {
      return null;
    }

    return match.group(0);
  }

  String? _extractFullName(List<String> lines) {
    final normalizedLines = lines
        .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((line) => line.isNotEmpty)
        .toList();

    for (var i = 0; i < normalizedLines.length; i++) {
      final upperLine = normalizedLines[i].toUpperCase();
      if (!_isNameLabel(upperLine)) {
        continue;
      }

      if (i + 1 < normalizedLines.length) {
        final nextLine = normalizedLines[i + 1].toUpperCase();
        if (_isValidUppercaseName(nextLine)) {
          return nextLine;
        }
      }
    }

    final candidates = normalizedLines
        .map((line) => line.toUpperCase())
        .where(_isValidUppercaseName)
        .toList();

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.first;
  }

  bool _isNameLabel(String line) {
    return line.contains('HO VA TEN') ||
        line.contains('HỌ VÀ TÊN') ||
        line.contains('HỌ TÊN') ||
        line.contains('HO TEN');
  }

  bool _isValidUppercaseName(String value) {
    if (value.contains(RegExp(r'\d'))) {
      return false;
    }

    if (!_uppercaseNameRegex.hasMatch(value)) {
      return false;
    }

    final words = value.split(' ').where((word) => word.isNotEmpty).toList();
    return words.length >= 2;
  }

  List<String> _extractLines(RecognizedText recognizedText) {
    final lines = <String>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        lines.add(line.text);
      }
    }
    return lines;
  }

  static bool isValidCccd(String value) {
    final normalized = value.replaceAll(RegExp(r'\D'), '');
    return _cccdRegex.hasMatch(normalized);
  }

  static String hashCccd(String cccd) {
    final normalized = cccd.replaceAll(RegExp(r'\D'), '');
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
