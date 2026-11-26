import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class CartridgeCodeAlreadyExists implements Exception {
  const CartridgeCodeAlreadyExists();
}

class CartridgeDatabase {
  CartridgeDatabase._();
  static final CartridgeDatabase instance = CartridgeDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = p.join(await getDatabasesPath(), 'it_master_local.db');
    _database = await openDatabase(
      dbPath,
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("UPDATE cartridges SET status = 'Принят' WHERE status = 'В наличии'");
          await db.execute("UPDATE movements SET type = 'Получение из заправки' WHERE type = 'Возврат'");
        }
      },
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

  Future<void> closeDatabase() async {
    final current = _database;
    if (current != null) {
      await current.close();
      _database = null;
    }
  }

  Future<List<Map<String, Object?>>> getCartridges() async {
    final db = await database;
    return db.query('cartridges', orderBy: 'id DESC');
  }

  Future<Map<String, Object?>?> getCartridge(int id) async {
    final db = await database;
    final rows = await db.query('cartridges', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
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

  Future<bool> isCartridgeCodeTaken(String code, {int? exceptId}) async {
    final db = await database;
    final normalized = code.trim();
    if (normalized.isEmpty) return false;
    final rows = await db.query(
      'cartridges',
      columns: ['id'],
      where: 'TRIM(code) = ? COLLATE NOCASE AND id != ?',
      whereArgs: [normalized, exceptId ?? -1],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> updateCartridgeCode(int id, String code) async {
    final normalized = code.trim();
    if (await isCartridgeCodeTaken(normalized, exceptId: id)) {
      throw const CartridgeCodeAlreadyExists();
    }
    final db = await database;
    await db.update('cartridges', {'code': normalized}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addCartridge({
    required String code,
    required String model,
    required String printerModel,
    required String department,
    required String senderName,
    required String note,
    required String signature,
    DateTime? receivedAt,
  }) async {
    final normalizedCode = code.trim();
    if (await isCartridgeCodeTaken(normalizedCode)) {
      throw const CartridgeCodeAlreadyExists();
    }
    final db = await database;
    await db.transaction((txn) async {
      final now = (receivedAt ?? DateTime.now()).toIso8601String();
      final id = await txn.insert('cartridges', {
        'code': code,
        'model': model,
        'printer_model': printerModel,
        'department': department,
        'sender_name': senderName,
        'received_at': now,
        'note': note,
        'status': 'Принят',
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

  Future<void> addBatchMovement({
    required List<int> ids, required String type, required String destination,
    String personName = '', String signature = '', String department = '', DateTime? movementDate,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = (movementDate ?? DateTime.now()).toIso8601String();
      for (final id in ids) {
        await txn.insert('movements', {
          'cartridge_id': id, 'type': type, 'date': now,
          'person_name': personName, 'department': department,
          'destination': destination, 'note': '', 'signature': signature,
        });
        await txn.update('cartridges', {
          'status': type == 'Отправка на заправку' ? 'На заправке' : 'Готов к выдаче',
        }, where: 'id = ?', whereArgs: [id]);
      }
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
    DateTime? movementDate,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = (movementDate ?? DateTime.now()).toIso8601String();
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
        {'status': type == 'Отправка на заправку' ? 'На заправке' : type == 'Получение из заправки' ? 'Готов к выдаче' : 'Выдан'},
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
  final Set<int> selectedIds = {};

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

  Future<void> _batch(String type) async {
    final destination = TextEditingController();
    final recipient = TextEditingController();
    final signatureController = SignatureController(penStrokeWidth: 2, penColor: Colors.black, exportBackgroundColor: Colors.white);
    final receiptDate = DateTime.now();
    String signatureData = '';
    bool confirmed = false;
    try {
      if (type == 'Отправка на заправку') {
        confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Отправка на заправку'),
          content: TextField(controller: destination, decoration: const InputDecoration(labelText: 'Куда отправлены картриджи')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, destination.text.trim().isNotEmpty), child: const Text('Отправить')),
          ],
        )) ?? false;
      } else {
        confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Получение из заправки'),
          content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Получено картриджей: ${selectedIds.length}'),
            const SizedBox(height: 8),
            Text('Дата получения: ${DateFormat('dd.MM.yyyy HH:mm').format(receiptDate)}'),
            const SizedBox(height: 12),
            TextField(controller: recipient, decoration: const InputDecoration(labelText: 'ФИО получателя *', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            const Text('Подпись получателя *'),
            const SizedBox(height: 6),
            Container(height: 150, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Theme.of(ctx).colorScheme.outline), borderRadius: BorderRadius.circular(8)),
              child: Signature(controller: signatureController, backgroundColor: Colors.white)),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: signatureController.clear, icon: const Icon(Icons.clear), label: const Text('Очистить подпись'))),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () {
              if (recipient.text.trim().isNotEmpty && !signatureController.isEmpty) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Укажите ФИО и поставьте подпись.')));
              }
            }, child: const Text('Подтвердить получение')),
          ],
        )) ?? false;
        if (confirmed) {
          final bytes = await signatureController.toPngBytes();
          if (bytes == null || bytes.isEmpty) {
            confirmed = false;
          } else {
            signatureData = base64Encode(bytes);
          }
        }
      }
      if (!confirmed) return;
      await CartridgeDatabase.instance.addBatchMovement(
        ids: selectedIds.toList(), type: type, destination: destination.text.trim(),
        personName: recipient.text.trim(), signature: signatureData, movementDate: receiptDate,
      );
      if (!mounted) return;
      setState(() => selectedIds.clear());
      await _load();
    } finally {
      destination.dispose();
      recipient.dispose();
      signatureController.dispose();
    }
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
                        title: 'К выдаче',
                        value: cartridges.where((e) => e['status'] == 'Готов к выдаче').length.toString(),
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
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.qr_code_scanner),
                      title: const Text('Сканировать QR картриджа'),
                      subtitle: const Text('Открыть карточку по наклейке'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const CartridgeScannerPage()));
                        await _load();
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Все', label: Text('Все')),
                        ButtonSegment(value: 'Принят', label: Text('Приняты')),
                        ButtonSegment(value: 'На заправке', label: Text('Заправка')),
                        ButtonSegment(value: 'Готов к выдаче', label: Text('К выдаче')),
                        ButtonSegment(value: 'Выдан', label: Text('Выданные')),
                      ],
                      selected: {filter},
                      onSelectionChanged: (value) => setState(() {
                        filter = value.first;
                        selectedIds.clear();
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (selectedIds.isNotEmpty) Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('Выбрано картриджей: ${selectedIds.length}'),
                        if (selectedIds.every((id) => cartridges.any((c) => c['id'] == id && c['status'] == 'Принят')))
                          FilledButton.icon(onPressed: () => _batch('Отправка на заправку'), icon: const Icon(Icons.local_shipping), label: const Text('Отправить выбранные на заправку')),
                        if (selectedIds.every((id) => cartridges.any((c) => c['id'] == id && c['status'] == 'На заправке')))
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text('Получение и выдачу оформляйте в карточке каждого картриджа отдельно — ФИО и подпись будут сохранены именно у него.'),
                          ),
                        TextButton(onPressed: () => setState(() => selectedIds.clear()), child: const Text('Снять выделение')),
                      ]),
                    ),
                  ),
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
                      selected: selectedIds.contains(item['id']),
                      onSelect: (v) => setState(() { v ? selectedIds.add(item['id'] as int) : selectedIds.remove(item['id'] as int); }),
                      onChanged: _load,
                    )),
                ],
              ),
            ),
    );
  }
}

