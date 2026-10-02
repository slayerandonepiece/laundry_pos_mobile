class Expense {
  final String id;
  final String? outletId;
  final String title;
  final String category;
  final int amount;
  final String due;
  final String? paid;
  final bool monthly;
  final String? seriesId;

  Expense({
    required this.id,
    this.outletId,
    required this.title,
    required this.category,
    required this.amount,
    required this.due,
    this.paid,
    this.monthly = false,
    this.seriesId,
  });

  bool get isPaid => paid != null && paid!.isNotEmpty;

  /// Created offline with an id the app made up; the server has never seen it.
  static bool isUnsyncedId(String id) => id.startsWith('LOCAL-');
  bool get isUnsynced => isUnsyncedId(id);

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id']?.toString() ?? '',
      outletId: json['outletId']?.toString(),
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Operations',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      due: json['due']?.toString() ?? '',
      paid: json['paid']?.toString(),
      monthly: json['monthly'] == true,
      seriesId: json['seriesId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'outletId': outletId,
      'title': title,
      'category': category,
      'amount': amount,
      'due': due,
      'paid': paid,
      'monthly': monthly,
      'seriesId': seriesId,
    };
  }
}
