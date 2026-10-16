import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/media_attachment.dart';
import '../services/database_service.dart';
import '../services/media_service.dart';
import 'image_viewer_dialog.dart';
import 'video_player_dialog.dart';
import 'voice_recorder_dialog.dart';
import 'audio_player_card.dart';

class MediaAttachmentSection extends StatefulWidget {
  final String
  entityType; // 'exercise', 'muscle', 'plan', 'session', 'workout_exercise'
  final int entityId;
  final String title;
  final String? sectionTitle;
  final String? entityTitle;
  final VoidCallback? onChanged;

  const MediaAttachmentSection({
    super.key,
    required this.entityType,
    required this.entityId,
    this.title = 'MEDIA ATTACHMENTS',
    this.sectionTitle,
    this.entityTitle,
    this.onChanged,
  });

  @override
  State<MediaAttachmentSection> createState() => _MediaAttachmentSectionState();
}

class _MediaAttachmentSectionState extends State<MediaAttachmentSection> {
  final DatabaseService _dbService = DatabaseService();
  final MediaService _mediaService = MediaService.instance;

  List<MediaAttachment> _attachments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  @override
  void didUpdateWidget(covariant MediaAttachmentSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId ||
        oldWidget.entityType != widget.entityType) {
      _loadAttachments();
    }
  }

  Future<void> _loadAttachments() async {
    if (widget.entityId <= 0) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final list = await _dbService.getMediaAttachments(
      widget.entityType,
      widget.entityId,
    );
    if (mounted) {
      setState(() {
        _attachments = list;
        _isLoading = false;
      });
    }
  }

  void _showAddMediaSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  'ATTACH MEDIA',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const Divider(color: AppColors.border),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'Capture Photo (Camera)',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final path = await _mediaService.capturePhoto();
                  if (path != null) {
                    await _saveAttachment('photo', path, 'Workout Form Photo');
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'Choose Photo from Gallery',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final path = await _mediaService.pickPhotoFromGallery();
                  if (path != null) {
                    await _saveAttachment('photo', path, 'Gallery Form Photo');
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.videocam_rounded,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'Record Video (Camera)',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final path = await _mediaService.recordVideo();
                  if (path != null) {
                    await _saveAttachment('video', path, 'Workout Form Video');
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.video_library_rounded,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'Choose Video from Gallery',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final path = await _mediaService.pickVideoFromGallery();
                  if (path != null) {
                    await _saveAttachment('video', path, 'Execution Video');
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.mic_rounded,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'Record Voice Note',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  VoiceRecorderDialog.show(
                    context,
                    title: 'Trainer Voice Note',
                    onSaved: (audioPath, duration) async {
                      await _saveAttachment(
                        'audio',
                        audioPath,
                        'Trainer Voice Instruction',
                        durationSeconds: duration,
                      );
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.audio_file_rounded,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'Import Audio File',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final path = await _mediaService.pickAudioFile();
                  if (path != null) {
                    await _saveAttachment(
                      'audio',
                      path,
                      'Imported Audio Memo',
                      durationSeconds: 30,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAttachment(
    String mediaType,
    String filePath,
    String defaultTitle, {
    int? durationSeconds,
  }) async {
    final attachment = MediaAttachment(
      entityType: widget.entityType,
      entityId: widget.entityId,
      mediaType: mediaType,
      filePath: filePath,
      title: defaultTitle,
      durationSeconds: durationSeconds,
    );

    await _dbService.insertMediaAttachment(attachment);
    await _loadAttachments();
    widget.onChanged?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$mediaType attached successfully'),
          backgroundColor: AppColors.successDark,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = _attachments.where((a) => a.mediaType == 'photo').toList();
    final videos = _attachments.where((a) => a.mediaType == 'video').toList();
    final audios = _attachments.where((a) => a.mediaType == 'audio').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.perm_media_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.sectionTitle ?? widget.title,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                if (_attachments.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_attachments.length}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            TextButton.icon(
              icon: const Icon(
                Icons.add_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              label: const Text(
                'Add Media',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              onPressed: _showAddMediaSheet,
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (_attachments.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.perm_media_outlined,
                  color: AppColors.textSecondary,
                  size: 32,
                ),
                const SizedBox(height: 8),
                const Text(
                  'No media attachments yet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Attach form photos, execution videos, or trainer voice notes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Attach First File'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  onPressed: _showAddMediaSheet,
                ),
              ],
            ),
          )
        else ...[
          // Photos Grid
          if (photos.isNotEmpty) ...[
            const Text(
              'PHOTOS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: photos.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (ctx, i) => _buildPhotoThumbnail(photos[i]),
            ),
            const SizedBox(height: 14),
          ],

          // Videos Cards
          if (videos.isNotEmpty) ...[
            const Text(
              'VIDEOS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            ...videos.map((v) => _buildVideoCard(v)),
            const SizedBox(height: 14),
          ],

          // Audio Memos Cards
          if (audios.isNotEmpty) ...[
            const Text(
              'VOICE NOTES & AUDIO',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            ...audios.map(
              (a) => AudioPlayerCard(
                attachment: a,
                onUpdated: () {
                  _loadAttachments();
                  widget.onChanged?.call();
                },
                onDeleted: () {
                  _loadAttachments();
                  widget.onChanged?.call();
                },
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPhotoThumbnail(MediaAttachment photo) {
    return FutureBuilder<String>(
      future: _mediaService.resolveFilePath(photo.filePath),
      builder: (ctx, snap) {
        final path = snap.data ?? photo.filePath;
        final file = File(path);
        final exists = file.existsSync();

        return InkWell(
          onTap: () {
            ImageViewerDialog.show(
              context,
              attachment: photo,
              onUpdated: () {
                _loadAttachments();
                widget.onChanged?.call();
              },
              onDeleted: () {
                _loadAttachments();
                widget.onChanged?.call();
              },
            );
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (exists)
                    Image.file(file, fit: BoxFit.cover)
                  else
                    Container(
                      color: AppColors.surfaceElevated,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image_rounded,
                            color: Colors.amber,
                            size: 24,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Missing',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Text(
                        photo.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoCard(MediaAttachment video) {
    return InkWell(
      onTap: () {
        VideoPlayerDialog.show(
          context,
          videoPath: video.filePath,
          title: video.title,
          attachment: video,
          onUpdated: () {
            _loadAttachments();
            widget.onChanged?.call();
          },
          onDeleted: () {
            _loadAttachments();
            widget.onChanged?.call();
          },
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Recorded on ${video.createdAt.length >= 10 ? video.createdAt.substring(0, 10) : video.createdAt}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.videocam_rounded,
                    color: AppColors.primary,
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Play',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
