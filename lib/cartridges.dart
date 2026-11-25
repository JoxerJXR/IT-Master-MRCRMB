import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class CartridgeDatabase {
  CartridgeDatabase._();
  static final CartridgeDatabase instance = CartridgeDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = p.join(await getDatabasesPath(), 'it_master_local.db');
    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cartridges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL,
            model TEXT NOT NULL,
            printer_model TEXT NOT NULL,
            department TEXT NOT NULL,
            sender_name TEXT NOT NULL,
            received_at TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'В наличии'
          )
        ''');
        await db.execute('''
          CREATE TABLE movements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cartridge_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            date TEXT NOT NULL,
            person_name TEXT NOT NULL DEFAULT '',
            department TEXT NOT NULL DEFAULT '',
            destination TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            signature TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(cartridge_id) REFERENCES cartridges(id)
          )
        ''');
      },
    );
    return _database!;
  }

  Future<List<Map<String, Object?>>> getCartridges() async {
    final db = await database;
    return db.query('cartridges', orderBy: 'id DESC');
  }

  Future<List<Map<String, Object?>>> getMovements(int cartridgeId) async {
    final db = await database;
    return db.query(
      'movements',
      where: 'cartridge_id = ?',
      whereArgs: [cartridgeId],
      orderBy: 'id DESC',
    );
  }

  Future<void> addCartridge({
    required String code,
    required String model,
    required String printerModel,
    required String department,
    required String senderName,
    required String note,
    required String signature,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('cartridges', {
        'code': code,
        'model': model,
        'printer_model': printerModel,
        'department': department,
        'sender_name': senderName,
        'received_at': now,
        'note': note,
        'status': 'В наличии',
      });
      await txn.insert('movements', {
        'cartridge_id': id,
        'type': 'Приём',
        'date': now,
        'person_name': senderName,
        'department': department,
        'note': note,
        'signature': signature,
      });
    });
  }

  Future<void> addMovement({
    required int cartridgeId,
    required String type,
    required String personName,
    required String department,
    required String destination,
    required String note,
    required String signature,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.insert('movements', {
        'cartridge_id': cartridgeId,
        'type': type,
        'date': now,
        'person_name': personName,
        'department': department,
        'destination': destination,
        'note': note,
        'signature': signature,
      });
      await txn.update(
        'cartridges',
        {'status': type == 'Отправка на заправку' ? 'На заправке' : 'В наличии'},
        where: 'id = ?',
        whereArgs: [cartridgeId],
      );
    });
  }
}

class CartridgesPage extends StatefulWidget {
  const CartridgesPage({super.key});

  @override
  State<CartridgesPage> createState() => _CartridgesPageState();
}

class _CartridgesPageState extends State<CartridgesPage> {
  List<Map<String, Object?>> cartridges = [];
  bool loading = true;
  String filter = 'Все';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await CartridgeDatabase.instance.getCartridges();
    if (!mounted) return;
    setState(() {
      cartridges = rows;
      loading = false;
    });
  }

  Future<void> _openNew() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CartridgeIntakePage()),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = cartridges.where((item) {
      if (filter == 'Все') return true;
      return item['status'] == filter;
    }).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text('Принять картридж'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                children: [
                  Row(
                    children: [
                      Expanded(child: _SummaryCard(
                        title: 'Всего',
                        value: cartridges.length.toString(),
                        icon: Icons.inventory_2_outlined,
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _SummaryCard(
                        title: 'В наличии',
                        value: cartridges.where((e) => e['status'] == 'В наличии').length.toString(),
                        icon: Icons.check_circle_outline,
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _SummaryCard(
                        title: 'На заправке',
                        value: cartridges.where((e) => e['status'] == 'На заправке').length.toString(),
                        icon: Icons.local_shipping_outlined,
                      )),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Все', label: Text('Все')),
                      ButtonSegment(value: 'В наличии', label: Text('В наличии')),
                      ButtonSegment(value: 'На заправке', label: Text('Заправка')),
                    ],
                    selected: {filter},
                    onSelectionChanged: (value) => setState(() => filter = value.first),
                  ),
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 70),
                      child: Column(
                        children: [
                          Icon(Icons.print_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          const Text('Картриджей пока нет', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          const Text('Нажмите «Принять картридж», чтобы добавить первый.'),
                        ],
                      ),
                    )
                  else
                    ...visible.map((item) => _CartridgeTile(
                      item: item,
                      onChanged: _load,
                    )),
                ],
              ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _SummaryCard({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _CartridgeTile extends StatelessWidget {
  final Map<String, Object?> item;
  final VoidCallback onChanged;
  const _CartridgeTile({required this.item, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.print_rounded),
        ),
        title: Text(
          '${item['model']} · ${item['code']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Принтер: ${item['printer_model']}'),
              Text('Отделение: ${item['department']}'),
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(status, style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CartridgeDetailsPage(cartridge: item),
            ),
          );
          onChanged();
        },
      ),
    );
  }
}

class CartridgeIntakePage extends StatefulWidget {
  const CartridgeIntakePage({super.key});

  @override
  State<CartridgeIntakePage> createState() => _CartridgeIntakePageState();
}

class _CartridgeIntakePageState extends State<CartridgeIntakePage> {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController();
  final model = TextEditingController();
  final printer = TextEditingController();
  final department = TextEditingController();
  final sender = TextEditingController();
  final note = TextEditingController();
  final signature = SignatureController(penStrokeWidth: 2, penColor: Colors.black, exportBackgroundColor: Colors.white);
  bool saving = false;

  @override
  void dispose() {
    code.dispose();
    model.dispose();
    printer.dispose();
    department.dispose();
    sender.dispose();
    note.dispose();
    signature.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    if (signature.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нужна подпись сдающего.')));
      return;
    }
    setState(() => saving = true);
    try {
      final bytes = await signature.toPngBytes();
      if (bytes == null) throw Exception('Не удалось сохранить подпись');
      await CartridgeDatabase.instance.addCartridge(
        code: code.text.trim(),
        model: model.text.trim(),
        printerModel: printer.text.trim(),
        department: department.text.trim(),
        senderName: sender.text.trim(),
        note: note.text.trim(),
        signature: base64Encode(bytes),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Приём картриджа')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionTitle('Данные картриджа'),
            _field(code, 'Номер / код картриджа'),
            _field(model, 'Модель картриджа'),
            _field(printer, 'Модель принтера'),
            _field(department, 'Отделение'),
            const _SectionTitle('Кто сдал картридж'),
            _field(sender, 'ФИО сдающего'),
            _field(note, 'Примечание (необязательно)', required: false, maxLines: 2),
            const _SectionTitle('Подпись сдающего'),
            const Text('Попросите сотрудника расписаться в поле ниже.'),
            const SizedBox(height: 8),
            _SignaturePad(controller: signature),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(saving ? 'Сохранение...' : 'Сохранить приём'),
            ),
          ],
        ),
      ),
    );
  }
}

class CartridgeDetailsPage extends StatefulWidget {
  final Map<String, Object?> cartridge;
  const CartridgeDetailsPage({super.key, required this.cartridge});

  @override
  State<CartridgeDetailsPage> createState() => _CartridgeDetailsPageState();
}

class _CartridgeDetailsPageState extends State<CartridgeDetailsPage> {
  List<Map<String, Object?>> movements = [];
  bool loading = true;

  int get id => widget.cartridge['id'] as int;
  String get status => widget.cartridge['status'] as String;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await CartridgeDatabase.instance.getMovements(id);
    if (!mounted) return;
    setState(() {
      movements = rows;
      loading = false;
    });
  }

  Future<void> _movement(String type) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CartridgeMovementPage(cartridgeId: id, type: type),
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.cartridge;
    return Scaffold(
      appBar: AppBar(title: const Text('Карточка картриджа')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item['model']}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _info('Код', item['code']),
                  _info('Принтер', item['printer_model']),
                  _info('Отделение', item['department']),
                  _info('Сдал', item['sender_name']),
                  _info('Дата приёма', _date(item['received_at'] as String)),
                  _info('Статус', status),
                  if ((item['note'] as String).isNotEmpty) _info('Примечание', item['note']),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (status == 'В наличии')
            FilledButton.icon(
              onPressed: () => _movement('Отправка на заправку'),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Отправить на заправку'),
            )
          else
            FilledButton.icon(
              onPressed: () => _movement('Возврат'),
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('Оформить возврат'),
            ),
          const SizedBox(height: 20),
          const _SectionTitle('История движения'),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (movements.isEmpty)
            const Text('История пока пуста.')
          else
            ...movements.map((movement) => _MovementCard(movement: movement)),
        ],
      ),
    );
  }
}

class CartridgeMovementPage extends StatefulWidget {
  final int cartridgeId;
  final String type;
  const CartridgeMovementPage({super.key, required this.cartridgeId, required this.type});

  @override
  State<CartridgeMovementPage> createState() => _CartridgeMovementPageState();
}

class _CartridgeMovementPageState extends State<CartridgeMovementPage> {
  final formKey = GlobalKey<FormState>();
  final person = TextEditingController();
  final department = TextEditingController();
  final destination = TextEditingController();
  final note = TextEditingController();
  final signature = SignatureController(penStrokeWidth: 2, penColor: Colors.black, exportBackgroundColor: Colors.white);
  bool saving = false;

  bool get isReturn => widget.type == 'Возврат';

  @override
  void dispose() {
    person.dispose();
    department.dispose();
    destination.dispose();
    note.dispose();
    signature.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    if (isReturn && signature.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Подпись получателя обязательна.')));
      return;
    }
    setState(() => saving = true);
    try {
      String signatureData = '';
      if (isReturn) {
        final bytes = await signature.toPngBytes();
        if (bytes == null) throw Exception('Не удалось сохранить подпись');
        signatureData = base64Encode(bytes);
      }
      await CartridgeDatabase.instance.addMovement(
        cartridgeId: widget.cartridgeId,
        type: widget.type,
        personName: person.text.trim(),
        department: department.text.trim(),
        destination: destination.text.trim(),
        note: note.text.trim(),
        signature: signatureData,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.type)),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.type, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            if (isReturn) ...[
              _field(person, 'ФИО получателя'),
              _field(department, 'Отделение получателя'),
              const _SectionTitle('Подпись получателя'),
              const Text('Возврат нельзя сохранить без подписи получателя.'),
              const SizedBox(height: 8),
              _SignaturePad(controller: signature),
            ] else ...[
              _field(destination, 'Куда отправлен картридж'),
            ],
            _field(note, 'Примечание (необязательно)', required: false, maxLines: 3),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(saving ? 'Сохранение...' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementCard extends StatelessWidget {
  final Map<String, Object?> movement;
  const _MovementCard({required this.movement});

  @override
  Widget build(BuildContext context) {
    final type = movement['type'] as String;
    final signature = movement['signature'] as String? ?? '';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(type, style: const TextStyle(fontWeight: FontWeight.bold))),
                Text(_date(movement['date'] as String), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if ((movement['person_name'] as String).isNotEmpty) _info('ФИО', movement['person_name']),
            if ((movement['department'] as String).isNotEmpty) _info('Отделение', movement['department']),
            if ((movement['destination'] as String).isNotEmpty) _info('Куда отправлен', movement['destination']),
            if ((movement['note'] as String).isNotEmpty) _info('Примечание', movement['note']),
            if (signature.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Подпись:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                height: 90,
                width: 220,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
                child: Image.memory(base64Decode(signature), fit: BoxFit.contain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignaturePad extends StatelessWidget {
  final SignatureController controller;
  const _SignaturePad({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 175,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Signature(controller: controller, backgroundColor: Colors.white))),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: controller.clear,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Очистить подпись'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}

Widget _field(
  TextEditingController controller,
  String label, {
  bool required = true,
  int maxLines = 1,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: TextFormField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), filled: true),
      validator: required
          ? (value) => value == null || value.trim().isEmpty ? 'Заполните поле' : null
          : null,
    ),
  );
}

Widget _info(String label, Object? value) {
  return Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 112, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text(value?.toString() ?? '')),
      ],
    ),
  );
}

String _date(String value) {
  try {
    return DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(value).toLocal());
  } catch (_) {
    return value;
  }
}
