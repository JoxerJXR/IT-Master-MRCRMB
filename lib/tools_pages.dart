import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xls;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'cartridges.dart';

class ConsumablesPage extends StatefulWidget {
  const ConsumablesPage({super.key});
  @override
  State<ConsumablesPage> createState() => _ConsumablesPageState();
}

class _ConsumablesPageState extends State<ConsumablesPage> {
  List<Map<String, Object?>> rows = [];
  bool loading = true;
  String search = '';
  Future<Database> get db => CartridgeDatabase.instance.database;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final d = await db;
    await d.execute('''CREATE TABLE IF NOT EXISTS it_consumables (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'Другое', quantity INTEGER NOT NULL DEFAULT 0,
      unit TEXT NOT NULL DEFAULT 'шт.', minimum INTEGER NOT NULL DEFAULT 0,
      location TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS it_consumable_movements (
      id INTEGER PRIMARY KEY AUTOINCREMENT, consumable_id INTEGER NOT NULL,
      action TEXT NOT NULL, amount INTEGER NOT NULL, date TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '')''');
    final data = await d.query('it_consumables', orderBy: 'name COLLATE NOCASE');
    if (mounted) setState(() { rows = data; loading = false; });
  }

  Future<void> _edit([Map<String, Object?>? item]) async {
    final name = TextEditingController(text: item?['name'] as String? ?? '');
    final quantity = TextEditingController(text: item?['quantity']?.toString() ?? '0');
    final minimum = TextEditingController(text: item?['minimum']?.toString() ?? '0');
    final unit = TextEditingController(text: item?['unit'] as String? ?? 'шт.');
    final location = TextEditingController(text: item?['location'] as String? ?? '');
    final note = TextEditingController(text: item?['note'] as String? ?? '');
    String category = item?['category'] as String? ?? 'Тонер';
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(item == null ? 'Новый расходный материал' : 'Редактирование'),
      content: SizedBox(width: 420, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Наименование *'), validator: (v) => v == null || v.trim().isEmpty ? 'Укажите название' : null),
        DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Категория'),
          items: ['Тонер','Картридж','Бумага','Кабель','Комплектующие','Чернила','Другое'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => category = v ?? category),
        TextFormField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Остаток'), validator: (v) => int.tryParse(v ?? '') == null || int.parse(v!) < 0 ? 'Введите число от 0' : null),
        TextFormField(controller: minimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Минимальный остаток'), validator: (v) => int.tryParse(v ?? '') == null || int.parse(v!) < 0 ? 'Введите число от 0' : null),
        TextField(controller: unit, decoration: const InputDecoration(labelText: 'Единица измерения')),
        TextField(controller: location, decoration: const InputDecoration(labelText: 'Место хранения')),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Примечание'), maxLines: 2),
      ])))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(c, true); }, child: const Text('Сохранить')),
      ],
    ));
    if (ok == true) {
      final d = await db;
      final values = <String, Object?>{
        'name': name.text.trim(), 'category': category,
        'quantity': int.parse(quantity.text), 'minimum': int.parse(minimum.text),
        'unit': unit.text.trim().isEmpty ? 'шт.' : unit.text.trim(),
        'location': location.text.trim(), 'note': note.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (item == null) {
        final id = await d.insert('it_consumables', values);
        await d.insert('it_consumable_movements', {
          'consumable_id': id,
          'action': 'Начальный остаток',
          'amount': int.parse(quantity.text),
          'date': DateTime.now().toIso8601String(),
          'note': 'Создание позиции',
        });
      } else {
        final oldQuantity = item['quantity'] as int;
        final newQuantity = int.parse(quantity.text);
        final difference = newQuantity - oldQuantity;
        await d.transaction((t) async {
          await t.update('it_consumables', values, where: 'id=?', whereArgs: [item['id']]);
          if (difference != 0) {
            await t.insert('it_consumable_movements', {
              'consumable_id': item['id'],
              'action': 'Корректировка остатка',
              'amount': difference,
              'date': DateTime.now().toIso8601String(),
              'note': 'Ручное изменение остатка: было $oldQuantity, стало $newQuantity',
            });
          }
        });
      }
      await _load();
    }
    for (final c in [name, quantity, minimum, unit, location, note]) { c.dispose(); }
  }

  Future<void> _change(Map<String, Object?> item, bool add) async {
    final controller = TextEditingController(text: '1');
    final note = TextEditingController();
    final form = GlobalKey<FormState>();
    final amount = await showDialog<int>(context: context, builder: (c) => AlertDialog(
      title: Text(add ? 'Поступление' : 'Выдача / списание'),
      content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(item['name'] as String),
        TextFormField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Количество'),
          validator: (v) { final n = int.tryParse(v ?? ''); if (n == null || n <= 0) return 'Введите число больше нуля'; if (!add && n > (item['quantity'] as int)) return 'Недостаточно остатка'; return null; }),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Кому / основание')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(c, int.parse(controller.text)); }, child: const Text('Провести')),
      ],
    ));
    if (amount != null) {
      final d = await db;
      final delta = add ? amount : -amount;
      await d.transaction((t) async {
        await t.rawUpdate('UPDATE it_consumables SET quantity = quantity + ?, updated_at = ? WHERE id = ?',
          [delta, DateTime.now().toIso8601String(), item['id']]);
        await t.insert('it_consumable_movements', {
          'consumable_id': item['id'], 'action': add ? 'Поступление' : 'Выдача / списание',
          'amount': amount, 'date': DateTime.now().toIso8601String(), 'note': note.text.trim(),
        });
      });
      await _load();
    }
    controller.dispose(); note.dispose();
  }

  Future<void> _history(Map<String, Object?> item) async {
    final data = await (await db).query('it_consumable_movements', where: 'consumable_id=?', whereArgs: [item['id']], orderBy: 'id DESC');
    if (!mounted) return;
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (c) => SafeArea(child: SizedBox(
      height: MediaQuery.of(c).size.height * .65,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Движение: ${item['name']}', style: Theme.of(c).textTheme.titleLarge),
        if (data.isEmpty) const Text('История отсутствует.'),
        ...data.map((m) => ListTile(leading: const Icon(Icons.swap_vert), title: Text('${m['action']} · ${m['amount']}'),
          subtitle: Text('${m['date']}\n${m['note']}'))),
      ]),
    )));
  }

  Future<void> _delete(Map<String, Object?> item) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Удалить позицию?'), content: Text(item['name'] as String),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить'))],
    ));
    if (ok == true) {
      final d = await db;
      await d.transaction((t) async {
        await t.delete('it_consumable_movements', where: 'consumable_id=?', whereArgs: [item['id']]);
        await t.delete('it_consumables', where: 'id=?', whereArgs: [item['id']]);
      });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((r) => (r['name'] as String).toLowerCase().contains(search.toLowerCase()) ||
      (r['category'] as String).toLowerCase().contains(search.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Расходные материалы')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Добавить')),
      body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
          TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск расходников', border: OutlineInputBorder()), onChanged: (v) => setState(() => search = v)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _StockStat(label: 'Позиций', value: rows.length.toString(), icon: Icons.inventory_2)),
            Expanded(child: _StockStat(label: 'Низкий остаток', value: rows.where((r) => (r['quantity'] as int) <= (r['minimum'] as int)).length.toString(), icon: Icons.warning_amber)),
          ]),
          ...visible.map((r) {
            final low = (r['quantity'] as int) <= (r['minimum'] as int);
            return Card(elevation: 0, child: ListTile(
              leading: CircleAvatar(child: Icon(low ? Icons.warning_amber : Icons.inventory_2, color: low ? Colors.deepOrange : null)),
              title: Text(r['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${r['category']} · Остаток: ${r['quantity']} ${r['unit']} · минимум ${r['minimum']}\n${r['location']}'),
              isThreeLine: true,
              onTap: () => _edit(r),
              trailing: PopupMenuButton<String>(onSelected: (v) {
                if (v == 'in') _change(r, true);
                if (v == 'out') _change(r, false);
                if (v == 'history') _history(r);
                if (v == 'edit') _edit(r);
                if (v == 'delete') _delete(r);
              }, itemBuilder: (_) => const [
                PopupMenuItem(value: 'in', child: Text('Поступление')),
                PopupMenuItem(value: 'out', child: Text('Выдача / списание')),
                PopupMenuItem(value: 'history', child: Text('История движения')),
                PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ]),
            ));
          }),
          if (visible.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Позиции не найдены.', textAlign: TextAlign.center)),
        ])),
    );
  }
}

