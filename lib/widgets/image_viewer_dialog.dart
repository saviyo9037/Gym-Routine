import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../models/media_attachment.dart';
import '../services/database_service.dart';
import '../services/media_service.dart';

class ImageViewerDialog extends StatefulWidget {
  final MediaAttachment attachment;
  final VoidCallback? onUpdated;
  final VoidCallback? onDeleted;

  const ImageViewerDialog({
    super.key,
    required this.attachment,
    this.onUpdated,
    this.onDeleted,
  });

  static Future<void> show(
    BuildContext context, {
    required MediaAttachment attachment,
    VoidCallback? onUpdated,
    VoidCallback? onDeleted,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (_) => ImageViewerDialog(
        attachment: attachment,
        onUpdated: onUpdated,
        onDeleted: onDeleted,
      ),
    );
  }

  @override
  State<ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<ImageViewerDialog> {
  final MediaService _mediaService = MediaService.instance;
  final DatabaseService _dbService = DatabaseService();

  late MediaAttachment _currentAttachment;
  String _resolvedPath = '';
  bool _isLoading = true;
  bool _fileExists = false;

  @override
  void initState() {
    super.initState();
    _currentAttachment = widget.attachment;
    _resolvePath();
  }

  Future<void> _resolvePath() async {
    final path = await _mediaService.resolveFilePath(
      _currentAttachment.filePath,
    );
    final exists = await File(path).exists();
    if (mounted) {
      setState(() {
        _resolvedPath = path;
        _fileExists = exists;
        _isLoading = false;
      });
    }
  }

  Future<void> _replaceImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: AppColors.primary,
              ),
              title: const Text(
                'Capture with Camera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final newPath = await _mediaService.capturePhoto();
                if (newPath != null) {
                  await _applyReplacement(newPath);
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.primary,
              ),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final newPath = await _mediaService.pickPhotoFromGallery();
                if (newPath != null) {
                  await _applyReplacement(newPath);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyReplacement(String newPath) async {
    // Delete old file if different
    if (_resolvedPath.isNotEmpty && _resolvedPath != newPath) {
      await _mediaService.deleteFile(_resolvedPath);
    }

    final updated = _currentAttachment.copyWith(filePath: newPath);
    if (updated.id != null) {
      await _dbService.updateMediaAttachment(updated);
    }

    setState(() {
      _currentAttachment = updated;
      _resolvedPath = newPath;
      _fileExists = true;
    });

    widget.onUpdated?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image replaced successfully'),
          backgroundColor: AppColors.successDark,
        ),
      );
    }
  }

  Future<void> _deleteImage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text(
          'Delete Image?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this photo attachment? This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_currentAttachment.id != null) {
        await _dbService.deleteMediaAttachment(_currentAttachment.id!);
      }
      await _mediaService.deleteFile(_resolvedPath);
      widget.onDeleted?.call();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo deleted'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _shareImage() async {
    if (_fileExists && _resolvedPath.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(_resolvedPath)],
          text: _currentAttachment.title,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.photo_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentAttachment.title,
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _currentAttachment.createdAt.length >= 10
                            ? _currentAttachment.createdAt.substring(0, 10)
                            : _currentAttachment.createdAt,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Image Content / Zoom Canvas
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : (!_fileExists
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.broken_image_rounded,
                                    color: Colors.amber,
                                    size: 64,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Photo file could not be found on device',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _resolvedPath,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.sync_rounded,
                                      color: Colors.black,
                                    ),
                                    label: const Text(
                                      'Replace Photo',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                    ),
                                    onPressed: _replaceImage,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.file(
                                File(_resolvedPath),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Text(
                                    'Failed to render photo',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          )),
            ),
          ),

          // Footer Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                TextButton.icon(
                  icon: const Icon(
                    Icons.sync_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  label: const Text(
                    'Replace',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _replaceImage,
                ),
                TextButton.icon(
                  icon: const Icon(
                    Icons.share_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'Share',
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: _shareImage,
                ),
                TextButton.icon(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                  label: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onPressed: _deleteImage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
