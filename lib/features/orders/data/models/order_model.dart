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
      method: json['method']?.toString() ?? 'Cash',
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

  InvoiceInfo({
    required this.exists,
    this.invoiceSeq,
    this.accessToken,
    this.canGenerate = false,
  });

  String get formattedInvoiceNumber {
    if (invoiceSeq == null) return '';
    return 'INV-${invoiceSeq.toString().padLeft(6, '0')}';
  }

  String get invoiceNumber => formattedInvoiceNumber;
  DateTime get issuedAt => DateTime.now();

  factory InvoiceInfo.fromJson(Map<String, dynamic> json) {
    return InvoiceInfo(
      exists: json['exists'] == true,
      invoiceSeq: (json['invoiceSeq'] as num?)?.toInt(),
      accessToken: json['accessToken']?.toString(),
      canGenerate: json['canGenerate'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'exists': exists,
      'invoiceSeq': invoiceSeq,
      'accessToken': accessToken,
      'canGenerate': canGenerate,
    };
  }
}

class Order {
  final String id; // Order code (e.g. EL-123)
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

  Order({
    required this.id,
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

  String get orderCode => id;
  DateTime get createdAt => DateTime.tryParse(date)?.toLocal() ?? DateTime.now();
  DateTime get dueDateTime => DateTime.tryParse(due)?.toLocal() ?? DateTime.now();

  factory Order.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] as List? ?? [];
    final rawPayments = json['payments'] as List? ?? [];
    final rawHistory = json['history'] as List? ?? [];
    final rawInvoice = json['invoice'] as Map<String, dynamic>?;

    return Order(
      id: json['id']?.toString() ?? '',
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
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
    };
  }

  Order copyWith({
    String? id,
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
  }) {
    return Order(
      id: id ?? this.id,
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
    );
  }
}
