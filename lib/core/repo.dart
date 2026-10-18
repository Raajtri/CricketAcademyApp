import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';

import '../firebase_options.dart';
import 'models.dart';
import 'scoring.dart';

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String monthKey(DateTime d) => DateFormat('yyyy-MM').format(d);

/// Fee position for one student: monthly fee x months since joining, minus payments.
class FeeSummary {
  final double billed;
  final double paid;
  final List<String> unpaidMonths;
  FeeSummary(this.billed, this.paid, this.unpaidMonths);
  double get due => billed - paid;
}

FeeSummary feeSummary(
  Student s,
  Iterable<FeePayment> payments, {
  DateTime? now,
}) {
  now ??= DateTime.now();
  final mine = payments.where((p) => p.studentId == s.id).toList();
  final paidByMonth = <String, double>{};
  for (final p in mine) {
    paidByMonth[p.month] = (paidByMonth[p.month] ?? 0) + p.amount;
  }
  var billed = 0.0;
  final unpaid = <String>[];
  var m = DateTime(s.joinDate.year, s.joinDate.month);
  final last = DateTime(now.year, now.month);
  while (!m.isAfter(last)) {
    billed += s.monthlyFee;
    final k = monthKey(m);
    if ((paidByMonth[k] ?? 0) + 0.001 < s.monthlyFee) unpaid.add(k);
    m = DateTime(m.year, m.month + 1);
  }
  final paid = mine.fold<double>(0, (a, p) => a + p.amount);
  return FeeSummary(billed, paid, unpaid);
}

class Repo {
  Repo._();
  static final Repo i = Repo._();

