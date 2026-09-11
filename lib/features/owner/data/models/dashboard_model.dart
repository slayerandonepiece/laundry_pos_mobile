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

class DashboardMetrics {
  final int todaySales;
  final int todayCount;
  final int periodSales;
  final int periodOrders;
  final int todo; // orders to finish
  final int completed;
  final int outstanding;
  final int overdue;
  final int dueToday;
  final List<ServiceMixItem> serviceMix;
  final List<CashPoint> cash;

  DashboardMetrics({
    this.todaySales = 0,
    this.todayCount = 0,
    this.periodSales = 0,
    this.periodOrders = 0,
    this.todo = 0,
    this.completed = 0,
    this.outstanding = 0,
    this.overdue = 0,
    this.dueToday = 0,
    this.serviceMix = const [],
    this.cash = const [],
  });

  factory DashboardMetrics.fromJson(Map<String, dynamic> json) {
    final rawMix = json['serviceMix'] as List? ?? [];
    final rawCash = json['cash'] as List? ?? [];

    return DashboardMetrics(
      todaySales: (json['todaySales'] as num?)?.toInt() ?? 0,
      todayCount: (json['todayCount'] as num?)?.toInt() ?? 0,
      periodSales: (json['periodSales'] as num?)?.toInt() ?? 0,
      periodOrders: (json['periodOrders'] as num?)?.toInt() ?? 0,
      todo: (json['todo'] as num?)?.toInt() ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      outstanding: (json['outstanding'] as num?)?.toInt() ?? 0,
      overdue: (json['overdue'] as num?)?.toInt() ?? 0,
      dueToday: (json['dueToday'] as num?)?.toInt() ?? 0,
      serviceMix: rawMix
          .map(
            (m) => ServiceMixItem.fromJson(Map<String, dynamic>.from(m as Map)),
          )
          .toList(),
      cash: rawCash
          .map((c) => CashPoint.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'todaySales': todaySales,
      'todayCount': todayCount,
      'periodSales': periodSales,
      'periodOrders': periodOrders,
      'todo': todo,
      'completed': completed,
      'outstanding': outstanding,
      'overdue': overdue,
      'dueToday': dueToday,
      'serviceMix': serviceMix.map((m) => m.toJson()).toList(),
      'cash': cash.map((c) => c.toJson()).toList(),
    };
  }
}
