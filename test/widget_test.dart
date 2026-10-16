import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/widgets/exercise_image_widget.dart';

void main() {
  testWidgets('RepTrack theme and ExerciseImageWidget smoke test', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: ExerciseImageWidget(
            exerciseName: 'Standing Dumbbell Curl',
            imagePath: 'assets/images/exercises/standing_dumbbell_curl.jpg',
          ),
        ),
      ),
    );

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(ExerciseImageWidget), findsOneWidget);
  });
}
