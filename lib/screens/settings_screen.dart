import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

/// Settings: updates and developer info.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      appBar: const UiAppBar(title: 'Settings'),
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiListGroup(
            header: 'About',
            children: [
              UiListTile(
                'Open-source licences',
                icon: Icons.description_rounded,
                chevron: true,
                onTap: () => showLicensePage(context: context, applicationName: 'LinkDrop'),
              ),
            ],
          ),
          const UiGap(UiSpace.lg),
          const UiAppearanceSection(),
          const UiGap(UiSpace.lg),
          const UiUpdateSection(storeId: 'linkdrop'),
          const UiGap(UiSpace.lg),
          const UiDeveloperSection(),
        ],
      ),
    );
  }
}
