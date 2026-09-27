class User {
  final String id;
  final String name;
  final String phone;
  final bool isSuperAdmin;
  final bool mustChangePassword;

  User({
    required this.id,
    required this.name,
    required this.phone,
    this.isSuperAdmin = false,
    this.mustChangePassword = false,
  });

  String get displayName => name.isNotEmpty ? name : phone;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      isSuperAdmin: json['isSuperAdmin'] == true,
      mustChangePassword: json['mustChangePassword'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'isSuperAdmin': isSuperAdmin,
      'mustChangePassword': mustChangePassword,
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? phone,
    bool? isSuperAdmin,
    bool? mustChangePassword,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }
}

class StoreSummary {
  final String storeId;
  final String storeName;
  final String role; // 'OWNER' | 'EMPLOYEE'
  final String? blockedReason; // 'membership_inactive' | 'store_locked' | 'store_archived' | 'payment_lapsed'
  final String? paidThroughDate;

  StoreSummary({
    required this.storeId,
    required this.storeName,
    required this.role,
    this.blockedReason,
    this.paidThroughDate,
  });

  bool get isOwner => role.toUpperCase() == 'OWNER';
  bool get isEmployee => role.toUpperCase() == 'EMPLOYEE';
  bool get isBlocked => blockedReason != null && blockedReason!.isNotEmpty;

  factory StoreSummary.fromJson(Map<String, dynamic> json) {
    return StoreSummary(
      storeId: json['storeId']?.toString() ?? '',
      storeName: json['storeName']?.toString() ?? '',
      role: json['role']?.toString() ?? 'EMPLOYEE',
      blockedReason: json['blockedReason']?.toString(),
      paidThroughDate: json['paidThroughDate']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'storeId': storeId,
      'storeName': storeName,
      'role': role,
      'blockedReason': blockedReason,
      'paidThroughDate': paidThroughDate,
    };
  }
}
