import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_routes.dart';
import '../app_theme.dart';
import '../models/decision_models.dart';
import '../services/ekyc_session.dart';
import '../services/ocr_service.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  final EkycSession _session = EkycSession.instance;

  late final TextEditingController _cccdController;
  late final TextEditingController _nameController;
  late final TextEditingController _dobController;

  bool _isSaving = false;

  String get _cccdHash {
    final raw = _cccdController.text.trim();
    if (raw.isEmpty || !OcrService.isValidCccd(raw)) {
      return '';
    }
    return OcrService.hashCccd(raw);
  }

  @override
  void initState() {
    super.initState();
    _cccdController = TextEditingController(text: _session.cccd);
    _nameController = TextEditingController(text: _session.fullName);
    _dobController = TextEditingController(text: _session.dateOfBirth);

    _cccdController.addListener(_refreshPreview);
    _nameController.addListener(_refreshPreview);
    _dobController.addListener(_refreshPreview);
  }

  void _refreshPreview() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _cccdController
      ..removeListener(_refreshPreview)
      ..dispose();
    _nameController
      ..removeListener(_refreshPreview)
      ..dispose();
    _dobController
      ..removeListener(_refreshPreview)
      ..dispose();
    super.dispose();
  }

  Future<void> _confirmAndSave() async {
    final rawCccd = _cccdController.text.trim();
    final fullName = _nameController.text.trim().toUpperCase();
    final dateOfBirth = _dobController.text.trim();

    if (!OcrService.isValidCccd(rawCccd)) {
      _showMessage('Số CCCD không hợp lệ. Vui lòng nhập 9 hoặc 12 chữ số.');
      return;
    }

    if (fullName.isEmpty) {
      _showMessage('Họ tên không được để trống.');
      return;
    }

    if (dateOfBirth.isEmpty) {
      _showMessage('Ngày sinh không được để trống.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final normalizedCccd = rawCccd.replaceAll(RegExp(r'\D'), '');
      final cccdHash = OcrService.hashCccd(normalizedCccd);

      final hadOcrSeedData = _session.hasOcrData;
      final fieldMismatch =
          hadOcrSeedData &&
          (_session.cccd != normalizedCccd ||
              _session.fullName != fullName ||
              _session.dateOfBirth != dateOfBirth);

      final ocrSignals = OcrRiskSignals(
        confidence: hadOcrSeedData ? 0.90 : 0.58,
        fieldMismatch: fieldMismatch,
      );

      _session.setOcrData(
        cccd: normalizedCccd,
        fullName: fullName,
        dateOfBirth: dateOfBirth,
        cccdHash: cccdHash,
        ocrRiskSignals: ocrSignals,
      );

      // Privacy-First: lưu cục bộ bằng secure storage, không đẩy dữ liệu thô lên server.
      await _secureStorage.write(key: 'ekyc.cccd', value: normalizedCccd);
      await _secureStorage.write(key: 'ekyc.full_name', value: fullName);
      await _secureStorage.write(key: 'ekyc.date_of_birth', value: dateOfBirth);
      await _secureStorage.write(key: 'ekyc.cccd_hash_sha256', value: cccdHash);
      await _secureStorage.write(
        key: 'ekyc.updated_at',
        value: DateTime.now().toIso8601String(),
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).pushNamed(AppRoutes.face);
    } catch (error) {
      _showMessage('Lưu dữ liệu thất bại: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _goBackToOcr() {
    _session.resetFaceAndVerification();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.ocr, (route) => false);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final pagePadding = AppLayout.pagePadding(context);

    final hasSeedData =
        _session.hasOcrData ||
        _cccdController.text.trim().isNotEmpty ||
        _nameController.text.trim().isNotEmpty ||
        _dobController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Review OCR Data')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5FBFC), Color(0xFFF7F9FC)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.all(pagePadding),
            children: [
              AnimatedContainer(
                duration: AppMotion.medium,
                curve: AppMotion.standard,
                padding: EdgeInsets.all(compact ? 12 : 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bước 2/5 - Kiểm tra thông tin OCR',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Xác minh dữ liệu trước khi tiếp tục Face Matching và ZKP.',
                    ),
                  ],
                ),
              ),
              if (!hasSeedData) ...[
                SizedBox(height: compact ? 8 : 10),
                Container(
                  padding: EdgeInsets.all(compact ? 10 : 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFFFF8A3D)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bạn chưa có dữ liệu OCR. Có thể nhập tay hoặc quay lại màn hình quét.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: compact ? 12 : 16),
              TextField(
                controller: _cccdController,
                keyboardType: TextInputType.number,
                decoration: _fieldDecoration(
                  label: 'Số CCCD',
                  hint: 'Nhập 9 hoặc 12 chữ số',
                  icon: Icons.badge_outlined,
                ),
              ),
              SizedBox(height: compact ? 10 : 12),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.characters,
                decoration: _fieldDecoration(
                  label: 'Họ và tên',
                  icon: Icons.person_outline,
                ),
              ),
              SizedBox(height: compact ? 10 : 12),
              TextField(
                controller: _dobController,
                decoration: _fieldDecoration(
                  label: 'Ngày sinh',
                  hint: 'dd/mm/yyyy',
                  icon: Icons.calendar_month_outlined,
                ),
              ),
              SizedBox(height: compact ? 12 : 14),
              Container(
                padding: EdgeInsets.all(compact ? 10 : 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF13343A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AnimatedSwitcher(
                  duration: AppMotion.fast,
                  switchInCurve: AppMotion.standard,
                  switchOutCurve: Curves.easeIn,
                  child: SelectableText(
                    _cccdHash.isEmpty
                        ? 'SHA-256 Hash: (chưa hợp lệ)'
                        : 'SHA-256 Hash: $_cccdHash',
                    key: ValueKey<String>(_cccdHash),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(height: compact ? 18 : 24),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _confirmAndSave,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: Text(
                  _isSaving
                      ? 'Đang lưu và chuyển sang bước quét mặt...'
                      : 'Xác nhận & Tiếp tục quét khuôn mặt',
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _goBackToOcr,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Quét lại CCCD'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