  /// Re-subscribes a few times when a listener fails. A listener that Firestore
  /// rejects is dead for good, and right after sign-up the very first reads can be
  /// rejected for a moment, until the server has seen the new user's profile.
  Stream<T> _retrying<T>(Stream<T> Function() make, {int tries = 3}) async* {
    var attempt = 0;
    while (true) {
      try {
        await for (final v in make()) {
          attempt = 0;
          yield v;
        }
        return;
      } catch (e) {
        if (++attempt > tries) rethrow;
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ---------- auth & users ----------
  Stream<User?> get authChanges => _auth.authStateChanges();

  /// Only server-confirmed profiles count, so the app never opens its screens
  /// before the server knows this user is staff.
  Stream<AppUser?> profile(String uid) => _retrying(
    () => _db
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .where((d) => !d.metadata.hasPendingWrites)
        .map((d) => d.exists ? AppUser.fromDoc(d) : null),
  );

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signOut() => _auth.signOut();

  /// First-time setup: creates the admin account. Allowed by the security rules
  /// only while no admin exists yet.
  Future<void> createFirstAdmin(
    String name,
    String email,
    String password,
  ) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;
    await _db.collection('users').doc(uid).set({
      'name': name.trim(),
      'email': email.trim(),
      'role': 'admin',
    });
    await _db.collection('meta').doc('setup').set({
      'adminUid': uid,
      'at': FieldValue.serverTimestamp(),
    });
  }

  /// Admin creates a login for a coach or a student. A secondary Firebase app is
  /// used so the admin's own session is not replaced by the new account.
  Future<void> createLogin({
    required String name,
    required String email,
    required String password,
    String role = 'coach',
    String studentId = '',
  }) async {
    final app = await Firebase.initializeApp(
      name: 'secondary-${DateTime.now().millisecondsSinceEpoch}',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    try {
      final auth = FirebaseAuth.instanceFor(app: app);
      final cred = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _db.collection('users').doc(cred.user!.uid).set({
        'name': name.trim(),
        'email': email.trim(),
        'role': role,
        if (studentId.isNotEmpty) 'studentId': studentId,
      });
      await auth.signOut();
    } finally {
      await app.delete();
    }
  }

  Stream<List<AppUser>> staff() => _retrying(
    () => _db
        .collection('users')
        .snapshots()
        .map((s) => s.docs.map(AppUser.fromDoc).toList()),
  );

  Future<void> removeStaff(String uid) =>
      _db.collection('users').doc(uid).delete();

  // ---------- batches ----------
  Stream<List<Batch>> batches() => _retrying(
    () => _db
        .collection('batches')
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(Batch.fromDoc).toList()),
  );

  Future<void> saveBatch(Batch b) => b.id.isEmpty
      ? _db.collection('batches').add(b.toMap())
      : _db.collection('batches').doc(b.id).set(b.toMap());

  Future<void> deleteBatch(String id) =>
      _db.collection('batches').doc(id).delete();

  // ---------- students ----------
  Stream<List<Student>> students() => _retrying(
    () => _db
        .collection('students')
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(Student.fromDoc).toList()),
  );

  Future<void> saveStudent(Student s) => s.id.isEmpty
      ? _db.collection('students').add(s.toMap())
      : _db.collection('students').doc(s.id).set(s.toMap());

  Future<void> deleteStudent(String id) =>
      _db.collection('students').doc(id).delete();

  // ---------- attendance ----------
  String _attId(DateTime d, String batchId) => '${dayKey(d)}_$batchId';

  /// Map of studentId -> 'P' | 'A' | 'L' for a batch on a day.
  Stream<Map<String, String>> attendance(DateTime d, String batchId) =>
      _retrying(
        () => _db
            .collection('attendance')
            .doc(_attId(d, batchId))
            .snapshots()
            .map((s) {
              final r = (s.data()?['records'] as Map?) ?? {};
              return r.map((k, v) => MapEntry(k.toString(), v.toString()));
            }),
      );

  Future<void> setAttendance(
    DateTime d,
    String batchId,
    String studentId,
    String? status,
  ) {
    return _db.collection('attendance').doc(_attId(d, batchId)).set({
      'date': dayKey(d),
      'month': monthKey(d),
      'batchId': batchId,
      'records': {studentId: status ?? FieldValue.delete()},
    }, SetOptions(merge: true));
  }

  /// All attendance sheets of a month (for the monthly report).
  Stream<List<Map<String, dynamic>>> attendanceMonth(DateTime month) =>
      _retrying(
        () => _db
            .collection('attendance')
            .where('month', isEqualTo: monthKey(month))
            .snapshots()
            .map((s) => s.docs.map((d) => d.data()).toList()),
      );

  // ---------- fees ----------
  Stream<List<FeePayment>> payments() => _retrying(
    () => _db
        .collection('payments')
        .orderBy('paidOn', descending: true)
        .snapshots()
        .map((s) => s.docs.map(FeePayment.fromDoc).toList()),
  );

  Future<void> addPayment({
    required String studentId,
    required String month,
    required double amount,
    required String mode,
    String note = '',
  }) => _db.collection('payments').add({
    'studentId': studentId,
    'month': month,
    'amount': amount,
    'mode': mode,
    'note': note,
    'paidOn': Timestamp.now(),
  });

  Future<void> deletePayment(String id) =>
      _db.collection('payments').doc(id).delete();

  // ---------- inventory & sales ----------
  Stream<List<Item>> items() => _retrying(
    () => _db
        .collection('items')
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(Item.fromDoc).toList()),
  );

  Future<void> saveItem(Item i) => i.id.isEmpty
      ? _db.collection('items').add(i.toMap())
      : _db.collection('items').doc(i.id).set(i.toMap());

  Future<void> deleteItem(String id) =>
      _db.collection('items').doc(id).delete();

  Future<void> adjustStock(String itemId, int delta) => _db
      .collection('items')
      .doc(itemId)
      .update({'stock': FieldValue.increment(delta)});

