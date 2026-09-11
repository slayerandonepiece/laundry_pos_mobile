class StaffMember {
  final String id;
  final String name;
  final String username;
  final bool active;

  StaffMember({
    required this.id,
    required this.name,
    required this.username,
    this.active = true,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      active: json['active'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'username': username, 'active': active};
  }

  StaffMember copyWith({
    String? id,
    String? name,
    String? username,
    bool? active,
  }) {
    return StaffMember(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      active: active ?? this.active,
    );
  }
}
