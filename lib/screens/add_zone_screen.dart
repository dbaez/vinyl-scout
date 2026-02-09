import 'package:flutter/material.dart';
import '../models/shelf_model.dart';
import '../models/shelf_zone_model.dart';
import '../services/shelf_service.dart';
import '../theme/app_theme.dart';

class AddZoneScreen extends StatefulWidget {
  final ShelfModel shelf;

  const AddZoneScreen({super.key, required this.shelf});

  @override
  State<AddZoneScreen> createState() => _AddZoneScreenState();
}

class _AddZoneScreenState extends State<AddZoneScreen> {
  final ShelfService _shelfService = ShelfService();
  
  // Lista de puntos marcados (múltiples zonas)
  List<Offset> _markedPoints = [];
  bool _isSaving = false;
  Size? _imageDisplaySize;
  final GlobalKey _imageKey = GlobalKey();
  bool _imageLoaded = false;

  int get _startIndex => (widget.shelf.zones?.length ?? 0);

  @override
  void initState() {
    super.initState();
    // Capturar tamaño de imagen después del primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateImageSize();
    });
  }

  void _updateImageSize() {
    final RenderBox? imageBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageBox != null && imageBox.hasSize) {
      setState(() {
        _imageDisplaySize = imageBox.size;
      });
    } else {
      // Reintentar si la imagen aún no se ha cargado
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _updateImageSize();
      });
    }
  }

  Future<void> _saveAllZones() async {
    if (_markedPoints.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      // Crear lista de coordenadas para todas las zonas
      final zones = _markedPoints.asMap().entries.map((entry) {
        return ZoneCoordinates(
          centerX: entry.value.dx,
          centerY: entry.value.dy,
        );
      }).toList();

      // Guardar todas las zonas de una vez
      final savedZones = await _shelfService.addMultipleZonesWithOffset(
        shelfId: widget.shelf.id,
        zones: zones,
        startIndex: _startIndex,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text('${savedZones.length} zonas creadas'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, savedZones);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onTapImage(TapDownDetails details) {
    final RenderBox? imageBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageBox == null) return;

    final size = imageBox.size;
    final localPos = details.localPosition;

    // Convertir a coordenadas relativas (0.0 - 1.0)
    final relativeX = (localPos.dx / size.width).clamp(0.0, 1.0);
    final relativeY = (localPos.dy / size.height).clamp(0.0, 1.0);

    setState(() {
      _markedPoints.add(Offset(relativeX, relativeY));
      _imageDisplaySize = size;
    });
  }

  void _removeLastPoint() {
    if (_markedPoints.isNotEmpty) {
      setState(() {
        _markedPoints.removeLast();
      });
    }
  }

  void _clearAllPoints() {
    setState(() {
      _markedPoints.clear();
    });
  }

  void _removePoint(int index) {
    setState(() {
      _markedPoints.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final existingZonesCount = widget.shelf.zones?.length ?? 0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Añadir Zonas (${_markedPoints.length})'),
        actions: [
          if (_markedPoints.isNotEmpty) ...[
            IconButton(
              onPressed: _removeLastPoint,
              icon: const Icon(Icons.undo),
              tooltip: 'Deshacer última',
            ),
            IconButton(
              onPressed: _clearAllPoints,
              icon: const Icon(Icons.clear_all),
              tooltip: 'Limpiar todo',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Instrucciones
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[900],
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.touch_app, color: AppTheme.secondaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _markedPoints.isEmpty
                                ? 'Toca para marcar la zona ${existingZonesCount + 1}'
                                : '${_markedPoints.length} zona(s) marcada(s)',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Puedes marcar varias zonas antes de guardar',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Leyenda de colores
                if (existingZonesCount > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendItem(const Color(0xFF4CAF50), 'Zonas existentes'),
                      const SizedBox(width: 20),
                      _buildLegendItem(AppTheme.secondaryColor, 'Nuevas zonas'),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Imagen con marcadores
          Expanded(
            child: Container(
              color: Colors.grey[850],
              child: Center(
                child: GestureDetector(
                  onTapDown: _onTapImage,
                  child: Stack(
                    children: [
                      // Imagen
                      Image.network(
                        widget.shelf.masterPhotoUrl,
                        key: _imageKey,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) {
                            // Imagen cargada, capturar tamaño
                            if (!_imageLoaded) {
                              _imageLoaded = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _updateImageSize();
                              });
                            }
                            return child;
                          }
                          return const SizedBox(
                            width: 200,
                            height: 200,
                            child: Center(
                              child: CircularProgressIndicator(color: AppTheme.secondaryColor),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stack) {
                          return Container(
                            width: 200,
                            height: 200,
                            color: Colors.grey[800],
                            child: const Icon(Icons.broken_image, size: 64, color: Colors.grey),
                          );
                        },
                      ),

                      // Marcadores de zonas existentes
                      if (widget.shelf.zones != null && _imageDisplaySize != null)
                        ...widget.shelf.zones!.map((zone) => Positioned(
                              left: zone.centerX * _imageDisplaySize!.width - 16,
                              top: zone.centerY * _imageDisplaySize!.height - 16,
                              child: _buildMarker(
                                zone.zoneIndex + 1, 
                                isExisting: true,
                                onRemove: null,
                              ),
                            )),

                      // Nuevos marcadores
                      if (_imageDisplaySize != null)
                        ..._markedPoints.asMap().entries.map((entry) {
                          final index = entry.key;
                          final point = entry.value;
                          final zoneNumber = existingZonesCount + index + 1;
                          return Positioned(
                            left: point.dx * _imageDisplaySize!.width - 22,
                            top: point.dy * _imageDisplaySize!.height - 22,
                            child: _buildMarker(
                              zoneNumber,
                              isExisting: false,
                              onRemove: () => _removePoint(index),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Lista de zonas marcadas
          if (_markedPoints.isNotEmpty)
            Container(
              height: 60,
              color: Colors.grey[900],
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _markedPoints.length,
                itemBuilder: (context, index) {
                  final zoneNumber = existingZonesCount + index + 1;
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Chip(
                      backgroundColor: AppTheme.secondaryColor,
                      deleteIconColor: Colors.white,
                      onDeleted: () => _removePoint(index),
                      label: Text(
                        'Zona $zoneNumber',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      avatar: CircleAvatar(
                        backgroundColor: Colors.white24,
                        child: Text(
                          '$zoneNumber',
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Botones
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[900],
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white38),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _markedPoints.isNotEmpty && !_isSaving ? _saveAllZones : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        disabledBackgroundColor: Colors.grey[700],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.save, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _markedPoints.isEmpty 
                                      ? 'Marca zonas' 
                                      : 'Guardar ${_markedPoints.length} zona(s)',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: Colors.grey[400], fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildMarker(int number, {required bool isExisting, VoidCallback? onRemove}) {
    final size = isExisting ? 36.0 : 44.0;
    // Zonas existentes en verde, nuevas en color secundario (rosa)
    final color = isExisting ? const Color(0xFF4CAF50) : AppTheme.secondaryColor;

    return GestureDetector(
      onTap: onRemove,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: isExisting ? 2 : 3),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: isExisting ? 8 : 12,
              spreadRadius: isExisting ? 1 : 2,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Icono de check para zonas existentes
            if (isExisting)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 10, color: Color(0xFF4CAF50)),
                ),
              ),
            Text(
              '$number',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: isExisting ? 14 : 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
