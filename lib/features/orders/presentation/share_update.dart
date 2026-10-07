import 'package:flutter/material.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/core/constants/api_endpoints.dart';
import 'package:myshop/core/logging/app_logger.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/features/orders/data/orders_repository.dart';
import 'package:share_plus/share_plus.dart';

/// Share update: drafts the customer message for the order's current status
/// (from the organization's template, via the server) and opens the system
/// share sheet. Link only, no PDF, as on web.
Future<void> shareOrderUpdate(
  BuildContext context,
  OrdersRepository repository,
  Order order,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text, {bool error = false}) => messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.danger : null,
      behavior: SnackBarBehavior.floating,
    ),
  );

  // An order created offline has no server copy yet, so no public link.
  if (order.id.isEmpty) {
    say('Sync this order first, then share an update.');
    return;
  }
  try {
    final message = await repository.getOrderMessage(order.orderCode);
    if (!message.enabled) {
      say('Customer messages are off for this status.');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(text: message.compose(ApiEndpoints.baseUrl)),
    );
  } catch (e) {
    AppLogger.log('SHARE_UPDATE', 'share update failed', error: e);
    say(
      'Needs internet to draft the message — try again when online.',
      error: true,
    );
  }
}
