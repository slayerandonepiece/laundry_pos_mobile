import '../../../../core/utils/quantity_formatter.dart';

class OrderLine {
  final String productId;
  final String name;
  final double quantity;
  final String unit; // 'PIECE' | 'WEIGHT'
  final int amount;

  OrderLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.amount,
  });

  factory OrderLine.fromJson(Map<String, dynamic> json) {
    return OrderLine(
      productId: json['productId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: json['unit']?.toString() ?? 'PIECE',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
    );
  }

  String get productName => name;
  int get totalAmount => amount;
  bool get isWeight =>
      unit.toLowerCase() == 'weight' || unit.toLowerCase() == 'kg';

  String get displayQuantity => isWeight
      ? QuantityFormatter.formatWeight(quantity)
      : '${quantity.toInt()} pcs';

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'amount': amount,
    };
  }
}

class OrderPayment {
  final String id;
  final int amount;
  final String date;
  final String method;

  OrderPayment({
    required this.id,
    required this.amount,
    required this.date,
    required this.method,
  });

  factory OrderPayment.fromJson(Map<String, dynamic> json) {
    return OrderPayment(
      id: json['id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      date: json['date']?.toString() ?? '',
      method: json['method']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'amount': amount, 'date': date, 'method': method};
  }
}

class OrderHistoryEvent {
  final String status;
  final String at;
  final String by;

  OrderHistoryEvent({required this.status, required this.at, required this.by});

  factory OrderHistoryEvent.fromJson(Map<String, dynamic> json) {
    return OrderHistoryEvent(
      status: json['status']?.toString() ?? 'Pending',
      at: json['at']?.toString() ?? '',
      by: json['by']?.toString() ?? 'Staff',
    );
  }

  DateTime get timestamp => DateTime.tryParse(at)?.toLocal() ?? DateTime.now();
  String get actorName => by;

  Map<String, dynamic> toJson() {
    return {'status': status, 'at': at, 'by': by};
  }
}

class InvoiceInfo {
  final bool exists;
  final int? invoiceSeq;
  final String? accessToken;
  final bool canGenerate;
  final DateTime? generatedAt;

  InvoiceInfo({
    required this.exists,
    this.invoiceSeq,
    this.accessToken,
    this.canGenerate = false,
    this.generatedAt,
  });

  String get formattedInvoiceNumber {
    if (invoiceSeq == null) return '';
    return 'INV-${invoiceSeq.toString().padLeft(6, '0')}';
  }

  String get invoiceNumber => formattedInvoiceNumber;
  DateTime get issuedAt => generatedAt ?? DateTime.now();

  factory InvoiceInfo.fromJson(Map<String, dynamic> json) {
    return InvoiceInfo(
      exists: json['exists'] == true,
      invoiceSeq: (json['invoiceSeq'] as num?)?.toInt(),
      accessToken: json['accessToken']?.toString(),
      canGenerate: json['canGenerate'] == true,
      generatedAt: json['generatedAt'] != null
          ? DateTime.tryParse(json['generatedAt'].toString())?.toLocal()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'exists': exists,
      'invoiceSeq': invoiceSeq,
      'accessToken': accessToken,
      'canGenerate': canGenerate,
      if (generatedAt != null) 'generatedAt': generatedAt!.toIso8601String(),
    };
  }
}

class Order {
  final String id; // Server order code (e.g. EL-123); empty until synced

  /// App-generated id (UUID) for orders created or edited on this phone;
  /// null for web orders the app never touched. See
  /// docs/OFFLINE-ID-SYNC-PLAN.md §3.
  final String? offlineId;
  final String name; // Customer name
  final String phone;
  final String date; // Order date YYYY-MM-DD
  final String due; // Due date YYYY-MM-DD
  final String? completed;
  final String status; // 'Pending' | 'In Progress' | 'Ready' | 'Delivered'
  final List<OrderLine> lines;
  final List<OrderPayment> payments;
  final String notes;
  final List<OrderHistoryEvent> history;
  final InvoiceInfo? invoice;

  /// True once the backend has confirmed this order (always true for server-fetched orders).
  final bool isSynced;

  /// The outlet this order belongs to, or null for an org-wide/legacy order
  /// (no outlet assigned). See O5.3 in docs/OUTLET-PARITY-SPEC.md.
  final String? outletId;

  Order({
    required this.id,
    this.offlineId,
    required this.name,
    required this.phone,
    required this.date,
    required this.due,
    this.completed,
    required this.status,
    required this.lines,
    required this.payments,
    this.notes = '',
    this.history = const [],
    this.invoice,
    this.isSynced = true,
    this.outletId,
  });

  int get totalAmount => lines.fold(0, (sum, line) => sum + line.amount);
  int get paidAmount => payments.fold(0, (sum, p) => sum + p.amount);
  int get balanceDue {
    final diff = totalAmount - paidAmount;
    return diff > 0 ? diff : 0;
  }

  bool get isPaidInFull => balanceDue == 0 && totalAmount > 0;
  bool get isDelivered => status == 'Delivered';
  bool get isReady => status == 'Ready';
  bool get isInProgress => status == 'In Progress';
  bool get isPending => status == 'Pending';

