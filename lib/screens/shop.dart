import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../core/ui.dart';

class ShopView extends StatefulWidget {
  const ShopView({super.key});
  @override
  State<ShopView> createState() => _ShopViewState();
}

class _ShopViewState extends State<ShopView> {
  String _tab = 'stock';
  late final Stream<List<Item>> _items = Repo.i.items();
  late final Stream<List<Sale>> _sales = Repo.i.sales();
  late final Stream<List<Student>> _students = Repo.i.students();

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: _tab == 'stock'
        ? FloatingActionButton.extended(
            onPressed: () => _editItem(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          )
        : FloatingActionButton.extended(
            onPressed: () => sellItemDialog(context),
            icon: const Icon(Icons.shopping_cart_checkout),
            label: const Text('New sale'),
          ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'stock',
                label: Text('Stock'),
                icon: Icon(Icons.inventory_2_outlined),
              ),
              ButtonSegment(
                value: 'sales',
                label: Text('Sales'),
                icon: Icon(Icons.receipt_long_outlined),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        Expanded(child: _tab == 'stock' ? _stock() : _salesList()),
      ],
    ),
  );

  Widget _stock() => Live<List<Item>>(
    stream: _items,
    builder: (c, items) {
      if (items.isEmpty) {
        return const EmptyState(
          'No items yet.\nAdd bats, balls, kits, T-shirts, caps…',
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final it = items[i];
          return Card(
            child: ListTile(
              leading: Icon(
                it.category == 'Clothing'
                    ? Icons.checkroom
                    : Icons.sports_cricket,
              ),
              title: Text(it.label),
              subtitle: Text('${it.category}  •  ${rupees(it.price)}'),
              onTap: () => _editItem(context, it),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => Repo.i.adjustStock(it.id, -1),
                  ),
                  Text(
                    '${it.stock}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: it.stock <= 2
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => Repo.i.adjustStock(it.id, 1),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  Widget _salesList() => Live<List<Sale>>(
    stream: _sales,
    builder: (c, sales) => Live<List<Student>>(
      stream: _students,
      builder: (c, students) {
        if (sales.isEmpty) return const EmptyState('No sales yet.');
        final owing = sales.fold<double>(
          0,
          (a, s) => a + (s.balance > 0 ? s.balance : 0),
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pending from students: ${rupees(owing)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: sales.length,
                itemBuilder: (c, i) {
                  final s = sales[i];
                  final name =
                      students
                          .where((x) => x.id == s.studentId)
                          .firstOrNull
                          ?.name ??
                      'Unknown student';
                  return saleTile(context, s, studentName: name);
                },
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _editItem(BuildContext context, Item? it) async {
    final name = TextEditingController(text: it?.name ?? '');
    final size = TextEditingController(text: it?.size ?? '');
    final price = TextEditingController(
      text: it == null ? '' : it.price.toStringAsFixed(0),
    );
    final stock = TextEditingController(text: it == null ? '' : '${it.stock}');
    var cat = it?.category ?? 'Equipment';
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(it == null ? 'New item' : 'Edit item'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Field(
                    name,
                    'Item name (e.g. Bat, Training T-shirt)',
                    required: true,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: cat,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final x in ['Equipment', 'Clothing', 'Other'])
                        DropdownMenuItem(value: x, child: Text(x)),
                    ],
                    onChanged: (v) => set(() => cat = v!),
                  ),
                  const SizedBox(height: 12),
                  Field(size, 'Size (optional, e.g. M, 34, Youth)'),
                  Field(
                    price,
                    'Selling price (₹)',
                    type: TextInputType.number,
                    required: true,
                  ),
                  Field(stock, 'Stock quantity', type: TextInputType.number),
                ],
              ),
            ),
          ),
          actions: [
            if (it != null)
              TextButton(
                onPressed: () async {
                  if (await confirm(context, 'Delete ${it.label}?')) {
                    await Repo.i.deleteItem(it.id);
                    if (c.mounted) Navigator.pop(c, false);
                  }
                },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(c, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await Repo.i.saveItem(
        Item(
          id: it?.id ?? '',
          name: name.text.trim(),
          category: cat,
          size: size.text.trim(),
          price: numOf(price),
          stock: int.tryParse(stock.text.trim()) ?? 0,
        ),
      );
    }
  }
}

Widget saleTile(BuildContext context, Sale s, {String? studentName}) => Card(
  child: ListTile(
    title: Text(
      '${s.itemLabel} × ${s.qty}${studentName == null ? '' : '  •  $studentName'}',
    ),
    subtitle: Text(
      '${fmtDate(s.date)}  •  Total ${rupees(s.total)}  •  Paid ${rupees(s.paid)}',
    ),
    trailing: s.balance > 0
        ? TextButton(
            onPressed: () => _receive(context, s),
            child: Text(
              'Due ${rupees(s.balance)}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          )
        : const Icon(Icons.check_circle, color: Colors.green),
    onLongPress: () async {
      if (await confirm(
        context,
        'Cancel this sale?',
        'The item goes back into stock.',
      )) {
        await Repo.i.cancelSale(s);
      }
    },
  ),
);

Future<void> _receive(BuildContext context, Sale s) async {
  final amt = TextEditingController(text: s.balance.toStringAsFixed(0));
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Receive payment'),
      content: Field(amt, 'Amount (₹)', type: TextInputType.number),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (ok == true && numOf(amt) > 0) {
    await Repo.i.receiveSalePayment(s.id, numOf(amt));
  }
}

/// Sell an item to a student. Pass [student] to skip choosing one.
Future<void> sellItemDialog(BuildContext context, {Student? student}) async {
  final items = (await Repo.i.items().first).where((i) => i.stock > 0).toList();
  final students = (await Repo.i.students().first)
      .where((s) => s.active)
      .toList();
  if (!context.mounted) return;
  if (items.isEmpty) {
    toast(context, 'No items in stock. Add items in the Shop first.');
    return;
  }
  Student? who = student;
  Item? item = items.first;
  final qty = TextEditingController(text: '1');
  final price = TextEditingController(text: item.price.toStringAsFixed(0));
  final paid = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final total = (int.tryParse(qty.text) ?? 0) * numOf(price);
        return AlertDialog(
          title: const Text('Sell item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (student == null)
                  DropdownButtonFormField<Student>(
                    initialValue: who,
                    decoration: const InputDecoration(labelText: 'Student'),
                    items: [
                      for (final s in students)
                        DropdownMenuItem(value: s, child: Text(s.name)),
                    ],
                    onChanged: (v) => set(() => who = v),
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('To: ${student.name}'),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Item>(
                  initialValue: item,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Item'),
                  items: [
                    for (final i in items)
                      DropdownMenuItem(
                        value: i,
                        child: Text('${i.label}  (${i.stock} left)'),
                      ),
                  ],
                  onChanged: (v) => set(() {
                    item = v;
                    price.text = v!.price.toStringAsFixed(0);
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  onChanged: (_) => set(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price each (₹)',
                  ),
                  onChanged: (_) => set(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: paid,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Paid now (₹)',
                    helperText: 'Total ${rupees(total)}. Leave empty if unpaid',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Sell'),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true) return;
  final q = int.tryParse(qty.text) ?? 0;
  if (who == null || item == null || q <= 0) {
    if (context.mounted) toast(context, 'Choose a student, item and quantity');
    return;
  }
  if (q > item!.stock) {
    if (context.mounted) toast(context, 'Only ${item!.stock} in stock');
    return;
  }
  await Repo.i.recordSale(
    student: who!,
    item: item!,
    qty: q,
    unitPrice: numOf(price),
    paid: numOf(paid),
  );
  if (context.mounted) toast(context, 'Sale saved');
}
