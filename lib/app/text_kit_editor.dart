import 'package:flutter/material.dart';
import 'package:skapie/app/full_screen_text_editor.dart';
import 'package:skapie/kit_api/kit_api.dart';

/// Opens a text kit in the Full Screen text editor. Saving goes through [KitApi].
Future<void> showTextKitEditor({
  required BuildContext context,
  required KitApi kitApi,
  required String bodyId,
  required String title,
  required String content,
}) {
  return showFullScreenTextEditor(
    context: context,
    title: title,
    text: content,
    surfaceKey: const Key('text-kit-editor'),
    fieldKey: const Key('text-kit-editor-field'),
    closeKey: const Key('text-kit-editor-close'),
    onSave: (value) {
      if (value == content) {
        return;
      }
      kitApi.updateProps(bodyId, {'content': value});
    },
  );
}