class CartridgeQrPage extends StatelessWidget {
  final Map<String, Object?> cartridge;
  const CartridgeQrPage({super.key, required this.cartridge});

  @override
  Widget build(BuildContext context) {
    final id = cartridge['id'] as int;
    final code = (cartridge['code'] ?? '').toString();
    final model = (cartridge['model'] ?? '').toString();
    final qrValue = 'ITMASTER-CARTRIDGE:$id';
    return Scaffold(
      appBar: AppBar(title: const Text('QR-код картриджа')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(model, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text('Номер: $code', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  QrImageView(data: qrValue, version: QrVersions.auto, size: 240),
                  const SizedBox(height: 8),
                  Text('ID картриджа: $id'),
                  const SizedBox(height: 8),
                  const Text('Этот код закреплён за конкретным картриджем.'),
                  const SizedBox(height: 12),
                  SelectableText(qrValue, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CartridgeScannerPage extends StatefulWidget {
  const CartridgeScannerPage({super.key});

  @override
  State<CartridgeScannerPage> createState() => _CartridgeScannerPageState();
}

class _CartridgeScannerPageState extends State<CartridgeScannerPage> {
  bool _opening = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_opening) return;
    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (raw == null || !raw.startsWith('ITMASTER-CARTRIDGE:')) return;
    final id = int.tryParse(raw.substring('ITMASTER-CARTRIDGE:'.length));
    if (id == null) return;
    _opening = true;
    final cartridge = await CartridgeDatabase.instance.getCartridge(id);
    if (!mounted) return;
    if (cartridge == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Картридж с таким QR-кодом не найден.')));
      _opening = false;
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CartridgeDetailsPage(cartridge: cartridge)));
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Сканирование картриджа')),
    body: Stack(
      children: [
        MobileScanner(onDetect: _onDetect),
        Center(
          child: Container(
            width: 260,
            height: 190,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const Positioned(
          left: 20, right: 20, bottom: 32,
          child: Card(child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('Наведите камеру на QR-наклейку картриджа.', textAlign: TextAlign.center),
          )),
        ),
      ],
    ),
  );
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
  final bool selected;
  final ValueChanged<bool> onSelect;
  const _CartridgeTile({required this.item, required this.onChanged, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false)),
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
  DateTime receivedAt = DateTime.now();
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
        receivedAt: receivedAt,
      );
      if (mounted) Navigator.pop(context, true);
    } on CartridgeCodeAlreadyExists {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Такой номер занят')),
        );
      }
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
            _DateField(value: receivedAt, onChanged: (v) => setState(() => receivedAt = v)),
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
  Map<String, Object?>? currentCartridge;
  bool loading = true;

  int get id => widget.cartridge['id'] as int;
  String get status => (currentCartridge?['status'] ?? widget.cartridge['status']) as String;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await Future.wait([
      CartridgeDatabase.instance.getMovements(id),
      CartridgeDatabase.instance.getCartridge(id),
    ]);
    if (!mounted) return;
    setState(() {
      movements = result[0] as List<Map<String, Object?>>;
      currentCartridge = result[1] as Map<String, Object?>?;
      loading = false;
    });
  }

  Future<void> _editCode() async {
    final controller = TextEditingController(text: (currentCartridge?['code'] ?? widget.cartridge['code']).toString());
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Номер картриджа'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Номер / код', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    try {
      await CartridgeDatabase.instance.updateCartridgeCode(id, value);
      await _load();
    } on CartridgeCodeAlreadyExists {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Такой номер занят')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось изменить номер: $e')),
        );
      }
    }
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
    final item = currentCartridge ?? widget.cartridge;
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
                  Row(
                    children: [
                      Expanded(child: _info('Номер', item['code'])),
                      IconButton(
                        tooltip: 'Изменить номер',
                        onPressed: _editCode,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  _info('Принтер', item['printer_model']),
                  _info('Отделение', item['department']),
                  _info('Сдал', item['sender_name']),
                  _info('Дата приёма', _date(item['received_at'] as String)),
                  _info('Статус', status),
                  if ((item['note'] as String).isNotEmpty) _info('Примечание', item['note']),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CartridgeQrPage(cartridge: item),
                    )),
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Показать QR-код и наклейку'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (status == 'Принят' || status == 'Готов к выдаче')
            FilledButton.icon(
              onPressed: () => _movement(status == 'Принят' ? 'Отправка на заправку' : 'Выдача'),
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(status == 'Принят' ? 'Отправить на заправку' : 'Выдать сотруднику'),
            )
          else if (status == 'На заправке')
            FilledButton.icon(
              onPressed: () => _movement('Получение из заправки'),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Получить из заправки'),
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

  bool get isReturn => widget.type == 'Выдача';
  bool get isRefillReceipt => widget.type == 'Получение из заправки';
  bool get requiresSignature => isReturn || isRefillReceipt;
  DateTime movementDate = DateTime.now();

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
    if (requiresSignature && signature.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isRefillReceipt ? 'Подпись принимающего обязательна.' : 'Подпись получателя обязательна.')));
      return;
    }
    setState(() => saving = true);
    try {
      String signatureData = '';
      if (requiresSignature) {
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
        movementDate: movementDate,
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
             _DateField(value: movementDate, onChanged: (v) => setState(() => movementDate = v)),
            if (isReturn || isRefillReceipt) ...[
              _field(person, isRefillReceipt ? 'ФИО принимающего' : 'ФИО получателя'),
              if (isReturn) _field(department, 'Отделение получателя'),
              _SectionTitle(isRefillReceipt ? 'Подпись принимающего' : 'Подпись получателя'),
              Text(isRefillReceipt
                  ? 'Подпись сохранится отдельно в истории этого картриджа.'
                  : 'Выдача сохраняется только с подписью получателя.'),
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
              label: Text(saving ? 'Сохранение...' : isReturn ? 'Оформить выдачу' : isRefillReceipt ? 'Подтвердить получение' : 'Сохранить'),
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
    Uint8List? signatureBytes;
    if (signature.isNotEmpty) {
      try {
        signatureBytes = base64Decode(signature);
      } catch (_) {
        signatureBytes = null;
      }
    }
    final imageBytes = signatureBytes;
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
              const SizedBox(height: 6),
              if (imageBytes == null)
                const Text('Не удалось прочитать изображение подписи.')
              else
                GestureDetector(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => Dialog(
                      insetPadding: const EdgeInsets.all(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 5,
                          child: Image.memory(
                            imageBytes,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Text('Не удалось отобразить подпись.'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: Container(
                    width: double.infinity,
                    height: 150,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(child: Text('Не удалось отобразить подпись.')),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              const Text('Нажмите на подпись, чтобы увеличить её.', style: TextStyle(fontSize: 11)),
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
      height: 230,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Signature(
                key: const ValueKey('single-signature-canvas'),
                controller: controller,
                backgroundColor: Colors.white,
              ),
            ),
          ),
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


class _DateField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const _DateField({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: OutlinedButton.icon(
      icon: const Icon(Icons.calendar_month),
      label: Text('Дата: ${DateFormat('dd.MM.yyyy HH:mm').format(value)}'),
      onPressed: () async {
        final day = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (day == null || !context.mounted) return;
        final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(value));
        if (time == null) return;
        onChanged(DateTime(day.year, day.month, day.day, time.hour, time.minute));
      },
    ),
  );
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
