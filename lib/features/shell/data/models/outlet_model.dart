/// One outlet the signed-in user may operate under, as returned in
/// `organizations[].allowedOutlets[]` from `POST /api/v1/auth/login`.
class Outlet {
  final String id;
  final String outletCode;
  final String displayName;
  final bool isDefault;
  final String status;

  Outlet({
    required this.id,
    required this.outletCode,
    required this.displayName,
    this.isDefault = false,
    this.status = 'ACTIVE',
  });

  factory Outlet.fromJson(Map<String, dynamic> json) {
    return Outlet(
      id: json['id']?.toString() ?? '',
      outletCode: json['outletCode']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      isDefault: json['isDefault'] == true,
      status: json['status']?.toString() ?? 'ACTIVE',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'outletCode': outletCode,
      'displayName': displayName,
      'isDefault': isDefault,
      'status': status,
    };
  }
}
