import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

class ShareConfirmSheet extends StatelessWidget {
  const ShareConfirmSheet({super.key, required this.url});

  final String url;

  static Future<bool> show(BuildContext context, String url) async {
    final result = await UiSheet.show<bool>(
      context,
      title: 'Download this link?',
      actions: [
        Builder(
          builder: (context) =>
              UiButton('Cancel', variant: UiButtonVariant.outline, onPressed: () => Navigator.pop(context, false)),
        ),
        Builder(
          builder: (context) =>
              UiButton('Download', icon: Icons.download_outlined, onPressed: () => Navigator.pop(context, true)),
        ),
      ],
      child: ShareConfirmSheet(url: url),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return UiCard(
      padding: const EdgeInsets.all(UiSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link, size: 20, color: context.colors.textMuted),
          const SizedBox(width: UiSpace.sm),
          Expanded(child: Text(url, maxLines: 3, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
