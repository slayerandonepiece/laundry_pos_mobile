class OutletRollup {
  final String outletId;
  final String businessDate;
  final int ordersCreatedCount;
  final int ordersCompletedCount;
  final int grossOrderAmount;

  const OutletRollup({
    required this.outletId,
    required this.businessDate,
    this.ordersCreatedCount = 0,
    this.ordersCompletedCount = 0,
    this.grossOrderAmount = 0,
  });

  factory OutletRollup.fromJson(Map<String, dynamic> json) => OutletRollup(
    outletId: json['outletId']?.toString() ?? '',
    businessDate: json['businessDate']?.toString() ?? '',
    ordersCreatedCount: (json['ordersCreatedCount'] as num?)?.toInt() ?? 0,
    ordersCompletedCount: (json['ordersCompletedCount'] as num?)?.toInt() ?? 0,
    grossOrderAmount: (json['grossOrderAmount'] as num?)?.toInt() ?? 0,
  );
}