  /// Local key for bloc events and repository calls: the server code once
  /// synced, else the offline id.
  String get orderCode => id.isNotEmpty ? id : (offlineId ?? '');

  /// What the user sees: the server code, or `OFF-` + the last 6 characters
  /// of the offline id while the order is unsynced.
  String get displayCode {
    if (id.isNotEmpty) return id;
    final off = offlineId ?? '';
    final tail = off.length > 6 ? off.substring(off.length - 6) : off;
    return 'OFF-${tail.toUpperCase()}';
  }

  bool isSameOrder(Order other) => jsonSameOrder(
    {'id': id, 'offlineId': offlineId},
    {'id': other.id, 'offlineId': other.offlineId},
  );

  /// True when a cached order map is the order a [ref] (an [orderCode])
  /// points at.
  static bool jsonMatchesRef(Map<String, dynamic> json, String ref) =>
      ref.isNotEmpty && (json['id'] == ref || json['offlineId'] == ref);

  /// True when two order maps are the same order: equal non-empty ids, else
  /// equal non-empty offline ids.
  static bool jsonSameOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aId = a['id']?.toString() ?? '';
    final bId = b['id']?.toString() ?? '';
    if (aId.isNotEmpty && bId.isNotEmpty) return aId == bId;
    final aOff = a['offlineId']?.toString() ?? '';
    return aOff.isNotEmpty && aOff == b['offlineId']?.toString();
  }

  /// A server order map merged over the cached one: keeps the cached
  /// offline id and invoice when the server has none.
  static Map<String, dynamic> mergeServerJson(
    Map<String, dynamic>? cached,
    Map<String, dynamic> server,
  ) {
    final serverOff = server['offlineId']?.toString() ?? '';
    final cachedOff = cached?['offlineId']?.toString() ?? '';
    final keepOff = serverOff.isEmpty && cachedOff.isNotEmpty;
    final cachedInv = cached?['invoice'];
    final keepInv = server['invoice'] == null && cachedInv != null;
    if (!keepOff && !keepInv) return server;
    return {
      ...server,
      if (keepOff) 'offlineId': cachedOff,
      if (keepInv) 'invoice': cachedInv,
    };
  }

  /// False when [date] is missing/unparseable, in which case [createdAt] is
  /// only a "now" placeholder that filters must not treat as a real date.
  bool get hasValidCreatedDate => DateTime.tryParse(date) != null;
  bool get hasValidDueDate => DateTime.tryParse(due) != null;

  DateTime get createdAt =>
      DateTime.tryParse(date)?.toLocal() ?? DateTime.now();
  DateTime get dueDateTime =>
      DateTime.tryParse(due)?.toLocal() ?? DateTime.now();

  factory Order.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] as List? ?? [];
    final rawPayments = json['payments'] as List? ?? [];
    final rawHistory = json['history'] as List? ?? [];
    final rawInvoice = json['invoice'] as Map<String, dynamic>?;

    return Order(
      id: json['id']?.toString() ?? '',
      offlineId: (json['offlineId']?.toString() ?? '').isEmpty
          ? null
          : json['offlineId'].toString(),
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      due: json['due']?.toString() ?? '',
      completed: json['completed']?.toString(),
      status: json['status']?.toString() ?? 'Pending',
      lines: rawLines
          .map((l) => OrderLine.fromJson(Map<String, dynamic>.from(l as Map)))
          .toList(),
      payments: rawPayments
          .map(
            (p) => OrderPayment.fromJson(Map<String, dynamic>.from(p as Map)),
          )
          .toList(),
      notes: json['notes']?.toString() ?? '',
      history: rawHistory
          .map(
            (h) =>
                OrderHistoryEvent.fromJson(Map<String, dynamic>.from(h as Map)),
          )
          .toList(),
      invoice: rawInvoice != null ? InvoiceInfo.fromJson(rawInvoice) : null,
      isSynced: json['isSynced'] != false, // defaults to true for server data
      outletId: json['outletId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'offlineId': offlineId,
      'name': name,
      'phone': phone,
      'date': date,
      'due': due,
      'completed': completed,
      'status': status,
      'lines': lines.map((l) => l.toJson()).toList(),
      'payments': payments.map((p) => p.toJson()).toList(),
      'notes': notes,
      'history': history.map((h) => h.toJson()).toList(),
      'invoice': invoice?.toJson(),
      'isSynced': isSynced,
      'outletId': outletId,
    };
  }

  Order copyWith({
    String? id,
    String? offlineId,
    String? name,
    String? phone,
    String? date,
    String? due,
    String? completed,
    String? status,
    List<OrderLine>? lines,
    List<OrderPayment>? payments,
    String? notes,
    List<OrderHistoryEvent>? history,
    InvoiceInfo? invoice,
    bool? isSynced,
    String? outletId,
  }) {
    return Order(
      id: id ?? this.id,
      offlineId: offlineId ?? this.offlineId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      date: date ?? this.date,
      due: due ?? this.due,
      completed: completed ?? this.completed,
      status: status ?? this.status,
      lines: lines ?? this.lines,
      payments: payments ?? this.payments,
      notes: notes ?? this.notes,
      history: history ?? this.history,
      invoice: invoice ?? this.invoice,
      isSynced: isSynced ?? this.isSynced,
      outletId: outletId ?? this.outletId,
    );
  }
}