class _StockStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StockStat({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(12),
    child: Column(children: [Icon(icon), Text(value, style: Theme.of(context).textTheme.titleLarge), Text(label)])));
}

class NetworkToolsPage extends StatefulWidget {
  const NetworkToolsPage({super.key});
  @override
  State<NetworkToolsPage> createState() => _NetworkToolsPageState();
}

class _NetworkToolsPageState extends State<NetworkToolsPage> {
  final host = TextEditingController(text: '192.168.1.1');
  final port = TextEditingController(text: '80');
  bool checking = false;
  String result = 'Введите IP-адрес или имя узла и порт для проверки TCP-соединения.';
  List<String> addresses = [];

  Future<void> _local() async {
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false, type: InternetAddressType.IPv4);
      if (!mounted) return;
      setState(() => addresses = interfaces.expand((i) => i.addresses.map((a) => '${i.name}: ${a.address}')).toList());
    } catch (e) {
      if (mounted) setState(() => addresses = ['Не удалось получить адреса: $e']);
    }
  }

  Future<void> _check() async {
    final h = host.text.trim();
    final p = int.tryParse(port.text.trim());
    if (h.isEmpty || p == null || p < 1 || p > 65535) {
      setState(() => result = 'Укажите корректный адрес и порт от 1 до 65535.');
      return;
    }
    setState(() { checking = true; result = 'Проверка DNS и TCP-порта…'; });
    final lines = <String>[];
    try {
      final resolved = await InternetAddress.lookup(h).timeout(const Duration(seconds: 5));
      lines.add('DNS: успешно. Адреса: ${resolved.map((a) => a.address).join(', ')}');
    } catch (e) {
      lines.add('DNS: ошибка или узел не найден ($e)');
    }
    try {
      final socket = await Socket.connect(h, p, timeout: const Duration(seconds: 4));
      socket.destroy();
      lines.add('TCP порт $p: ДОСТУПЕН');
    } catch (e) {
      lines.add('TCP порт $p: недоступен или соединение отклонено ($e)');
    }
    if (mounted) setState(() { result = lines.join('\n'); checking = false; });
  }

  @override
  void initState() { super.initState(); _local(); }
  @override
  void dispose() { host.dispose(); port.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Проверка сети')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Проверка выполняет DNS-разрешение и TCP-подключение к выбранному порту. Это не ICMP ping: закрытый порт не означает, что устройство выключено.'))),
      TextField(controller: host, decoration: const InputDecoration(labelText: 'IP-адрес или имя узла', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'TCP-порт (например 80, 443, 445, 9100)', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: checking ? null : _check, icon: const Icon(Icons.network_check), label: Text(checking ? 'Проверка…' : 'Проверить соединение')),
      const SizedBox(height: 14),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: SelectableText(result))),
      const SizedBox(height: 12),
      Text('Локальные IPv4-адреса', style: Theme.of(context).textTheme.titleMedium),
      if (addresses.isEmpty) const Text('Адреса не обнаружены.'),
      ...addresses.map((a) => ListTile(dense: true, leading: const Icon(Icons.lan), title: SelectableText(a))),
      OutlinedButton.icon(onPressed: _local, icon: const Icon(Icons.refresh), label: const Text('Обновить адреса')),
    ]));
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  Map<String, int> stats = {};
  bool loading = true;
  bool exporting = false;

  Future<int> _count(Database db, String table, {String? where}) async {
    try {
      final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}');
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (_) { return 0; }
  }

  Future<void> _load() async {
    final db = await CartridgeDatabase.instance.database;
    final values = <String, int>{
      'Картриджи': await _count(db, 'cartridges'),
      'Картриджи на заправке': await _count(db, 'cartridges', where: "status='На заправке'"),
      'Картриджи готовы к выдаче': await _count(db, 'cartridges', where: "status='Готов к выдаче'"),
      'Картриджи выданы': await _count(db, 'cartridges', where: "status='Выдан'"),
      'Оборудование': await _count(db, 'it_equipment'),
      'Неисправное оборудование': await _count(db, 'it_equipment', where: "status='Неисправно'"),
      'Заявки': await _count(db, 'service_requests'),
      'Новые заявки': await _count(db, 'service_requests', where: "status='Новая'"),
      'Заявки в работе': await _count(db, 'service_requests', where: "status='В работе'"),
      'Сотрудники': await _count(db, 'revision_employees', where: 'active=1'),
      'Имущество на руках': await _count(db, 'revision_assets', where: "status='На руках'"),
      'Имущество на складе': await _count(db, 'revision_assets', where: "status='На складе'"),
      'Расходные материалы': await _count(db, 'it_consumables'),
      'Расходники с низким остатком': await _count(db, 'it_consumables', where: 'quantity <= minimum'),
    };
    if (mounted) setState(() { stats = values; loading = false; });
  }

  Future<void> _beginExport() async {
    if (exporting) return;
    setState(() => exporting = true);
  }

  Future<void> _exportExcel() async {
    await _beginExport();
    try {
      final book = xls.Excel.createExcel();
      final sheet = book['Сводный отчёт'];
      sheet.appendRow([xls.TextCellValue('Раздел'), xls.TextCellValue('Количество')]);
      for (final entry in stats.entries) {
        sheet.appendRow([xls.TextCellValue(entry.key), xls.IntCellValue(entry.value)]);
      }
      final bytes = book.save();
      if (bytes == null || bytes.isEmpty) throw Exception('Не удалось сформировать XLSX.');
      final file = XFile.fromData(Uint8List.fromList(bytes),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: 'IT-Master-report.xlsx');
      await SharePlus.instance.share(ShareParams(files: [file], text: 'Отчёт IT-Мастер в формате Excel'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка экспорта Excel: $e')));
    } finally { if (mounted) setState(() => exporting = false); }
  }

  Future<void> _exportPdf() async {
    await _beginExport();
    try {
      final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
      final font = pw.Font.ttf(fontData);
      final document = pw.Document();
      final now = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());
      document.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (_) => [
          pw.Text('IT-Мастер — сводный отчёт', style: pw.TextStyle(font: font, fontSize: 18)),
          pw.SizedBox(height: 6),
          pw.Text('Сформирован: $now', style: pw.TextStyle(font: font, fontSize: 9)),
          pw.SizedBox(height: 18),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
            columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1)},
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('Раздел', style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('Количество', style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold))),
                ],
              ),
              ...stats.entries.map((entry) => pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text(entry.key, style: pw.TextStyle(font: font, fontSize: 10))),
                pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text(entry.value.toString(), style: pw.TextStyle(font: font, fontSize: 10))),
              ])),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('Отчёт сформирован приложением IT-Мастер. Данные взяты из локальной базы устройства.',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
        ],
      ));
      final bytes = await document.save();
      final file = XFile.fromData(bytes, mimeType: 'application/pdf', name: 'IT-Master-report.pdf');
      await SharePlus.instance.share(ShareParams(files: [file], text: 'Отчёт IT-Мастер в формате PDF'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка экспорта PDF: $e')));
    } finally { if (mounted) setState(() => exporting = false); }
  }

  Future<void> _exportCsv() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'it_master_report_${DateTime.now().millisecondsSinceEpoch}.csv'));
      final lines = ['Раздел;Количество', ...stats.entries.map((e) => '${e.key};${e.value}')];
      await file.writeAsString('\uFEFF${lines.join('\n')}');
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Отчёт IT-Мастер CSV'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка экспорта CSV: $e')));
    }
  }

  @override
  void initState() { super.initState(); _load(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Отчёты и статистика')),
    body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Текущие показатели локальной базы данных. Экспортируйте сводку для передачи или печати.'),
        const SizedBox(height: 10),
        ...stats.entries.map((e) => Card(elevation: 0, child: ListTile(
          leading: const Icon(Icons.analytics_outlined), title: Text(e.key),
          trailing: Text(e.value.toString(), style: Theme.of(context).textTheme.titleLarge)))),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: exporting ? null : _exportExcel,
          icon: const Icon(Icons.table_view), label: Text(exporting ? 'Формирование…' : 'Экспортировать Excel (.xlsx)')),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: exporting ? null : _exportPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Экспортировать PDF')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: exporting ? null : _exportCsv,
          icon: const Icon(Icons.file_download_outlined), label: const Text('Экспортировать CSV')),
      ]),
    ),
  );
}
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool busy = false;
  String message = 'Резервная копия содержит локальную базу: картриджи, заявки, оборудование, ревизию и расходные материалы. Защищённые личные заметки хранятся отдельно в Android и в этот файл не входят.';

  Future<void> _backup() async {
    setState(() => busy = true);
    try {
      await CartridgeDatabase.instance.closeDatabase();
      final dbPath = p.join(await getDatabasesPath(), 'it_master_local.db');
      final source = File(dbPath);
      if (!await source.exists()) throw Exception('База данных ещё не создана.');
      final dir = await getTemporaryDirectory();
      final target = File(p.join(dir.path, 'IT-Master-backup-${DateTime.now().toIso8601String().replaceAll(':', '-')}.db'));
      await source.copy(target.path);
      await SharePlus.instance.share(ShareParams(files: [XFile(target.path)], text: 'Резервная копия IT-Мастер'));
      if (mounted) setState(() => message = 'Файл резервной копии подготовлен для сохранения или отправки.');
    } catch (e) {
      if (mounted) setState(() => message = 'Ошибка создания копии: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Восстановить базу?'),
      content: const Text('Текущая база данных будет заменена содержимым выбранной копии. Перед продолжением рекомендуется сначала сохранить текущую базу.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Продолжить'))],
    ));
    if (ok != true) return;
    setState(() => busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['db'], withData: false);
      final path = picked?.files.single.path;
      if (path == null) return;

      // Validate the selected SQLite file before touching the current database.
      final candidate = await openDatabase(path, readOnly: true);
      try {
        final integrity = await candidate.rawQuery('PRAGMA integrity_check');
        final integrityResult = integrity.isEmpty ? '' : integrity.first.values.first.toString();
        if (integrityResult.toLowerCase() != 'ok') {
          throw Exception('Файл повреждён: проверка SQLite не пройдена.');
        }
        final tables = await candidate.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        );
        final names = tables.map((row) => row['name'].toString()).toSet();
        if (!names.containsAll({'cartridges', 'movements'})) {
          throw Exception('Выбранный файл не является резервной копией IT-Мастер.');
        }
      } finally {
        await candidate.close();
      }

      final dbPath = p.join(await getDatabasesPath(), 'it_master_local.db');
      final current = File(dbPath);
      final tempDir = await getTemporaryDirectory();
      final safetyCopy = File(p.join(
        tempDir.path,
        'IT-Master-before-restore-${DateTime.now().millisecondsSinceEpoch}.db',
      ));
      await CartridgeDatabase.instance.closeDatabase();

      // Keep a safety copy so a failed replacement can be rolled back.
      final hadCurrent = await current.exists();
      if (hadCurrent) await current.copy(safetyCopy.path);
      try {
        await File(path).copy(dbPath);
        await CartridgeDatabase.instance.database;
        await CartridgeDatabase.instance.closeDatabase();
      } catch (_) {
        if (hadCurrent && await safetyCopy.exists()) {
          await safetyCopy.copy(dbPath);
        }
        rethrow;
      }
      if (mounted) {
        setState(() => message =
          'База проверена и восстановлена. Создана страховочная копия предыдущей базы. Перезапустите приложение, чтобы обновить все разделы.');
      }
    } catch (e) {
      if (mounted) setState(() => message = 'Ошибка восстановления: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Резервное копирование')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Icon(Icons.backup_outlined, size: 56),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(message))),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: busy ? null : _backup, icon: const Icon(Icons.save_alt), label: Text(busy ? 'Подождите…' : 'Создать и отправить копию')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: busy ? null : _restore, icon: const Icon(Icons.restore), label: const Text('Восстановить из файла .db')),
    ]));
}
