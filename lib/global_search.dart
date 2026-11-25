import 'package:flutter/material.dart';
import 'cartridges.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});
  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final controller = TextEditingController();
  List<Map<String, Object?>> results = [];
  bool searching = false;

  @override
  void dispose() { controller.dispose(); super.dispose(); }

  Future<void> search(String value) async {
    final q = value.trim();
    if (q.isEmpty) { setState(() { results = []; searching = false; }); return; }
    setState(() => searching = true);
    final db = await CartridgeDatabase.instance.database;
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final existing = tables.map((r) => r['name'] as String).toSet();
    final found = <Map<String, Object?>>[];
    Future<void> scan(String table, String label, List<String> columns, String titleColumn, String subtitleColumn) async {
      if (!existing.contains(table)) return;
      final info = await db.rawQuery('PRAGMA table_info($table)');
      final available = info.map((r) => r['name'] as String).toSet();
      final valid = columns.where(available.contains).toList();
      if (valid.isEmpty || !available.contains(titleColumn)) return;
      final where = valid.map((c) => 'CAST($c AS TEXT) LIKE ?').join(' OR ');
      final rows = await db.query(table, where: where, whereArgs: List.filled(valid.length, '%$q%'), limit: 30);
      for (final row in rows) {
        found.add({'section': label, 'title': (row[titleColumn] ?? label).toString(),
          'subtitle': available.contains(subtitleColumn) ? (row[subtitleColumn] ?? '').toString() : '',
          'id': row['id']});
      }
    }
    try {
      await scan('cartridges', 'Картриджи', ['code','model','printer_model','department','sender_name','status'], 'model', 'status');
      await scan('it_equipment', 'Оборудование', ['title','category','model','inventory_number','serial_number','location','status'], 'title', 'location');
      await scan('service_requests', 'Заявки', ['description','department','requester','room','equipment','inventory_number','executor','status'], 'description', 'status');
      await scan('revision_employees', 'Сотрудники', ['full_name','department','position'], 'full_name', 'department');
      await scan('revision_assets', 'Имущество', ['title','category','model','inventory_number','serial_number','note'], 'title', 'inventory_number');
      await scan('it_consumables', 'Расходники', ['name','category','location','note'], 'name', 'location');
    } finally {
      if (mounted) setState(() { results = found; searching = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Поиск по приложению')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(
        controller: controller, autofocus: true, onChanged: search,
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'ФИО, инвентарный номер, модель…',
          border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { controller.clear(); search(''); })),
      )),
      Expanded(child: searching ? const Center(child: CircularProgressIndicator()) :
        results.isEmpty ? Center(child: Text(controller.text.trim().isEmpty ? 'Введите запрос для поиска по разделам' : 'Ничего не найдено'))
        : ListView.builder(itemCount: results.length, itemBuilder: (context, index) {
          final r = results[index];
          return ListTile(leading: const Icon(Icons.search), title: Text(r['title'] as String),
            subtitle: Text('${r['section']} · ${r['subtitle']}'));
        })),
    ]),
  );
}
