import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'cartridges.dart';

class RevisionPage extends StatefulWidget {
  const RevisionPage({super.key});
  @override
  State<RevisionPage> createState() => _RevisionPageState();
}

class _RevisionPageState extends State<RevisionPage> {
  List<Map<String, Object?>> employees = [];
  bool loading = true;
  String search = '';
  Future<Database> get db => CartridgeDatabase.instance.database;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final d = await db;
    await d.execute('''CREATE TABLE IF NOT EXISTS revision_employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT, full_name TEXT NOT NULL,
      department TEXT NOT NULL DEFAULT '', position TEXT NOT NULL DEFAULT '',
      active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS revision_assets (
      id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, category TEXT NOT NULL,
      model TEXT NOT NULL DEFAULT '', inventory_number TEXT NOT NULL DEFAULT '',
      serial_number TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '',
      employee_id INTEGER, status TEXT NOT NULL DEFAULT 'На руках', created_at TEXT NOT NULL)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS revision_movements (
      id INTEGER PRIMARY KEY AUTOINCREMENT, asset_id INTEGER NOT NULL, action TEXT NOT NULL,
      from_employee_id INTEGER, to_employee_id INTEGER, date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '')''');
    final rows = await d.query('revision_employees', where: 'active = 1', orderBy: 'full_name COLLATE NOCASE');
    if (mounted) setState(() { employees = rows; loading = false; });
  }

  Future<int> _count(int id) async {
    final r = await (await db).rawQuery("SELECT COUNT(*) AS n FROM revision_assets WHERE employee_id=? AND status='На руках'", [id]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<void> _addEmployee() async {
    final name = TextEditingController();
    final dep = TextEditingController();
    final pos = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Новый сотрудник'),
      content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'ФИО'), validator: (v) => v == null || v.trim().isEmpty ? 'Укажите ФИО' : null),
        TextField(controller: dep, decoration: const InputDecoration(labelText: 'Отделение')),
        TextField(controller: pos, decoration: const InputDecoration(labelText: 'Должность')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(c, true); }, child: const Text('Сохранить'))
      ],
    ));
    if (ok == true) {
      await (await db).insert('revision_employees', {'full_name': name.text.trim(), 'department': dep.text.trim(), 'position': pos.text.trim(), 'active': 1, 'created_at': DateTime.now().toIso8601String()});
      await _load();
    }
    name.dispose(); dep.dispose(); pos.dispose();
  }

  Future<void> _archive(Map<String, Object?> employee) async {
    final d = await db;
    final id = employee['id'] as int;
    final assets = await d.query('revision_assets', where: "employee_id=? AND status='На руках'", whereArgs: [id]);
    final targets = employees.where((e) => e['id'] != id).toList();
    int? target = targets.isEmpty ? null : targets.first['id'] as int;
    bool warehouse = targets.isEmpty;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
      title: const Text('Увольнение сотрудника'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${employee['full_name']}'),
        Text('Закреплено имущества: ${assets.length} поз.'),
        if (assets.isNotEmpty) ...[
          const SizedBox(height: 10), const Text('Передать всё имущество:'),
          if (targets.isNotEmpty) DropdownButton<int>(isExpanded: true, value: target,
            items: targets.map((e) => DropdownMenuItem(value: e['id'] as int, child: Text(e['full_name'] as String, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setD(() { target = v; warehouse = false; })),
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: warehouse, title: const Text('Вернуть на склад'),
            onChanged: (v) => setD(() { warehouse = v ?? false; })),
        ],
        const Text('Сотрудник исчезнет из активного списка, история сохранится.'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Уволить'))
      ],
    )));
    if (ok != true) return;
    await d.transaction((t) async {
      final now = DateTime.now().toIso8601String();
      for (final a in assets) {
        await t.insert('revision_movements', {'asset_id': a['id'], 'action': warehouse ? 'Возврат на склад при увольнении' : 'Передача при увольнении',
          'from_employee_id': id, 'to_employee_id': warehouse ? null : target, 'date': now, 'note': 'Увольнение: ${employee['full_name']}'});
        await t.update('revision_assets', {'employee_id': warehouse ? null : target, 'status': warehouse ? 'На складе' : 'На руках'}, where: 'id=?', whereArgs: [a['id']]);
      }
      await t.update('revision_employees', {'active': 0}, where: 'id=?', whereArgs: [id]);
    });
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сотрудник архивирован. Имущество переоформлено.')));
  }

  @override
  Widget build(BuildContext context) {
    final list = employees.where((e) => (e['full_name'] as String).toLowerCase().contains(search.toLowerCase()) ||
      (e['department'] as String).toLowerCase().contains(search.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Ревизия имущества')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addEmployee, icon: const Icon(Icons.person_add), label: const Text('Сотрудник')),
      body: loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск сотрудника или отделения', border: OutlineInputBorder()), onChanged: (v) => setState(() => search = v))),
        Expanded(child: list.isEmpty ? const Center(child: Text('Сотрудников пока нет. Добавьте первого сотрудника.')) :
          ListView.builder(padding: const EdgeInsets.fromLTRB(12, 0, 12, 90), itemCount: list.length, itemBuilder: (c, i) {
            final e = list[i];
            return FutureBuilder<int>(future: _count(e['id'] as int), builder: (c, snap) => Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(e['full_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${e['department']} ${e['position']} • Имущества: ${snap.data ?? 0}'),
              trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'archive') _archive(e); },
                itemBuilder: (_) => const [PopupMenuItem(value: 'archive', child: Text('Уволить / архивировать'))]),
              onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => RevisionEmployeePage(employee: e))); await _load(); },
            )));
          })),
      ]),
    );
  }
}

