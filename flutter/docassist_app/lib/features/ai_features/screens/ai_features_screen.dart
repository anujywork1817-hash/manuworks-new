import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/router.dart';
import 'ai_feature_detail_screen.dart';

/// Standalone AI Features screen — reachable directly from the Dashboard's
/// "AI Features" shortcut. Tapping any tile opens that feature's own
/// screen (with its heading + a document upload/pick option).
class AiFeaturesScreen extends StatelessWidget {
  const AiFeaturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
          SizedBox(width: 6),
          Text('AI Features'),
        ]),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Choose a feature to get started.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisExtent: 92,
              ),
              itemCount: kAiFeatures.length,
              itemBuilder: (context, index) {
                final f = kAiFeatures[index];
                return InkWell(
                  onTap: () => context.push('${AppRoutes.aiFeatures}/${f.id}'),
                  borderRadius: AppRadius.md,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.md,
                      border: Border.all(color: AppColors.outline),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(f.icon, color: AppColors.textSecondary, size: 24),
                        const SizedBox(height: 6),
                        Text(
                          f.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ]),
        ),
      ),
    );
  }
}