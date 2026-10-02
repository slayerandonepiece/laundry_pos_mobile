class ServiceMixItem {
  final String label;
  final int amount;

  ServiceMixItem({required this.label, required this.amount});

  factory ServiceMixItem.fromJson(Map<String, dynamic> json) {
    return ServiceMixItem(
      label: json['label']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'amount': amount};
}

class CashPoint {
  final String label;
  final int income;
  final int expenses;

  CashPoint({
    required this.label,
    required this.income,
    required this.expenses,
  });

  factory CashPoint.fromJson(Map<String, dynamic> json) {
    return CashPoint(
      label: json['label']?.toString() ?? '',
      income: (json['income'] as num?)?.toInt() ?? 0,
      expenses: (json['expenses'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'income': income,
    'expenses': expenses,
  };
}

class DashboardBar {
  final String label;
  final int amount;

  DashboardBar({required this.label, required this.amount});

  factory DashboardBar.fromJson(Map<String, dynamic> json) {
    return DashboardBar(
      label: json['label']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'amount': amount};
}

class DashboardMetrics {
  final int todaySales;
  final int todayCount;
  final int periodSales;
  final int periodOrders;
  final bool hasPeriodSales;
  final int expensesThisMonth;
  final int todo; // orders to finish
  final int completed;
  final int outstanding;
  final int overdue;
  final int dueToday;
  final List<ServiceMixItem> serviceMix;
  final List<CashPoint> cash;

  /// Income/expenses over the requested range (present when the request
  /// carried a granularity). `cash` is always the current calendar month.
  final List<CashPoint> cashRange;
  final List<DashboardBar> bars;

  DashboardMetrics({
    this.todaySales = 0,
    this.todayCount = 0,
    this.periodSales = 0,
    this.periodOrders = 0,
    this.hasPeriodSales = true,
    this.expensesThisMonth = 0,
    this.todo = 0,
    this.completed = 0,
    this.outstanding = 0,
    this.overdue = 0,
    this.dueToday = 0,
    this.serviceMix = const [],
    this.cash = const [],
    this.cashRange = const [],
    this.bars = const [],
  });

  factory DashboardMetrics.fromJson(Map<String, dynamic> json) {
    // A malformed element is skipped rather than failing the whole dashboard.
    List<T> parseList<T>(Object? raw, T Function(Map<String, dynamic>) parse) =>
        raw is List
        ? [
            for (final e in raw)
              if (e is Map) parse(Map<String, dynamic>.from(e)),
          ]
        : <T>[];

    return DashboardMetrics(
      todaySales: (json['todaySales'] as num?)?.toInt() ?? 0,
      todayCount: (json['todayCount'] as num?)?.toInt() ?? 0,
      periodSales: (json['periodSales'] as num?)?.toInt() ?? 0,
      periodOrders: (json['periodOrders'] as num?)?.toInt() ?? 0,
      hasPeriodSales: json.containsKey('periodSales'),
      expensesThisMonth: (json['expenses'] as num?)?.toInt() ?? 0,
      todo: (json['todo'] as num?)?.toInt() ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      outstanding: (json['outstanding'] as num?)?.toInt() ?? 0,
      overdue: (json['overdue'] as num?)?.toInt() ?? 0,
      dueToday: (json['dueToday'] as num?)?.toInt() ?? 0,
      serviceMix: parseList(json['serviceMix'], ServiceMixItem.fromJson),
      cash: parseList(json['cash'], CashPoint.fromJson),
      cashRange: parseList(json['cashRange'], CashPoint.fromJson),
      bars: parseList(json['bars'], DashboardBar.fromJson),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'todaySales': todaySales,
      'todayCount': todayCount,
      'periodSales': periodSales,
      'periodOrders': periodOrders,
      'expenses': expensesThisMonth,
      'todo': todo,
      'completed': completed,
      'outstanding': outstanding,
      'overdue': overdue,
      'dueToday': dueToday,
      'serviceMix': serviceMix.map((m) => m.toJson()).toList(),
      'cash': cash.map((c) => c.toJson()).toList(),
      'cashRange': cashRange.map((c) => c.toJson()).toList(),
      'bars': bars.map((b) => b.toJson()).toList(),
    };
  }
}
