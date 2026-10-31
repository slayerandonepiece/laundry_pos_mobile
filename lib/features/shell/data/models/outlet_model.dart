/// One outlet's own billing standing, from `allowedOutlets[].billing`.
/// Older servers omit it, which reads as an open outlet.
class OutletBilling {
  final String state; // active | ending | trial | blocked | awaiting
  final bool blocked;
  final String? paidThroughDate; // yyyy-MM-dd
  final int? daysLeft;

  const OutletBilling({
    this.state = 'active',
    this.blocked = false,
    this.paidThroughDate,
    this.daysLeft,
  });

  factory OutletBilling.fromJson(Object? json) {
    if (json is! Map) return const OutletBilling();
    return OutletBilling(
      state: json['state']?.toString() ?? 'active',
      blocked: json['blocked'] == true,
      paidThroughDate: json['paidThroughDate']?.toString(),
      daysLeft: (json['daysLeft'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'state': state,
    'blocked': blocked,
    if (paidThroughDate != null) 'paidThroughDate': paidThroughDate,
    if (daysLeft != null) 'daysLeft': daysLeft,
  };
}

/// One outlet the signed-in user may operate under, as returned in
/// `organizations[].allowedOutlets[]` from `POST /api/v1/auth/login`.
class Outlet {
  final String id;
  final String outletCode;
  final String displayName;
  final bool isDefault;
  final String status;
  final OutletBilling? billing;

  bool get isBlocked => billing?.blocked ?? false;

  /// Days left when the outlet's paid term is 30 days or fewer from ending.
  int? get dueInDays => billing?.state == 'ending' ? billing?.daysLeft : null;

  Outlet({
    required this.id,
    required this.outletCode,
    required this.displayName,
    this.isDefault = false,
    this.status = 'ACTIVE',
    this.billing,
  });

  factory Outlet.fromJson(Map<String, dynamic> json) {
    return Outlet(
      id: json['id']?.toString() ?? '',
      outletCode: json['outletCode']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      isDefault: json['isDefault'] == true,
      status: json['status']?.toString() ?? 'ACTIVE',
      billing: json['billing'] is Map
          ? OutletBilling.fromJson(json['billing'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'outletCode': outletCode,
      'displayName': displayName,
      'isDefault': isDefault,
      'status': status,
      if (billing != null) 'billing': billing!.toJson(),
    };
  }
}
