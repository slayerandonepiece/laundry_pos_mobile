import 'package:bloc/bloc.dart';

import '../../../core/storage/local_cache.dart';
import '../data/models/outlet_model.dart';

/// The signed-in user's current outlet scope: which outlets they may operate
/// under, and whether they're viewing one specific outlet or (owners only)
/// every outlet at once.
class OutletScope {
  final List<Outlet> allowed;
  final String? activeOutletId;
  final bool allOutlets;
  final bool isOwner;

  /// True when organizations[] has never been cached for this employee.
  /// Distinguishes "employee genuinely has zero outlets" (render O4) from
  /// "outlets not cached yet" (force re-auth instead of guessing).
  final bool missingCache;

  const OutletScope({
    required this.allowed,
    required this.activeOutletId,
    required this.allOutlets,
    required this.isOwner,
    this.missingCache = false,
  });

  const OutletScope.empty()
    : allowed = const [],
      activeOutletId = null,
      allOutlets = false,
      isOwner = false,
      missingCache = false;

  const OutletScope.missingCache()
    : allowed = const [],
      activeOutletId = null,
      allOutlets = false,
      isOwner = false,
      missingCache = true;

  /// Employee assigned to zero outlets — every order call 403s by design
  /// (O4): block the shell, don't render orders/New sale behind it.
  bool get blockedNoOutlet => !isOwner && !missingCache && allowed.isEmpty;

  /// Employee with more than one outlet and none chosen yet: block the shell
  /// until they pick one (O3).
  bool get requiresSelection =>
      !isOwner && allowed.length > 1 && activeOutletId == null && !allOutlets;
}

/// Owns outlet-scope storage/state and is the only writer of the
/// LocalCacheService outlet keys (O2.1/O2.2). Every method re-derives the
/// emitted state from cache via [hydrate], so callers never have to keep the
/// write and the read-back in sync by hand.
class OutletScopeCubit extends Cubit<OutletScope> {
  final LocalCacheService _localCache;

  OutletScopeCubit({LocalCacheService? localCache})
    : _localCache = localCache ?? LocalCacheService(),
      super(const OutletScope.empty());

  /// Reads whatever is cached for the active store — on cold start,
  /// `checkSession` refreshes outlets from `/auth/status` (contract §2) before
  /// [hydrate] runs; also called after any write below.
  void hydrate() {
    final storeDetails = _localCache.getCachedStoreDetails();
    final isOwner =
        storeDetails != null &&
        storeDetails['role']?.toString().toUpperCase() == 'OWNER';
    final allowedMaps = _localCache.getAllowedOutlets();

    // Employees have no sensible default when nothing is cached yet (e.g.
    // first launch after this feature shipped, or a token surviving a data
    // clear) — force a fresh sign-in rather than guessing an outlet (O7).
    // Owners always have a sensible default (All outlets), so this only
    // applies to employees.
    if (allowedMaps == null && !isOwner) {
      emit(const OutletScope.missingCache());
      return;
    }

    final allowed = (allowedMaps ?? const []).map(Outlet.fromJson).toList();
    var activeOutletId = _localCache.getActiveOutletId();
    if (activeOutletId != null && !allowed.any((o) => o.id == activeOutletId)) {
      _localCache.clearActiveOutletId();
      activeOutletId = null;
    }

    if (allowed.length == 1) {
      activeOutletId = allowed.first.id;
      _localCache.setActiveOutletId(activeOutletId);
      _localCache.setAllOutletsScope(false);
    }

    // Owners default to All outlets (O3) whenever nothing has been narrowed
    // yet for this store; an explicit prior selection (activeOutletId set)
    // or an explicit "All outlets" tap both stay respected.
    final allOutlets = (allowed.length == 1)
        ? false
        : (isOwner
              ? (activeOutletId == null
                    ? true
                    : _localCache.isAllOutletsScope())
              : _localCache.isAllOutletsScope());

    emit(
      OutletScope(
        allowed: allowed,
        activeOutletId: allOutlets ? null : activeOutletId,
        allOutlets: allOutlets,
        isOwner: isOwner,
      ),
    );
  }

