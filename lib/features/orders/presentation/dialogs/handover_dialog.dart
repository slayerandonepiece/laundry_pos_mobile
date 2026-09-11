import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:myshop/core/constants/app_colors.dart';
import 'package:myshop/features/orders/bloc/orders_bloc.dart';
import 'package:myshop/features/orders/bloc/orders_event.dart';
import 'package:myshop/features/orders/bloc/orders_state.dart';
import 'package:myshop/features/orders/data/models/order_model.dart';
import 'package:myshop/shared/widgets/centred_dialog.dart';

class HandoverDialog {
  static Future<void> show(BuildContext context, {required Order order}) {
    return showDialog(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => BlocProvider.value(
        value: context.read<OrdersBloc>(),
        child: BlocConsumer<OrdersBloc, OrdersState>(
          listener: (context, state) {
            if (state.actionSuccessMessage != null) {
              Navigator.pop(context);
            } else if (state.error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.error!),
                  backgroundColor: AppColors.danger,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          builder: (context, state) {
            return CentredDialog(
              title: 'Hand over order?',
              subtitle:
                  'Mark order ${order.orderCode} for ${order.name.isNotEmpty ? order.name : order.phone} as delivered and generate customer invoice?',
              confirmLabel: 'Hand over',
              cancelLabel: 'Cancel',
              isLoading: state.isUpdatingStatus,
              onConfirm: state.isUpdatingStatus
                  ? null
                  : () {
                      context.read<OrdersBloc>().add(
                        HandoverOrderEvent(order.orderCode),
                      );
                    },
              onCancel: state.isUpdatingStatus
                  ? null
                  : () => Navigator.pop(context),
            );
          },
        ),
      ),
    );
  }
}
