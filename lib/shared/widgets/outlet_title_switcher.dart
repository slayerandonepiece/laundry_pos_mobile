import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/app_colors.dart';
import '../../core/sync/connectivity_service.dart';
import '../../core/theme/text_styles.dart';
import '../../features/shell/bloc/outlet_scope_cubit.dart';

class OutletTitleSwitcher extends StatefulWidget {
  final String screenLabel;
  final bool showAllOutletsOption;
  final String? subtitle;

  const OutletTitleSwitcher({
    super.key,
    required this.screenLabel,
    this.showAllOutletsOption = false,
    this.subtitle,
  });

  @override
  State<OutletTitleSwitcher> createState() => _OutletTitleSwitcherState();
}

class _OutletTitleSwitcherState extends State<OutletTitleSwitcher> {
  bool _menuOpen = false;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.isEmpty
        ? '?'
        : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  Future<void> _openMenu(
    BuildContext context,
    OutletScopeCubit cubit,
    OutletScope scope,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final targetRect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final position = RelativeRect.fromRect(
      targetRect,
      Offset.zero & overlay.size,
    );

    final messenger = ScaffoldMessenger.maybeOf(context);

    void handleSelectAll() {
      final cached = cubit.hasCachedOrdersFor(allOutlets: true);
      if (ConnectivityService.instance.isOffline && !cached) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              "All outlets isn't on this phone yet. Connect to the internet to open it.",
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      cubit.selectAllOutlets();
    }

    void handleSelectOutlet(String outletId, String displayName) {
      final cached = cubit.hasCachedOrdersFor(
        outletId: outletId,
        allOutlets: false,
      );
      if (ConnectivityService.instance.isOffline && !cached) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              "$displayName isn't on this phone yet. Connect to the internet to open it.",
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      cubit.select(outletId);
    }

    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        enabled: false,
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: Text(
          'SWITCH OUTLET',
          style: TextStyle(
            fontFamily: AppTextStyles.fontBody,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
            color: AppColors.mutedText,
          ),
        ),
      ),
      if (widget.showAllOutletsOption && scope.isOwner)
        PopupMenuItem<String>(
          value: '__all__',
          onTap: handleSelectAll,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: _MenuOutletRow(
            avatar: const Icon(
              Icons.grid_view_rounded,
              size: 15,
              color: Colors.white,
            ),
            avatarSelected: scope.allOutlets,
            title: 'All outlets',
            subtitle: 'Every branch combined',
            subtitleColor: AppColors.mutedText,
            isSelected: scope.allOutlets,
            showCloudDownload: false,
          ),
        ),
      ...scope.allowed.map((outlet) {
        final isSelected =
            !scope.allOutlets && outlet.id == scope.activeOutletId;
        final isCached = cubit.hasCachedOrdersFor(
          outletId: outlet.id,
          allOutlets: false,
        );
        final rowSubtitle = isCached
            ? '${outlet.outletCode} · On this phone'
            : 'Not on this phone yet';
        final subtitleColor = isCached ? AppColors.success : AppColors.warning;
        return PopupMenuItem<String>(
          value: outlet.id,
          onTap: () => handleSelectOutlet(outlet.id, outlet.displayName),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: _MenuOutletRow(
            avatar: Text(
              _initials(outlet.displayName),
              style: TextStyle(
                fontFamily: AppTextStyles.fontDisplay,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : AppColors.mutedText,
              ),
            ),
            avatarSelected: isSelected,
            title: outlet.displayName,
            subtitle: rowSubtitle,
            subtitleColor: subtitleColor,
            isSelected: isSelected,
            showCloudDownload: !isCached && !isSelected,
          ),
        );
      }),
    ];

    setState(() => _menuOpen = true);
    await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: AppColors.surface,
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 300),
      items: items,
    );
    if (mounted) {
      setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<OutletScopeCubit?>();
    final scope = cubit?.state ?? const OutletScope.empty();

    final hasChoice =
        scope.allowed.length > 1 ||
        (scope.isOwner && widget.showAllOutletsOption);

    final String outletLabel;
    if (scope.allOutlets) {
      outletLabel = 'All outlets';
    } else if (scope.allowed.isEmpty) {
      outletLabel = widget.screenLabel;
    } else {
      outletLabel =
          scope.allowed
              .where((o) => o.id == scope.activeOutletId)
              .map((o) => o.displayName)
              .firstOrNull ??
          (scope.allowed.length == 1
              ? scope.allowed.first.displayName
              : 'Select outlet');
    }

    final topLine = (widget.subtitle != null && widget.subtitle!.isNotEmpty)
        ? '${widget.screenLabel.toUpperCase()} · ${widget.subtitle}'
        : widget.screenLabel.toUpperCase();

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            topLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontBody,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: AppColors.mutedText,
            ),
          ),
          const SizedBox(height: 1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  outletLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontDisplay,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (hasChoice) ...[
                const SizedBox(width: 2),
                Icon(
                  _menuOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.mutedText,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (!hasChoice || cubit == null) {
      return content;
    }

    return InkWell(
      onTap: () => _openMenu(context, cubit, scope),
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _MenuOutletRow extends StatelessWidget {
  final Widget avatar;
  final bool avatarSelected;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final bool isSelected;
  final bool showCloudDownload;

  const _MenuOutletRow({
    required this.avatar,
    required this.avatarSelected,
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    required this.isSelected,
    required this.showCloudDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 284,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryTint : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: avatarSelected ? AppColors.primary : AppColors.neutralBg,
            ),
            child: Center(child: avatar),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontBody,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
          ),
          if (showCloudDownload)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(
                Icons.cloud_download_outlined,
                size: 15,
                color: AppColors.mutedText,
              ),
            ),
          if (isSelected)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(
                Icons.check_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }
}
