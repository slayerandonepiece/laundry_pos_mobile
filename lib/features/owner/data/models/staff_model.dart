class StaffMember {
  final String id;
  final String name;
  final String phone;
  final bool active;

  StaffMember({
    required this.id,
    required this.name,
    required this.phone,
    this.active = true,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      active: json['active'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'phone': phone, 'active': active};
  }

  StaffMember copyWith({
    String? id,
    String? name,
    String? phone,
    bool? active,
  }) {
    return StaffMember(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      active: active ?? this.active,
    );
  }
}
