import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/theme/memo_theme.dart';
import '../domain/document_import_models.dart';

class CameraCaptureOutcome {
  const CameraCaptureOutcome._({this.candidate, this.chooseGallery = false});

  const CameraCaptureOutcome.captured(ImageCandidate candidate)
    : this._(candidate: candidate);

  const CameraCaptureOutcome.gallery() : this._(chooseGallery: true);

  final ImageCandidate? candidate;
  final bool chooseGallery;
}

class DocumentCameraScreen extends StatefulWidget {
  const DocumentCameraScreen({super.key});

  @override
  State<DocumentCameraScreen> createState() => _DocumentCameraScreenState();
}

class _DocumentCameraScreenState extends State<DocumentCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _loading = true;
  bool _capturing = false;
  bool _permanentlyDenied = false;
  String? _error;
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed && mounted) {
      _initialize(requestPermission: false);
    }
  }

  Future<void> _initialize({bool requestPermission = true}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final permission = requestPermission
        ? await Permission.camera.request()
        : await Permission.camera.status;
    if (!permission.isGranted) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _permanentlyDenied = permission.isPermanentlyDenied;
        _error = 'MemoMind cần quyền camera để chụp tài liệu.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('camera_unavailable', 'No camera');
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _controller?.dispose();
      setState(() {
        _controller = controller;
        _loading = false;
        _permanentlyDenied = false;
      });
    } on CameraException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Không thể chụp ảnh. Vui lòng thử lại hoặc chọn ảnh từ thư viện.';
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      HapticFeedback.mediumImpact();
      final file = await controller.takePicture();
      final candidate = ImageCandidate(
        bytes: await file.readAsBytes(),
        source: DocumentImageSource.camera,
        originalPath: file.path,
        ownsTemporaryFile: true,
      );
      if (mounted) {
        Navigator.of(context).pop(CameraCaptureOutcome.captured(candidate));
      }
    } on CameraException {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error =
            'Không thể chụp ảnh. Vui lòng thử lại hoặc chọn ảnh từ thư viện.';
      });
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = _flashMode == FlashMode.off ? FlashMode.auto : FlashMode.off;
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } on CameraException {
      // Some devices do not expose a flash unit; capture remains available.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Chụp tài liệu'),
        actions: [
          if (controller?.value.isInitialized ?? false)
            IconButton(
              tooltip: _flashMode == FlashMode.off
                  ? 'Bật flash tự động'
                  : 'Tắt flash',
              onPressed: _toggleFlash,
              icon: Icon(
                _flashMode == FlashMode.off
                    ? Icons.flash_off_rounded
                    : Icons.flash_auto_rounded,
              ),
            ),
        ],
      ),
      body: _error != null
          ? _CameraError(
              message: _error!,
              showSettings: _permanentlyDenied,
              onRetry: _initialize,
              onSettings: openAppSettings,
              onGallery: () =>
                  Navigator.of(context)
                      .pop(const CameraCaptureOutcome.gallery()),
              onCancel: () => Navigator.of(context).pop(),
            )
          : _loading || controller == null || !controller.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: CameraPreview(controller),
                  ),
                ),
                const IgnorePointer(
                  child: CustomPaint(painter: _GuidePainter()),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  top: 16,
                  child: SafeArea(
                    child: Text(
                      'Đặt tài liệu trong khung và giữ thiết bị ổn định',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        shadows: const [Shadow(blurRadius: 6)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: Semantics(
                        button: true,
                        label: 'Chụp ảnh',
                        child: InkResponse(
                          key: const Key('camera-shutter'),
                          onTap: _capturing ? null : _capture,
                          radius: 42,
                          child: Container(
                            width: 76,
                            height: 76,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _capturing
                                    ? Colors.white54
                                    : Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: _capturing
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({
    required this.message,
    required this.showSettings,
    required this.onRetry,
    required this.onSettings,
    required this.onGallery,
    required this.onCancel,
  });

  final String message;
  final bool showSettings;
  final VoidCallback onRetry;
  final VoidCallback onSettings;
  final VoidCallback onGallery;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return ColoredBox(
      color: p.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.no_photography_outlined, color: p.warning, size: 52),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
                if (showSettings)
                  TextButton(
                    onPressed: onSettings,
                    child: const Text('Mở cài đặt'),
                  ),
                TextButton(
                  onPressed: onGallery,
                  child: const Text('Chọn từ thư viện'),
                ),
                TextButton(onPressed: onCancel, child: const Text('Hủy')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * 0.82,
      height: size.height * 0.58,
    );
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, Paint()..color = Colors.black45);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
