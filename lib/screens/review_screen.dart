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

  void _showDocumentPreview() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Xem lại',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('Bản xem nhanh thông tin vừa nhận diện từ giấy tờ.'),
              const SizedBox(height: 12),
              Text('Họ và tên: ${_nameController.text.trim()}'),
              const SizedBox(height: 6),
              Text('Số CCCD: ${_cccdController.text.trim()}'),
              const SizedBox(height: 6),
              Text('Ngày sinh: ${_dobController.text.trim()}'),
            ],
          ),
        );
      },
    );
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

    return Scaffold(
      appBar: AppBar(title: const Text('Xác minh tài khoản')),
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
                      'Bước 2/4',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Kiểm tra thông tin',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('Hãy kiểm tra và chỉnh sửa nếu có sai sót'),
                  ],
                ),
              ),
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
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showDocumentPreview,
                  icon: const Icon(Icons.remove_red_eye_outlined),
                  label: const Text('Xem lại'),
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
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
              SizedBox(height: compact ? 18 : 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _confirmAndSave,
                  child: Text(
                    _isSaving ? 'Đang xử lý...' : 'Thông tin đã đúng',
                  ),
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isSaving ? null : _goBackToOcr,
                  child: const Text('Chụp lại giấy tờ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
