import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import '../network/api_exceptions.dart';
import '../storage/local_cache.dart';

const _tag = 'SERVER_ACTIONS';

/// Something only the server can decide (cancel an order, delete or edit an
/// expense, ...). It is tracked here instead of making the user wait: the
/// screen shows it as "processing", and the sync sends it in the background.
class ServerAction {
  static const String queued = 'queued';
  static const String failed = 'failed';

  final String id;
  final String type;

  /// The order code / expense id the action is about, so a screen can tag it.
  final String targetId;

  /// What the screen shows next to it, e.g. "Cancelling…".
  final String label;

  /// What the Pending requests list says, e.g. "Cancel order 1000000002".
  final String summary;
  final Map<String, dynamic> payload;
  final String status;
  final String? lastError;
  final DateTime createdAt;

  const ServerAction({
    required this.id,
    required this.type,
    required this.targetId,
    required this.label,
    required this.summary,
    required this.payload,
    required this.status,
    required this.createdAt,
    this.lastError,
  });

  bool get isFailed => status == failed;

  ServerAction copyWith({String? status, String? lastError}) => ServerAction(
    id: id,
    type: type,
    targetId: targetId,
    label: label,
    summary: summary,
    payload: payload,
    status: status ?? this.status,
    lastError: lastError ?? this.lastError,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'targetId': targetId,
    'label': label,
    'summary': summary,
    'payload': payload,
    'status': status,
    'lastError': lastError,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ServerAction.fromJson(Map<String, dynamic> json) => ServerAction(
    id: json['id'].toString(),
    type: json['type'].toString(),
    targetId: json['targetId'].toString(),
    label: json['label']?.toString() ?? 'Processing…',
    summary: json['summary']?.toString() ?? json['type'].toString(),
    payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
    status: json['status']?.toString() ?? queued,
    lastError: json['lastError']?.toString(),
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
  );
}

typedef ServerActionHandler = Future<void> Function(ServerAction action);

/// The queue for actions that need the server. Kept apart from the order and
/// owner queues because these are not local edits: nothing changes on the
/// phone until the server says yes, so the screens only show a "processing"
/// tag meanwhile. Failures the server explains stay visible until retried or
/// dismissed; slow or unreachable servers just keep the item queued.
class ServerActionQueue {
  ServerActionQueue._(this._cache);

  static ServerActionQueue instance = ServerActionQueue._(LocalCacheService());

  @visibleForTesting
  static ServerActionQueue forTesting(LocalCacheService cache) =>
      ServerActionQueue._(cache);

  final LocalCacheService _cache;
  final Set<String> _processing = {};
  bool _running = false;

  /// Every action on the phone, oldest first. Screens listen to this to show
  /// tags and to reload when an action finishes.
  final ValueNotifier<List<ServerAction>> actions = ValueNotifier(const []);

  List<ServerAction> _read() {
    try {
      return [
        for (final m in _cache.getServerActions()) ServerAction.fromJson(m),
      ];
    } catch (e) {
      AppLogger.log(_tag, 'cannot read queue', error: e);
      return const [];
    }
  }

  Future<void> _write(List<ServerAction> list) async {
    await _cache.setServerActions([for (final a in list) a.toJson()]);
    actions.value = List.unmodifiable(list);
  }

  /// Loads what is stored (app start, sign-in).
  void reload() => actions.value = List.unmodifiable(_read());

  ServerAction? forTarget(String targetId) {
    for (final a in actions.value) {
      if (a.targetId == targetId) return a;
    }
    return null;
  }

  bool isProcessing(String id) => _processing.contains(id);

  /// Adds an action and returns at once. Refuses a second action on the same
  /// target while one is still waiting, so two requests never race.
  Future<ServerAction> enqueue({
    required String type,
    required String targetId,
    required String label,
    String? summary,
    Map<String, dynamic> payload = const {},
  }) async {
    final list = _read();
    final waiting = list.where((a) => a.targetId == targetId && !a.isFailed);
    if (waiting.isNotEmpty) {
      throw StateError('A request for this is already processing.');
    }
    final action = ServerAction(
      id: 'sa_${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      targetId: targetId,
      label: label,
      summary: summary ?? label,
      payload: payload,
      status: ServerAction.queued,
      createdAt: DateTime.now(),
    );
    // A rejected earlier attempt on the same target is replaced by this one.
    await _write([...list.where((a) => a.targetId != targetId), action]);
    return action;
  }

  /// Sends queued actions in order. Returns false if it stopped early because
  /// the server was slow or unreachable (they stay queued and are retried).
  /// A server refusal parks that action as failed and moves on; a signed-out
  /// session is rethrown for the sync engine to handle.
  Future<bool> process(Map<String, ServerActionHandler> handlers) async {
    if (_running) return true;
    _running = true;
    var allDone = true;
    try {
      for (final action in _read().where((a) => !a.isFailed)) {
        final handler = handlers[action.type];
        if (handler == null) {
          await _finish(
            action.id,
            failure: 'This request is no longer supported.',
          );
          continue;
        }
        _processing.add(action.id);
        actions.value = List.unmodifiable(_read());
        try {
          await handler(action);
          await _finish(action.id);
        } catch (e) {
          if (e is AuthException && e.statusCode == 401) rethrow;
          if (_isRefusal(e)) {
            AppLogger.log(_tag, '${action.type} refused', error: e);
            await _finish(action.id, failure: _reason(e));
          } else {
            AppLogger.log(_tag, '${action.type} will retry', error: e);
            allDone = false;
            break;
          }
        } finally {
          _processing.remove(action.id);
        }
      }
    } finally {
      _running = false;
      actions.value = List.unmodifiable(_read());
    }
    return allDone;
  }

  /// The server answered and said no (as opposed to being slow or down).
  static bool _isRefusal(Object e) {
    if (e is! ApiException) return false;
    final code = e.statusCode;
    if (code == null) return false;
    return code >= 400 &&
        code < 500 &&
        code != 401 &&
        code != 408 &&
        code != 429;
  }

  static String _reason(Object e) =>
      e is ApiException ? e.message : e.toString();

  Future<void> _finish(String id, {String? failure}) async {
    final list = _read();
    if (failure == null) {
      await _write([...list.where((a) => a.id != id)]);
    } else {
      await _write([
        for (final a in list)
          a.id == id
              ? a.copyWith(status: ServerAction.failed, lastError: failure)
              : a,
      ]);
    }
  }

  /// "Retry" on failed actions: put them back in the queue.
  Future<void> reviveFailed() async {
    final list = _read();
    if (!list.any((a) => a.isFailed)) return;
    await _write([
      for (final a in list)
        a.isFailed ? a.copyWith(status: ServerAction.queued) : a,
    ]);
  }

  Future<void> dismiss(String id) async =>
      _write([..._read().where((a) => a.id != id)]);
}
