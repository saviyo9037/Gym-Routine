import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/models/media_attachment.dart';

void main() {
  group('MediaAttachment Model & Serialization Tests', () {
    test('Correctly serializes and deserializes photo attachment', () {
      final now = DateTime.now().toIso8601String();
      final att = MediaAttachment(
        id: 10,
        entityType: 'exercise',
        entityId: 42,
        mediaType: 'photo',
        filePath: '/data/user/0/com.example.reptrack/app_flutter/reptrack_media/form_123.jpg',
        title: 'Bicep Form Check',
        description: 'Elbows tucked, strict form',
        createdAt: now,
      );

      final map = att.toMap();
      expect(map['id'], equals(10));
      expect(map['entity_type'], equals('exercise'));
      expect(map['entity_id'], equals(42));
      expect(map['media_type'], equals('photo'));
      expect(map['file_path'], contains('form_123.jpg'));
      expect(map['title'], equals('Bicep Form Check'));
      expect(map['description'], equals('Elbows tucked, strict form'));
      expect(map['duration_seconds'], isNull);

      final revived = MediaAttachment.fromMap(map);
      expect(revived.id, equals(10));
      expect(revived.entityType, equals('exercise'));
      expect(revived.entityId, equals(42));
      expect(revived.mediaType, equals('photo'));
      expect(revived.filePath, equals(att.filePath));
      expect(revived.title, equals('Bicep Form Check'));
      expect(revived.description, equals('Elbows tucked, strict form'));
      expect(revived.durationSeconds, isNull);
    });

    test('Correctly serializes and deserializes video attachment', () {
      final att = MediaAttachment(
        id: 20,
        entityType: 'session',
        entityId: 99,
        mediaType: 'video',
        filePath: '/storage/emulated/0/Android/data/com.example.reptrack/files/reptrack_media/video_456.mp4',
        title: 'Squat PR Set Video',
        durationSeconds: 45,
      );

      final map = att.toMap();
      expect(map['id'], equals(20));
      expect(map['entity_type'], equals('session'));
      expect(map['media_type'], equals('video'));
      expect(map['duration_seconds'], equals(45));

      final revived = MediaAttachment.fromMap(map);
      expect(revived.id, equals(20));
      expect(revived.entityType, equals('session'));
      expect(revived.mediaType, equals('video'));
      expect(revived.durationSeconds, equals(45));
    });

    test(
      'Correctly serializes and deserializes audio attachment with duration',
      () {
        final att = MediaAttachment(
          id: 30,
          entityType: 'plan',
          entityId: 5,
          mediaType: 'audio',
          filePath: '/data/user/0/com.example.reptrack/files/reptrack_media/voice_789.m4a',
          title: 'Trainer Voice Cue',
          durationSeconds: 18,
        );

        final map = att.toMap();
        expect(map['id'], equals(30));
        expect(map['entity_type'], equals('plan'));
        expect(map['media_type'], equals('audio'));
        expect(map['duration_seconds'], equals(18));

        final revived = MediaAttachment.fromMap(map);
        expect(revived.mediaType, equals('audio'));
        expect(revived.durationSeconds, equals(18));
        expect(revived.title, equals('Trainer Voice Cue'));
      },
    );

    test('copyWith produces non-destructive replaced attachments', () {
      final original = MediaAttachment(
        id: 1,
        entityType: 'muscle',
        entityId: 2,
        mediaType: 'photo',
        filePath: '/old/path/old_image.jpg',
        title: 'Original Title',
        durationSeconds: null,
      );

      final updated = original.copyWith(
        filePath: '/new/path/new_image.jpg',
        title: 'Updated Title',
        durationSeconds: 12,
      );

      // Verify original is untouched
      expect(original.filePath, equals('/old/path/old_image.jpg'));
      expect(original.title, equals('Original Title'));
      expect(original.durationSeconds, isNull);

      // Verify updated has modified values while retaining identity
      expect(updated.id, equals(1));
      expect(updated.entityType, equals('muscle'));
      expect(updated.entityId, equals(2));
      expect(updated.mediaType, equals('photo'));
      expect(updated.filePath, equals('/new/path/new_image.jpg'));
      expect(updated.title, equals('Updated Title'));
      expect(updated.durationSeconds, equals(12));
    });

    test('Supports all 5 required attachment entity types', () {
      final allowedEntities = [
        'exercise',
        'muscle',
        'plan',
        'session',
        'workout_exercise',
      ];
      for (final entity in allowedEntities) {
        final att = MediaAttachment(
          entityType: entity,
          entityId: 100,
          mediaType: 'photo',
          filePath: '/path/$entity.jpg',
          title: '$entity Media',
        );
        expect(att.entityType, equals(entity));
        expect(att.entityId, equals(100));
      }
    });

    test('Supports all 3 required media types: photo, video, audio', () {
      final allowedTypes = ['photo', 'video', 'audio'];
      for (final type in allowedTypes) {
        final att = MediaAttachment(
          entityType: 'exercise',
          entityId: 1,
          mediaType: type,
          filePath: '/path/file.$type',
          title: '$type test',
        );
        expect(att.mediaType, equals(type));
      }
    });

    test('Filtering attachments by entityType and entityId isolates target attachments', () {
      final allAttachments = [
        MediaAttachment(
          id: 1,
          entityType: 'exercise',
          entityId: 10,
          mediaType: 'photo',
          filePath: 'p1.jpg',
          title: 'Ex 10 Photo',
        ),
        MediaAttachment(
          id: 2,
          entityType: 'exercise',
          entityId: 20,
          mediaType: 'video',
          filePath: 'v1.mp4',
          title: 'Ex 20 Video',
        ),
        MediaAttachment(
          id: 3,
          entityType: 'muscle',
          entityId: 10,
          mediaType: 'photo',
          filePath: 'p2.jpg',
          title: 'Muscle 10 Photo',
        ),
        MediaAttachment(
          id: 4,
          entityType: 'session',
          entityId: 5,
          mediaType: 'audio',
          filePath: 'a1.m4a',
          title: 'Session 5 Audio',
        ),
        MediaAttachment(
          id: 5,
          entityType: 'plan',
          entityId: 7,
          mediaType: 'video',
          filePath: 'v2.mp4',
          title: 'Plan 7 Video',
        ),
        MediaAttachment(
          id: 6,
          entityType: 'exercise',
          entityId: 10,
          mediaType: 'audio',
          filePath: 'a2.m4a',
          title: 'Ex 10 Audio',
        ),
      ];

      final ex10Attachments = allAttachments
          .where((a) => a.entityType == 'exercise' && a.entityId == 10)
          .toList();
      expect(ex10Attachments.length, equals(2));
      expect(ex10Attachments.any((a) => a.mediaType == 'photo'), isTrue);
      expect(ex10Attachments.any((a) => a.mediaType == 'audio'), isTrue);

      final sessionAttachments = allAttachments
          .where((a) => a.entityType == 'session' && a.entityId == 5)
          .toList();
      expect(sessionAttachments.length, equals(1));
      expect(sessionAttachments.first.title, equals('Session 5 Audio'));

      final muscleAttachments = allAttachments
          .where((a) => a.entityType == 'muscle')
          .toList();
      expect(muscleAttachments.length, equals(1));
      expect(muscleAttachments.first.title, equals('Muscle 10 Photo'));

      final planAttachments = allAttachments
          .where((a) => a.entityType == 'plan')
          .toList();
      expect(planAttachments.length, equals(1));
      expect(planAttachments.first.title, equals('Plan 7 Video'));
    });
  });
}
