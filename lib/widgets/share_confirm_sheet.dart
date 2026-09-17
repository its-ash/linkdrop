import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

class ShareConfirmSheet extends StatelessWidget {
  const ShareConfirmSheet({super.key, required this.url});

  final String url;

  static Future<bool> show(BuildContext context, String url) async {
    final result = await ThemeBottomSheet.show<bool>(
      context,
      isScrollControlled: true,
      builder: (context) => ShareConfirmSheet(url: url),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, size: 22),
              const SizedBox(width: 8),
              Text(
                'Download this link?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ThemeCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(url, maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ThemeButton(
                  label: 'Cancel',
                  variant: ThemeButtonVariant.outlined,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ThemeButton(
                  label: 'Download',
                  icon: Icons.download_outlined,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
