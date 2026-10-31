import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/shell/bloc/outlet_scope_cubit.dart';

extension LargeTextContext on BuildContext {
  /// True at big accessibility text sizes, where side-by-side tags and chips
  /// no longer fit and are stacked under their text instead.
  bool get largeText => MediaQuery.textScalerOf(this).scale(10) > 13;
}

extension OutletBlockedContext on BuildContext {
  /// True when [outletId] (or, without one, the outlet being viewed) is
  /// blocked until it is paid. Rebuilds the caller when billing changes.
  bool outletBlocked([String? outletId]) {
    final scope = watch<OutletScopeCubit?>()?.state;
    if (scope == null) return false;
    return outletId == null || outletId.isEmpty
        ? scope.activeOutletBlocked
        : scope.isBlocked(outletId);
  }
}
