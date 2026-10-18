import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';

class ExerciseImageWidget extends StatelessWidget {
  final String? imagePath;
  final String? personalPhotoPath;
  final String exerciseName;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  const ExerciseImageWidget({
    super.key,
    this.imagePath,
    this.personalPhotoPath,
    required this.exerciseName,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(12);
    // Decode at display size: a 200-card list must not hold 200 full-size bitmaps.
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final decodeWidth = (width != null && width!.isFinite)
        ? (width! * dpr).round().clamp(64, 1080)
        : 720;

    Widget imageContent;

    // Check personal photo path first
    if (personalPhotoPath != null && personalPhotoPath!.isNotEmpty) {
      final file = File(personalPhotoPath!);
      if (file.existsSync()) {
        imageContent = Image.file(
          file,
          cacheWidth: decodeWidth,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
      } else {
        imageContent = _buildAssetOrPlaceholder(decodeWidth);
      }
    } else {
      imageContent = _buildAssetOrPlaceholder(decodeWidth);
    }

    return ClipRRect(
      borderRadius: effectiveRadius,
      child: Container(
        width: width,
        height: height,
        color: AppColors.cardSurface,
        child: imageContent,
      ),
    );
  }

  Widget _buildAssetOrPlaceholder(int decodeWidth) {
    if (imagePath != null && imagePath!.isNotEmpty) {
      if (imagePath!.startsWith('assets/')) {
        return Image.asset(
          imagePath!,
          cacheWidth: decodeWidth,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
      } else {
        final f = File(imagePath!);
        if (f.existsSync()) {
          return Image.file(
            f,
            cacheWidth: decodeWidth,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => _buildPlaceholder(),
          );
        }
      }
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    final initials = exerciseName.trim().isNotEmpty
        ? exerciseName
              .trim()
              .split(' ')
              .map((w) => w.isNotEmpty ? w[0] : '')
              .take(2)
              .join()
        : 'RT';

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        gradient: LinearGradient(
          colors: [AppColors.surfaceElevated, AppColors.cardSurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.fitness_center_rounded,
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              initials,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
