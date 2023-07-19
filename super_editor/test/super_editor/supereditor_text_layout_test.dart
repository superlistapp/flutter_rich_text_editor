import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_text_layout/super_text_layout_inspector.dart';

import '../test_tools.dart';
import 'document_test_tools.dart';

void main() {
  group('SuperEditor', () {
    testWidgetsOnAllPlatforms('respects the OS text scaling preference', (tester) async {
      // Pump an editor with a custom textScaler.

      const scaler = TextScaler.linear(1.5);

      await tester
          .createDocument()
          .withSingleParagraph()
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(textScaler: scaler),
                  child: superEditor,
                ),
              ),
            ),
          )
          .pump();

      // Ensure the configure textScaleFactor was applied.
      expect(SuperTextInspector.findTextScaler(), scaler);
    });
  });
}
