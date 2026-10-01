/// One outlet an employee may work in.
class StaffOutlet {
  final String id;
  final String name;

  const StaffOutlet({required this.id, required this.name});

  factory StaffOutlet.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    // Never a blank label: fall back to the id.
    return StaffOutlet(id: id, name: name.trim().isEmpty ? id : name);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class StaffMember {
  final String id;
  final String name;
  final String phone;
  final bool active;

  /// Outlets the employee may work in. Null means "not known yet" (a staff
  /// list cached before assignments were kept) — distinct from an empty list,
  /// which means the employee has no outlet access at all.
  final List<StaffOutlet>? outlets;
  final String? defaultOutletId;

  StaffMember({
    required this.id,
    required this.name,
    required this.phone,
    this.active = true,
    this.outlets,
    this.defaultOutletId,
  });

  /// True only when the server says this employee has no outlet: they can
  /// sign in but have nowhere to work.
  bool get hasNoOutletAccess => outlets != null && outlets!.isEmpty;

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    final rawOutlets = json['outlets'];
    return StaffMember(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      active: json['active'] != false,
      outlets: rawOutlets is List
          ? [
              // One malformed entry must not fail the whole list.
              for (final o in rawOutlets)
                if (o is Map)
                  StaffOutlet.fromJson(Map<String, dynamic>.from(o)),
            ]
          : null,
      defaultOutletId: json['defaultOutletId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'active': active,
      if (outlets != null) 'outlets': outlets!.map((o) => o.toJson()).toList(),
      if (defaultOutletId != null) 'defaultOutletId': defaultOutletId,
    };
  }

  StaffMember copyWith({
    String? id,
    String? name,
    String? phone,
    bool? active,
    List<StaffOutlet>? outlets,
    String? defaultOutletId,
    bool clearDefaultOutletId = false,
  }) {
    return StaffMember(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      active: active ?? this.active,
      outlets: outlets ?? this.outlets,
      defaultOutletId: clearDefaultOutletId
          ? null
          : (defaultOutletId ?? this.defaultOutletId),
    );
  }
}
