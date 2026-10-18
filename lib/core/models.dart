import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _ts(dynamic v) =>
    v is Timestamp ? v.toDate() : (v is DateTime ? v : DateTime.now());

class AppUser {
  final String uid;
  final String name;
  final String email;
  final String role; // 'admin' | 'coach' | 'student'
  final String studentId; // set for students: their record in `students`
  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.studentId = '',
  });
  bool get isAdmin => role == 'admin';
  bool get isStudent => role == 'student';
  bool get isStaff => role == 'admin' || role == 'coach';
  String get roleLabel => isAdmin ? 'Admin' : (isStudent ? 'Student' : 'Coach');

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AppUser(
      uid: d.id,
      name: m['name'] ?? '',
      email: m['email'] ?? '',
      role: m['role'] ?? 'coach',
      studentId: m['studentId'] ?? '',
    );
  }
}

class Batch {
  final String id;
  final String name;
  final String timing;
  final String coach;
  final double fee;
  Batch({
    required this.id,
    required this.name,
    this.timing = '',
    this.coach = '',
    this.fee = 0,
  });

  factory Batch.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Batch(
      id: d.id,
      name: m['name'] ?? '',
      timing: m['timing'] ?? '',
      coach: m['coach'] ?? '',
      fee: (m['fee'] ?? 0).toDouble(),
    );
  }
  Map<String, dynamic> toMap() => {
    'name': name,
    'timing': timing,
    'coach': coach,
    'fee': fee,
  };
}

class Student {
  final String id;
  final String name;
  final String phone;
  final String parentName;
  final String batchId;
  final String team; // team name, e.g. for picking players for matches
  final double monthlyFee;
  final DateTime joinDate;
  final bool active;
  final String notes;
  Student({
    required this.id,
    required this.name,
    this.phone = '',
    this.parentName = '',
    this.batchId = '',
    this.team = '',
    this.monthlyFee = 0,
    DateTime? joinDate,
    this.active = true,
    this.notes = '',
  }) : joinDate = joinDate ?? DateTime.now();

  factory Student.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Student(
      id: d.id,
      name: m['name'] ?? '',
      phone: m['phone'] ?? '',
      parentName: m['parentName'] ?? '',
      batchId: m['batchId'] ?? '',
      team: m['team'] ?? '',
      monthlyFee: (m['monthlyFee'] ?? 0).toDouble(),
      joinDate: _ts(m['joinDate']),
      active: m['active'] ?? true,
      notes: m['notes'] ?? '',
    );
  }
  Map<String, dynamic> toMap() => {
    'name': name,
    'phone': phone,
    'parentName': parentName,
    'batchId': batchId,
    'team': team,
    'monthlyFee': monthlyFee,
    'joinDate': Timestamp.fromDate(joinDate),
    'active': active,
    'notes': notes,
  };
}

class FeePayment {
  final String id;
  final String studentId;
  final String month; // yyyy-MM, the month this payment covers
  final double amount;
  final DateTime paidOn;
  final String mode;
  final String note;
  FeePayment({
    required this.id,
    required this.studentId,
    required this.month,
    required this.amount,
    required this.paidOn,
    this.mode = 'Cash',
    this.note = '',
  });
  factory FeePayment.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return FeePayment(
      id: d.id,
      studentId: m['studentId'] ?? '',
      month: m['month'] ?? '',
      amount: (m['amount'] ?? 0).toDouble(),
      paidOn: _ts(m['paidOn']),
      mode: m['mode'] ?? 'Cash',
      note: m['note'] ?? '',
    );
  }
}

class Item {
  final String id;
  final String name;
  final String category; // Equipment | Clothing | Other
  final String size;
  final double price;
  final int stock;
  Item({
    required this.id,
    required this.name,
    this.category = 'Equipment',
    this.size = '',
    this.price = 0,
    this.stock = 0,
  });
  factory Item.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Item(
      id: d.id,
      name: m['name'] ?? '',
      category: m['category'] ?? 'Equipment',
      size: m['size'] ?? '',
      price: (m['price'] ?? 0).toDouble(),
      stock: (m['stock'] ?? 0).toInt(),
    );
  }
  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category,
    'size': size,
    'price': price,
    'stock': stock,
  };
  String get label => size.isEmpty ? name : '$name ($size)';
}

class Sale {
  final String id;
  final String studentId;
  final String itemId;
  final String itemLabel;
  final int qty;
  final double unitPrice;
  final double paid;
  final DateTime date;
  Sale({
    required this.id,
    required this.studentId,
    required this.itemId,
    required this.itemLabel,
    required this.qty,
    required this.unitPrice,
    required this.paid,
    required this.date,
  });
  double get total => qty * unitPrice;
  double get balance => total - paid;
  factory Sale.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Sale(
      id: d.id,
      studentId: m['studentId'] ?? '',
      itemId: m['itemId'] ?? '',
      itemLabel: m['itemLabel'] ?? '',
      qty: (m['qty'] ?? 1).toInt(),
      unitPrice: (m['unitPrice'] ?? 0).toDouble(),
      paid: (m['paid'] ?? 0).toDouble(),
      date: _ts(m['date']),
    );
  }
}