  Stream<List<Sale>> sales() => _retrying(
    () => _db
        .collection('sales')
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Sale.fromDoc).toList()),
  );

  Future<void> recordSale({
    required Student student,
    required Item item,
    required int qty,
    required double unitPrice,
    required double paid,
  }) {
    final batch = _db.batch();
    batch.set(_db.collection('sales').doc(), {
      'studentId': student.id,
      'itemId': item.id,
      'itemLabel': item.label,
      'qty': qty,
      'unitPrice': unitPrice,
      'paid': paid,
      'date': Timestamp.now(),
    });
    batch.update(_db.collection('items').doc(item.id), {
      'stock': FieldValue.increment(-qty),
    });
    return batch.commit();
  }

  Future<void> receiveSalePayment(String saleId, double amount) => _db
      .collection('sales')
      .doc(saleId)
      .update({'paid': FieldValue.increment(amount)});

  /// Deleting a sale puts the stock back.
  Future<void> cancelSale(Sale s) {
    final batch = _db.batch();
    batch.delete(_db.collection('sales').doc(s.id));
    batch.update(_db.collection('items').doc(s.itemId), {
      'stock': FieldValue.increment(s.qty),
    });
    return batch.commit();
  }

  // ---------- student's own view ----------
  Stream<Student?> student(String id) => _retrying(
    () => _db
        .collection('students')
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? Student.fromDoc(d) : null),
  );

  // Queries are filtered by studentId, which is what the security rules check.
  Stream<List<FeePayment>> paymentsFor(String studentId) => _retrying(
    () => _db
        .collection('payments')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map(
          (s) =>
              s.docs.map(FeePayment.fromDoc).toList()
                ..sort((a, b) => b.paidOn.compareTo(a.paidOn)),
        ),
  );

  Stream<List<Sale>> salesFor(String studentId) => _retrying(
    () => _db
        .collection('sales')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map(
          (s) =>
              s.docs.map(Sale.fromDoc).toList()
                ..sort((a, b) => b.date.compareTo(a.date)),
        ),
  );

  /// Every attendance sheet of a batch, all months. Students may only ask for their own batch.
  Stream<List<Map<String, dynamic>>> attendanceForBatchAll(String batchId) =>
      _retrying(
        () => _db
            .collection('attendance')
            .where('batchId', isEqualTo: batchId)
            .snapshots()
            .map((s) => s.docs.map((d) => d.data()).toList()),
      );

  /// Attendance sheets of one batch for one month.
  Stream<List<Map<String, dynamic>>> attendanceForBatch(
    String batchId,
    DateTime month,
  ) => _retrying(
    () => _db
        .collection('attendance')
        .where('batchId', isEqualTo: batchId)
        .where('month', isEqualTo: monthKey(month))
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList()),
  );

  // ---------- matches & scoring ----------
  Stream<List<CricketMatch>> matches() => _retrying(
    () => _db
        .collection('matches')
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs.map(CricketMatch.fromDoc).toList()),
  );

  Stream<CricketMatch?> match(String id) => _retrying(
    () => _db
        .collection('matches')
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? CricketMatch.fromDoc(d) : null),
  );

  Future<String> createMatch({
    required String teamA,
    required String teamB,
    required List<String> playersA,
    required List<String> playersB,
    required int overs,
    required String battingFirst,
  }) async {
    final ref = await _db.collection('matches').add({
      'teamA': teamA,
      'teamB': teamB,
      'playersA': playersA,
      'playersB': playersB,
      'overs': overs,
      'battingFirst': battingFirst,
      'currentInnings': 1,
      'status': 'live',
      'result': '',
      'date': Timestamp.now(),
    });
    return ref.id;
  }

  Stream<List<Ball>> balls(String matchId) => _retrying(
    () => _db
        .collection('matches')
        .doc(matchId)
        .collection('balls')
        .orderBy('seq')
        .snapshots()
        .map((s) => s.docs.map(Ball.fromDoc).toList()),
  );

  Future<void> addBall(String matchId, Ball b) =>
      _db.collection('matches').doc(matchId).collection('balls').add(b.toMap());

  Future<void> deleteBall(String matchId, String ballId) => _db
      .collection('matches')
      .doc(matchId)
      .collection('balls')
      .doc(ballId)
      .delete();

  Future<void> setMatch(String matchId, Map<String, dynamic> data) =>
      _db.collection('matches').doc(matchId).update(data);

  Future<void> deleteMatch(String matchId) async {
    final balls = await _db
        .collection('matches')
        .doc(matchId)
        .collection('balls')
        .get();
    final batch = _db.batch();
    for (final d in balls.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_db.collection('matches').doc(matchId));
    await batch.commit();
  }

  /// Every ball ever scored, grouped by "matchId#innings" for career stats.
  Stream<Map<String, List<Ball>>> allBallsGrouped() => _retrying(
    () => _db.collectionGroup('balls').snapshots().map((s) {
      final out = <String, List<Ball>>{};
      for (final d in s.docs) {
        final matchId = d.reference.parent.parent!.id;
        final b = Ball.fromDoc(d);
        out.putIfAbsent('$matchId#${b.innings}', () => []).add(b);
      }
      return out;
    }),
  );
}