class RevisionEmployeePage extends StatefulWidget {
  final Map<String, Object?> employee;
  const RevisionEmployeePage({super.key, required this.employee});
  @override
  State<RevisionEmployeePage> createState() => _RevisionEmployeePageState();
}

class _RevisionEmployeePageState extends State<RevisionEmployeePage> {
  List<Map<String, Object?>> assets = [], employees = [];
  bool loading = true;
  Future<Database> get db => CartridgeDatabase.instance.database;
  int get employeeId => widget.employee['id'] as int;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final d = await db;
    final r = await Future.wait([
      d.query('revision_assets', where: "employee_id=? AND status='На руках'", whereArgs: [employeeId], orderBy: 'category,title'),
      d.query('revision_employees', where: 'active=1', orderBy: 'full_name'),
    ]);
    if (mounted) setState(() { assets = r[0]; employees = r[1]; loading = false; });
  }

  Future<void> _addAsset() async {
    final title = TextEditingController();
    final model = TextEditingController();
    final inv = TextEditingController();
    final serial = TextEditingController();
    final note = TextEditingController();
    const categories = ['Принтер','Монитор','Клавиатура','Мышь','Ноутбук','Колонки','Картридж','Сетевое оборудование','Комплектующие','Другое'];
    String category = categories.first;
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
      title: const Text('Добавить имущество'),
      content: SizedBox(width: 420, child: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Категория'),
          items: categories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setD(() => category = v ?? categories.first)),
        TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Наименование'), validator: (v) => v == null || v.trim().isEmpty ? 'Укажите наименование' : null),
        TextField(controller: model, decoration: const InputDecoration(labelText: 'Модель')),
        TextField(controller: inv, decoration: const InputDecoration(labelText: 'Инвентарный номер')),
        TextField(controller: serial, decoration: const InputDecoration(labelText: 'Серийный номер')),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Примечание'), maxLines: 2),
      ])))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(c, true); }, child: const Text('Добавить'))
      ],
    )));
    if (ok == true) {
      final d = await db;
      await d.transaction((t) async {
        final now = DateTime.now().toIso8601String();
        final id = await t.insert('revision_assets', {'title': title.text.trim(), 'category': category, 'model': model.text.trim(),
          'inventory_number': inv.text.trim(), 'serial_number': serial.text.trim(), 'note': note.text.trim(),
          'employee_id': employeeId, 'status': 'На руках', 'created_at': now});
        await t.insert('revision_movements', {'asset_id': id, 'action': 'Закрепление за сотрудником', 'to_employee_id': employeeId, 'date': now, 'note': ''});
      });
      await _load();
    }
    title.dispose(); model.dispose(); inv.dispose(); serial.dispose(); note.dispose();
  }

  Future<void> _move(Map<String, Object?> asset, {required bool toWarehouse}) async {
    final targets = employees.where((e) => e['id'] != employeeId).toList();
    if (!toWarehouse && targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала добавьте другого сотрудника.')));
      return;
    }
    int? target = targets.isEmpty ? null : targets.first['id'] as int;
    final note = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
      title: Text(toWarehouse ? 'Вернуть на склад' : 'Передать имущество'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${asset['category']}: ${asset['title']}'),
        if (!toWarehouse) DropdownButton<int>(isExpanded: true, value: target,
          items: targets.map((e) => DropdownMenuItem(value: e['id'] as int, child: Text(e['full_name'] as String, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setD(() => target = v)),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Основание / примечание')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Подтвердить'))
      ],
    )));
    if (ok == true) {
      final d = await db;
      final now = DateTime.now().toIso8601String();
      await d.transaction((t) async {
        await t.update('revision_assets', {'employee_id': toWarehouse ? null : target, 'status': toWarehouse ? 'На складе' : 'На руках'}, where: 'id=?', whereArgs: [asset['id']]);
        await t.insert('revision_movements', {'asset_id': asset['id'], 'action': toWarehouse ? 'Возврат на склад' : 'Передача другому сотруднику',
          'from_employee_id': employeeId, 'to_employee_id': toWarehouse ? null : target, 'date': now, 'note': note.text.trim()});
      });
      await _load();
    }
    note.dispose();
  }

  Future<void> _history(Map<String, Object?> asset) async {
    final rows = await (await db).rawQuery('''SELECT m.*, f.full_name AS from_name, t.full_name AS to_name
      FROM revision_movements m LEFT JOIN revision_employees f ON f.id=m.from_employee_id
      LEFT JOIN revision_employees t ON t.id=m.to_employee_id WHERE m.asset_id=? ORDER BY m.id DESC''', [asset['id']]);
    if (!mounted) return;
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (c) => SafeArea(child: SizedBox(
      height: MediaQuery.of(c).size.height * .65,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('История: ${asset['title']}', style: Theme.of(c).textTheme.titleLarge),
        ...rows.map((r) => ListTile(leading: const Icon(Icons.swap_horiz), title: Text(r['action'] as String),
          subtitle: Text('${_date(r['date'] as String)}\nОт: ${r['from_name'] ?? 'Склад'} → Кому: ${r['to_name'] ?? 'Склад'}${(r['note'] as String).isNotEmpty ? '\n${r['note']}' : ''}'), isThreeLine: true)),
      ]),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.employee['full_name'] as String;
    return Scaffold(appBar: AppBar(title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addAsset, icon: const Icon(Icons.add_box), label: const Text('Добавить имущество')),
      body: loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Card(margin: const EdgeInsets.all(12), child: ListTile(leading: const Icon(Icons.badge_outlined), title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${widget.employee['department']} • Закреплено позиций: ${assets.length}'))),
        Expanded(child: assets.isEmpty ? const Center(child: Text('За сотрудником пока ничего не числится.')) :
          ListView.builder(padding: const EdgeInsets.fromLTRB(12, 0, 12, 90), itemCount: assets.length, itemBuilder: (c, i) {
            final a = assets[i];
            final info = [a['model'], (a['inventory_number'] as String).isNotEmpty ? 'Инв. № ${a['inventory_number']}' : '', (a['serial_number'] as String).isNotEmpty ? 'S/N ${a['serial_number']}' : ''].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
            return Card(child: ListTile(leading: const Icon(Icons.devices_other), title: Text('${a['category']}: ${a['title']}'),
              subtitle: Text('$info${(a['note'] as String).isNotEmpty ? '\n${a['note']}' : ''}'),
              trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'move') _move(a, toWarehouse: false); if (v == 'stock') _move(a, toWarehouse: true); if (v == 'history') _history(a); },
                itemBuilder: (_) => const [PopupMenuItem(value: 'move', child: Text('Передать сотруднику')), PopupMenuItem(value: 'stock', child: Text('Вернуть на склад')), PopupMenuItem(value: 'history', child: Text('История движения'))])));
          })),
      ]));
  }
}

String _date(String value) {
  try { return DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(value).toLocal()); } catch (_) { return value; }
}