  bool hasCachedOrdersFor({String? outletId, required bool allOutlets}) =>
      _localCache.hasCachedOrdersFor(
        outletId: outletId,
        allOutlets: allOutlets,
      );

  /// Applies the O3 initial-scope defaults right after a fresh login, then
  /// hydrates from what was just written.
  void adoptFromLogin({required bool isOwner}) {
    final allowed = (_localCache.getAllowedOutlets() ?? const [])
        .map(Outlet.fromJson)
        .toList();

    if (allowed.length == 1) {
      _localCache.setActiveOutletId(allowed.first.id);
      _localCache.setAllOutletsScope(false);
    } else if (isOwner) {
      _localCache.setAllOutletsScope(true);
      _localCache.clearActiveOutletId();
    } else {
      // 0 or >=2 outlets: reuse the outlet this employee picked last time
      // in this organization, if still allowed; otherwise O4's blocked
      // screen or the outlet picker takes over from here.
      final key = _rememberedOutletKey();
      final remembered = key == null
          ? null
          : _localCache.getRememberedOutlet(key.$1, key.$2);
      if (remembered != null && allowed.any((o) => o.id == remembered)) {
        _localCache.setActiveOutletId(remembered);
      } else {
        _localCache.clearActiveOutletId();
      }
      _localCache.setAllOutletsScope(false);
    }

    hydrate();
  }

  /// Employee (or owner) narrows to one specific outlet.
  void select(String outletId) {
    _localCache.setActiveOutletId(outletId);
    _localCache.setAllOutletsScope(false);
    final key = _rememberedOutletKey();
    if (key != null) {
      _localCache.setRememberedOutlet(key.$1, key.$2, outletId);
    }
    hydrate();
  }

  /// Actions queued offline and not yet on the server.
  bool get hasPendingChanges => _localCache.getTotalPendingCount() > 0;

  bool _switching = false;

  /// True while [selectClearingPrevious] is running, so a second tap cannot
  /// start a concurrent switch.
  bool get isSwitching => _switching;

  /// Employee switching outlets: only the outlet in use is kept on the phone,
  /// but the outgoing outlet's cached orders, delta cursor, dashboard and
  /// expenses are dropped only once the new outlet has synced, so a dropped
  /// connection or a killed app mid-switch never leaves the phone with data
  /// for neither. The pending queues are left alone — queued actions carry
  /// their own outlet id and must still flush to it — which is why callers
  /// flush first.
  ///
  /// [syncNewScope] runs after the new outlet is selected and reports whether
  /// it synced. When it did not, the previous outlet (and its cache) is put
  /// back and false is returned. Without it the previous outlet is cleared
  /// straight after the switch. Returns false too when a switch is already
  /// running.
  Future<bool> selectClearingPrevious(
    String outletId, {
    Future<bool> Function()? syncNewScope,
  }) async {
    if (_switching) return false;
    _switching = true;
    try {
      final previous = _localCache.getActiveOutletId();
      select(outletId);
      if (previous == null || previous == outletId) return true;
      if (syncNewScope != null && !await syncNewScope()) {
        if (!isClosed) select(previous);
        return false;
      }
      await _localCache.clearScopeData(previous);
      return true;
    } finally {
      _switching = false;
    }
  }

  /// (user id, organization id) the remembered outlet is stored under, or
  /// null when either isn't cached.
  (String, String)? _rememberedOutletKey() {
    final userId = _localCache.getCachedUser()?['id']?.toString() ?? '';
    if (userId.isEmpty) return null;
    final storeId = _localCache.getActiveStoreId() ?? '';
    if (storeId.isEmpty) return null;
    return (userId, storeId);
  }

  /// Owner only: view every outlet at once.
  void selectAllOutlets() {
    _localCache.setAllOutletsScope(true);
    _localCache.clearActiveOutletId();
    hydrate();
  }

  /// Signed out, or the active outlet was revoked mid-session — drop back to
  /// nothing-selected without touching cached allowedOutlets (those are
  /// re-derived from cache on the next hydrate/adoptFromLogin).
  void clearSelection() {
    _localCache.clearActiveOutletId();
    _localCache.clearAllOutletsScope();
    hydrate();
  }

  /// Full reset on logout, before a different user's data is cached.
  void reset() {
    emit(const OutletScope.empty());
  }
}
