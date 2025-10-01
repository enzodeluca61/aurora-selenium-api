class Field {
  final String? id;
  final String name;
  final String address;
  final String code; // sigla
  final String? userId;

  Field({
    this.id,
    required this.name,
    required this.address,
    required this.code,
    this.userId,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'name': name,
      'address': address,
      'code': code,
      'user_id': userId,
      'created_at': DateTime.now().toIso8601String(),
    };
    
    if (id != null) {
      json['id'] = id;
    }
    
    return json;
  }

  factory Field.fromJson(Map<String, dynamic> json) {
    return Field(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      code: json['code'] ?? '',
      userId: json['user_id'],
    );
  }

  Field copyWith({
    String? id,
    String? name,
    String? address,
    String? code,
    String? userId,
  }) {
    return Field(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      code: code ?? this.code,
      userId: userId ?? this.userId,
    );
  }
}