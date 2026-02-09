import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crop_image/crop_image.dart';

// Importaciones condicionales para cámara y ML Kit (solo móvil)
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/shelf_zone_model.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Pantalla modal de escáner para capturar fotos de los lomos de vinilos
/// Soporta cámara en vivo (móvil) y selección de galería (web/escritorio)
class ZoneScannerScreen extends StatefulWidget {
  final ShelfZoneModel zone;
  final Function(File imageFile, String? extractedText)? onImageCaptured;

  const ZoneScannerScreen({
    super.key,
    required this.zone,
    this.onImageCaptured,
  });

  /// Muestra el escáner como modal desde abajo
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required ShelfZoneModel zone,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (context) => ZoneScannerScreen(zone: zone),
    );
  }

  @override
  State<ZoneScannerScreen> createState() => _ZoneScannerScreenState();
}

class _ZoneScannerScreenState extends State<ZoneScannerScreen>
    with TickerProviderStateMixin {
  // Platform detection
  bool get _isWebOrDesktop => kIsWeb || (!Platform.isAndroid && !Platform.isIOS);

  // Camera (solo móvil)
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isCameraError = false;
  String? _cameraErrorMessage;

  // ML Kit (solo móvil)
  TextRecognizer? _textRecognizer;

  // Image Picker
  final ImagePicker _imagePicker = ImagePicker();

  // Selected images (multi-foto por zona)
  final List<XFile> _selectedImages = [];
  final List<Uint8List> _selectedImagesList = [];
  int _currentPreviewIndex = 0;

  // State
  bool _isCapturing = false;
  bool _isProcessing = false;
  String? _feedbackMessage;
  bool _showFeedback = false;

  // Animations
  late AnimationController _pulseController;
  late AnimationController _buttonBounceController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _buttonBounceAnimation;

  // Localization
  AppLocalizations? _loc;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    
    if (!_isWebOrDesktop) {
      _textRecognizer = TextRecognizer();
      _initCamera();
    }
  }

  void _initAnimations() {
    // Pulse animation for the scanning frame
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Bounce animation for the capture button
    _buttonBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _buttonBounceAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _buttonBounceController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initCamera() async {
    if (_isWebOrDesktop) return;

    try {
      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _isCameraError = true;
          _cameraErrorMessage = 'No cameras available';
        });
        return;
      }

      // Use back camera
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      // Lock orientation to portrait for consistent UI
      await _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraError = true;
          _cameraErrorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _buttonBounceController.dispose();
    _cameraController?.dispose();
    _textRecognizer?.close();
    super.dispose();
  }

  /// Comprime/redimensiona una imagen para que no exceda maxWidth
  /// Esto es crucial en web donde ImagePicker ignora maxWidth/maxHeight
  static Future<Uint8List> _compressImage(Uint8List bytes, {int maxWidth = 1500}) async {
    try {
      // Decodificar para obtener dimensiones
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final original = frame.image;

      // Si ya es lo suficientemente pequeña, devolver tal cual
      if (original.width <= maxWidth) {
        debugPrint('📷 Imagen OK: ${original.width}x${original.height} (${(bytes.length / 1024).toStringAsFixed(0)} KB)');
        original.dispose();
        return bytes;
      }

      // Calcular nuevas dimensiones manteniendo aspect ratio
      final ratio = maxWidth / original.width;
      final newWidth = maxWidth;
      final newHeight = (original.height * ratio).round();

      // Redibujar a nuevo tamaño
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, newWidth.toDouble(), newHeight.toDouble()),
      );
      canvas.drawImageRect(
        original,
        Rect.fromLTWH(0, 0, original.width.toDouble(), original.height.toDouble()),
        Rect.fromLTWH(0, 0, newWidth.toDouble(), newHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final resized = await picture.toImage(newWidth, newHeight);
      original.dispose();

      final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
      resized.dispose();

      if (byteData != null) {
        final compressed = byteData.buffer.asUint8List();
        debugPrint('📷 Imagen comprimida: ${newWidth}x$newHeight (${(compressed.length / 1024).toStringAsFixed(0)} KB, antes ${(bytes.length / 1024).toStringAsFixed(0)} KB)');
        return compressed;
      }
    } catch (e) {
      debugPrint('⚠️ Error comprimiendo imagen: $e — usando original');
    }
    return bytes;
  }

  /// Seleccionar imagen de la galería
  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1500,
        maxHeight: 1500,
        imageQuality: 80,
      );

      if (image != null) {
        // Leer bytes y comprimir (en web ImagePicker ignora maxWidth/quality)
        final rawBytes = await image.readAsBytes();
        final bytes = await _compressImage(rawBytes);
        
        setState(() {
          _selectedImages.add(image);
          _selectedImagesList.add(bytes);
          _currentPreviewIndex = _selectedImages.length - 1;
          _showFeedback = false;
        });

        _showFeedbackMessage(
          'Foto ${_selectedImages.length} añadida',
          isSuccess: true,
        );
      }
    } catch (e) {
      _showFeedbackMessage(_loc?.errorOccurred ?? 'Error al seleccionar imagen');
    }
  }

  /// Capturar foto desde la cámara
  Future<void> _capturePhoto() async {
    if (_isCapturing || _cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Button bounce animation
    await _buttonBounceController.forward();
    _buttonBounceController.reverse();

    setState(() {
      _isCapturing = true;
      _showFeedback = false;
    });

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      // Comprimir: fotos de cámara suelen ser 12MP+
      final rawBytes = await imageFile.readAsBytes();
      final bytes = await _compressImage(rawBytes);

      setState(() {
        _selectedImages.add(imageFile);
        _selectedImagesList.add(bytes);
        _currentPreviewIndex = _selectedImages.length - 1;
        _isCapturing = false;
      });

      _showFeedbackMessage(
        'Foto ${_selectedImages.length} capturada',
        isSuccess: true,
      );
    } catch (e) {
      _showFeedbackMessage(_loc?.errorOccurred ?? 'Error capturing photo');
      setState(() {
        _isCapturing = false;
      });
    }
  }

  /// Procesar y enviar las imágenes seleccionadas
  Future<void> _processAndSubmit() async {
    if (_selectedImages.isEmpty) return;

    // Button bounce animation
    await _buttonBounceController.forward();
    _buttonBounceController.reverse();

    setState(() {
      _isProcessing = true;
    });

    try {
      _showFeedbackMessage(_loc?.scannerSuccess ?? 'Perfect!', isSuccess: true);

      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        // Devolver siempre los bytes comprimidos (web + móvil)
        // _selectedImagesList contiene las imágenes ya comprimidas/recortadas
        Navigator.of(context).pop({
          'imageBytesList': _selectedImagesList,
          'zone': widget.zone,
        });
      }
    } catch (e) {
      _showFeedbackMessage(_loc?.errorOccurred ?? 'Error processing images');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _analyzeImageQuality(String imagePath) async {
    if (_textRecognizer == null) {
      return {'isGoodQuality': true, 'extractedText': null};
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer!.processImage(inputImage);

      final textBlocks = recognizedText.blocks;
      final totalText = recognizedText.text;

      // Analyze quality based on text recognition
      final hasGoodText = textBlocks.length >= 2 || totalText.length >= 20;

      if (!hasGoodText) {
        if (textBlocks.isEmpty) {
          return {
            'isGoodQuality': false,
            'tip': _loc?.scannerTipLight,
            'extractedText': null,
          };
        } else {
          return {
            'isGoodQuality': false,
            'tip': _loc?.scannerTipCloser,
            'extractedText': null,
          };
        }
      }

      return {
        'isGoodQuality': true,
        'extractedText': totalText,
        'blocksCount': textBlocks.length,
      };
    } catch (e) {
      return {'isGoodQuality': true, 'extractedText': null};
    }
  }

  /// Eliminar una imagen de la lista
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _selectedImagesList.removeAt(index);
      if (_currentPreviewIndex >= _selectedImages.length) {
        _currentPreviewIndex = (_selectedImages.length - 1).clamp(0, _selectedImages.length);
      }
      _showFeedback = false;
    });
  }

  /// Limpiar todas las imágenes
  void _clearAllImages() {
    setState(() {
      _selectedImages.clear();
      _selectedImagesList.clear();
      _currentPreviewIndex = 0;
      _showFeedback = false;
    });
  }

  /// Abrir el editor de recorte para una imagen
  Future<void> _cropImage(int index) async {
    if (index < 0 || index >= _selectedImagesList.length) return;

    final cropController = CropController();
    final imageBytes = _selectedImagesList[index];

    final result = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CropDialog(
        imageBytes: imageBytes,
        cropController: cropController,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedImagesList[index] = result;
      });
      _showFeedbackMessage('Foto ${index + 1} recortada', isSuccess: true);
    }
  }

  void _showFeedbackMessage(String message, {bool isSuccess = false}) {
    setState(() {
      _feedbackMessage = message;
      _showFeedback = true;
    });

    if (!isSuccess) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showFeedback = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _loc = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      height: size.height - statusBarHeight,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Custom AppBar
          _buildAppBar(),

          // Main content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              _loc?.scanner ?? 'Scanner',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final bool hasImages = _selectedImages.isNotEmpty;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Title instruction
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Text(
              hasImages
                  ? '${_selectedImages.length} foto${_selectedImages.length == 1 ? '' : 's'} · Sección de 15-20 discos cada una'
                  : _loc?.scannerTitle ?? '¡Encuadra los lomos de tus vinilos aquí!',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: hasImages ? 15 : 20,
                fontWeight: hasImages ? FontWeight.w500 : FontWeight.bold,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Image area (camera preview OR selected image OR gallery picker)
          Expanded(
            child: _buildImageArea(),
          ),

          // Thumbnail strip (cuando hay imágenes)
          if (hasImages) _buildThumbnailStrip(),

          // Gallery / add photo button
          _buildGalleryButton(),

          // Feedback messages area
          _buildFeedbackArea(),

          // Hint text
          if (!hasImages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tips_and_updates_outlined,
                          color: Colors.amber.shade300,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _loc?.scannerHint ?? 'Asegúrate de que la luz sea buena',
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Action button
          _buildActionButton(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildImageArea() {
    // Si hay imágenes seleccionadas, mostrar vista previa de la actual
    if (_selectedImages.isNotEmpty && _selectedImagesList.isNotEmpty) {
      return _buildSelectedImagePreview();
    }

    // En web/desktop, mostrar placeholder con opción de galería
    if (_isWebOrDesktop) {
      return _buildGalleryPlaceholder();
    }

    // En móvil, mostrar cámara o error
    if (_isCameraError) {
      return _buildCameraErrorWithGallery();
    }

    if (!_isCameraInitialized) {
      return _buildCameraLoading();
    }

    return _buildCameraPreview();
  }

  /// Vista previa de imagen seleccionada (la actual del carrusel)
  Widget _buildSelectedImagePreview() {
    final safeIndex = _currentPreviewIndex.clamp(0, _selectedImagesList.length - 1);
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Imagen seleccionada — contain para verla completa
            Center(
              child: Image.memory(
                _selectedImagesList[safeIndex],
                fit: BoxFit.contain,
              ),
            ),

          // Overlay con zona y contador
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Foto ${safeIndex + 1} de ${_selectedImages.length}',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Botones superiores derechos: recortar + eliminar
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Botón recortar
                GestureDetector(
                  onTap: () => _cropImage(safeIndex),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.crop, color: AppTheme.accentColor, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                // Botón eliminar
                GestureDetector(
                  onTap: () => _removeImage(safeIndex),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // Processing overlay
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _loc?.analyzing ?? 'Analyzing...',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Tira de miniaturas con botón de añadir
  Widget _buildThumbnailStrip() {
    return Container(
      height: 80,
      margin: const EdgeInsets.only(top: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length + 1, // +1 para el botón "añadir"
        itemBuilder: (context, index) {
          // Último elemento: botón "Añadir foto"
          if (index == _selectedImages.length) {
            return GestureDetector(
              onTap: _pickFromGallery,
              child: Container(
                width: 64,
                height: 64,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1.5,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_rounded,
                        color: AppTheme.accentColor, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Añadir',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          
          // Miniatura de foto
          final isSelected = index == _currentPreviewIndex;
          return GestureDetector(
            onTap: () => setState(() => _currentPreviewIndex = index),
            child: Container(
              width: 64,
              height: 64,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppTheme.accentColor : Colors.white.withOpacity(0.2),
                  width: isSelected ? 2.5 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppTheme.accentColor.withOpacity(0.3),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _selectedImagesList[index],
                      fit: BoxFit.cover,
                      width: 64,
                      height: 64,
                    ),
                  ),
                  // Número de foto
                  Positioned(
                    bottom: 2,
                    left: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Botón eliminar
                  Positioned(
                    top: -2,
                    right: -2,
                    child: GestureDetector(
                      onTap: () => _removeImage(index),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 1.5),
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Placeholder para web/desktop
  Widget _buildGalleryPlaceholder() {
    return GestureDetector(
      onTap: _pickFromGallery,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 2,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.photo_library_rounded,
                  size: 64,
                  color: AppTheme.accentColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _loc?.selectPhoto ?? 'Selecciona una foto',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pulsa aquí o usa el botón de abajo',
                style: GoogleFonts.poppins(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade300, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Cámara no disponible en Web',
                      style: GoogleFonts.poppins(
                        color: Colors.amber.shade300,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Error de cámara con opción de galería
  Widget _buildCameraErrorWithGallery() {
    return GestureDetector(
      onTap: _pickFromGallery,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _loc?.cameraNotAvailable ?? 'Cámara no disponible',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Pulsa para seleccionar de galería',
                  style: GoogleFonts.poppins(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library, color: AppTheme.accentColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Abrir galería',
                        style: GoogleFonts.poppins(
                          color: AppTheme.accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraLoading() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              _loc?.loading ?? 'Loading...',
              style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          AspectRatio(
            aspectRatio: _cameraController!.value.aspectRatio,
            child: CameraPreview(_cameraController!),
          ),

          // Scanning frame overlay
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return CustomPaint(
                painter: ScannerFramePainter(
                  pulseValue: _pulseAnimation.value,
                  accentColor: AppTheme.accentColor,
                ),
                child: child,
              );
            },
          ),

          // Zone indicator
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility, color: Colors.white.withOpacity(0.8), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${_loc?.zone ?? 'Zone'} ${widget.zone.zoneIndex + 1}',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Capture button overlay (en móvil)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isCapturing ? null : _capturePhoto,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : Icon(Icons.camera_alt, size: 32, color: AppTheme.primaryColor),
                ),
              ),
            ),
          ),

          // Processing overlay
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    const SizedBox(height: 16),
                    Text(
                      _loc?.analyzing ?? 'Analyzing...',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Botón de galería (visible cuando no hay imágenes, o como "añadir más" cuando hay)
  Widget _buildGalleryButton() {
    // Si ya hay imágenes, el botón de añadir está en el thumbnail strip
    if (_selectedImages.isNotEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        onTap: _pickFromGallery,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_rounded, color: AppTheme.accentColor, size: 22),
              const SizedBox(width: 10),
              Text(
                'O selecciona una foto de tu galería',
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackArea() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _showFeedback ? 1.0 : 0.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _showFeedback ? 50 : 0,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _feedbackMessage?.contains('Perfect') == true ||
                  _feedbackMessage?.contains('Perfecto') == true ||
                  _feedbackMessage?.contains('correctamente') == true ||
                  _feedbackMessage?.contains('capturada') == true
              ? Colors.green.withOpacity(0.2)
              : Colors.amber.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _feedbackMessage?.contains('Perfect') == true ||
                    _feedbackMessage?.contains('Perfecto') == true ||
                    _feedbackMessage?.contains('correctamente') == true ||
                    _feedbackMessage?.contains('capturada') == true
                ? Colors.green.withOpacity(0.5)
                : Colors.amber.withOpacity(0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _feedbackMessage?.contains('Perfect') == true ||
                      _feedbackMessage?.contains('Perfecto') == true ||
                      _feedbackMessage?.contains('correctamente') == true ||
                      _feedbackMessage?.contains('capturada') == true
                  ? Icons.check_circle
                  : Icons.lightbulb_outline,
              color: _feedbackMessage?.contains('Perfect') == true ||
                      _feedbackMessage?.contains('Perfecto') == true ||
                      _feedbackMessage?.contains('correctamente') == true ||
                      _feedbackMessage?.contains('capturada') == true
                  ? Colors.green
                  : Colors.amber,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _feedbackMessage ?? '',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Botón principal de acción
  Widget _buildActionButton() {
    final bool hasImage = _selectedImages.isNotEmpty;
    final bool canSubmit = hasImage && !_isProcessing && !_isCapturing;

    return ScaleTransition(
      scale: _buttonBounceAnimation,
      child: GestureDetector(
        onTap: canSubmit ? _processAndSubmit : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            gradient: canSubmit
                ? LinearGradient(
                    colors: [
                      AppTheme.accentColor,
                      AppTheme.accentColor.withRed((AppTheme.accentColor.red * 0.8).toInt()),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [Colors.grey.shade700, Colors.grey.shade800],
                  ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: canSubmit
                ? [
                    BoxShadow(
                      color: AppTheme.accentColor.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isProcessing)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              else ...[
                Text(
                  hasImage
                      ? '¡Analizar ${_selectedImages.length} foto${_selectedImages.length == 1 ? '' : 's'}!'
                      : (_loc?.readyForGemini ?? '¡Listo para Gemini...!'),
                  style: GoogleFonts.poppins(
                    color: canSubmit ? Colors.white : Colors.white54,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(canSubmit ? 0.2 : 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasImage ? Icons.send_rounded : Icons.camera_alt,
                    color: canSubmit ? Colors.white : Colors.white54,
                    size: 24,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Painter for the scanning frame overlay
class ScannerFramePainter extends CustomPainter {
  final double pulseValue;
  final Color accentColor;

  ScannerFramePainter({
    required this.pulseValue,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Semi-transparent overlay outside the frame
    final outerPath = Path()..addRect(rect);

    // Inner frame area (leave clear)
    final frameMargin = 24.0;
    final frameRect = Rect.fromLTRB(
      frameMargin,
      size.height * 0.15,
      size.width - frameMargin,
      size.height * 0.85,
    );

    final innerPath = Path()
      ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(16)));

    // Combine paths to create hole
    final combinedPath = Path.combine(PathOperation.difference, outerPath, innerPath);

    // Draw semi-transparent overlay
    canvas.drawPath(combinedPath, Paint()..color = Colors.black.withOpacity(0.4));

    // Draw animated frame border
    final borderOpacity = 0.5 + (pulseValue * 0.5);
    final borderWidth = 2.0 + (pulseValue * 1.0);

    final framePaint = Paint()
      ..color = accentColor.withOpacity(borderOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, const Radius.circular(16)),
      framePaint,
    );

    // Draw corner brackets
    final cornerLength = 30.0;
    final cornerPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Top-left corner
    canvas.drawLine(
      Offset(frameRect.left, frameRect.top + cornerLength),
      Offset(frameRect.left, frameRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameRect.left, frameRect.top),
      Offset(frameRect.left + cornerLength, frameRect.top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(frameRect.right - cornerLength, frameRect.top),
      Offset(frameRect.right, frameRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameRect.right, frameRect.top),
      Offset(frameRect.right, frameRect.top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(frameRect.left, frameRect.bottom - cornerLength),
      Offset(frameRect.left, frameRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameRect.left, frameRect.bottom),
      Offset(frameRect.left + cornerLength, frameRect.bottom),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(frameRect.right - cornerLength, frameRect.bottom),
      Offset(frameRect.right, frameRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameRect.right, frameRect.bottom),
      Offset(frameRect.right, frameRect.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant ScannerFramePainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue;
  }
}

/// Dialog de recorte de imagen usando crop_image
class _CropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final CropController cropController;

  const _CropDialog({
    required this.imageBytes,
    required this.cropController,
  });

  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  bool _isCropping = false;

  Future<void> _confirmCrop() async {
    setState(() => _isCropping = true);
    try {
      final croppedBitmap = await widget.cropController.croppedBitmap();
      final byteData = await croppedBitmap.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null && mounted) {
        Navigator.of(context).pop(byteData.buffer.asUint8List());
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al recortar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(
              children: [
                Icon(Icons.crop, color: AppTheme.accentColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Recortar foto',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Instrucción
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Ajusta el recuadro para seleccionar los discos',
              style: GoogleFonts.poppins(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Área de recorte
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: CropImage(
                  controller: widget.cropController,
                  image: Image.memory(widget.imageBytes),
                  gridColor: AppTheme.accentColor.withOpacity(0.5),
                  gridCornerSize: 30,
                  gridThinWidth: 1,
                  gridThickWidth: 3,
                  alwaysShowThirdLines: true,
                  // paddingSize añade zona táctil alrededor de la imagen
                  // para que las esquinas de recorte sean accesibles en web
                  paddingSize: 20,
                  touchSize: 80,
                  alwaysMove: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Botones
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                // Resetear
                TextButton.icon(
                  onPressed: () {
                    widget.cropController.crop = const Rect.fromLTRB(0, 0, 1, 1);
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    'Resetear',
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                  ),
                ),
                const Spacer(),
                // Confirmar
                ElevatedButton.icon(
                  onPressed: _isCropping ? null : _confirmCrop,
                  icon: _isCropping
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 20),
                  label: Text(
                    _isCropping ? 'Recortando...' : 'Confirmar',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
