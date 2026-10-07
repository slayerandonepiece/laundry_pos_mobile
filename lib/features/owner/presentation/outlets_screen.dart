import 'package:flutter/material.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/storage/local_cache.dart';
import 'package:myshop/core/theme/text_styles.dart';
import 'package:myshop/features/shell/data/models/outlet_model.dart';
import 'package:myshop/shared/widgets/app_card.dart';

/// More > Outlets. The organization's outlets, as the last sign-in or
/// session check returned them. The server only lists active outlets, so
/// there is nothing to filter. Managing outlets is done on the web.
class OutletsScreen extends StatelessWidget {
  const OutletsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final outlets = [
      for (final o in LocalCacheService().getAllowedOutlets() ?? const [])
        Outlet.fromJson(Map<String, dynamic>.from(o)),
    ];
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: const Text(
          'Outlets',
          style: TextStyle(
            fontFamily: AppTextStyles.fontDisplay,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Your branches. Add or edit outlets on the web.',
            style: AppTextStyles.hint,
          ),
          const SizedBox(height: 16),
          if (outlets.isEmpty)
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Text('No outlets yet', style: AppTextStyles.hint),
            ),
          for (final o in outlets) ...[
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.displayName,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontBody,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Outlet code ${o.outletCode}',
                          style: AppTextStyles.hint,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
