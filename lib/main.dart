import 'cartridges.dart';
import 'revision.dart';
import 'requests.dart';
import 'equipment.dart';
import 'knowledge_base.dart';
import 'private_notes.dart';
import 'app_info.dart';
import 'tools_pages.dart';
import 'global_search.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ITMasterApp());
}

class ITMasterApp extends StatelessWidget {
  const ITMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IT-Мастер',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B9A),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF65B5E8),
          brightness: Brightness.dark,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _organizationKey = 'organization_name';
  static const _defaultOrganization = 'ГБУЗ «МРЦРМБ» ЛНР';

  int selectedIndex = 0;
  String organizationName = '';
  bool _loadingOrganization = true;

  @override
  void initState() {
    super.initState();
    _loadOrganization();
  }

  Future<void> _loadOrganization() async {
    final preferences = await SharedPreferences.getInstance();
    final savedName = preferences.getString(_organizationKey)?.trim() ?? '';
    if (!mounted) return;
    setState(() {
      organizationName = savedName;
      _loadingOrganization = false;
    });
    if (savedName.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showOrganizationSetup();
      });
    }
  }

  Future<void> _saveOrganization(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_organizationKey, normalized);
    if (mounted) setState(() => organizationName = normalized);
  }

  Future<void> _showOrganizationSetup() async {
    final controller = TextEditingController(text: organizationName);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Настройка приложения'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Укажите название вашей организации. Оно будет отображаться на главном экране.'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Название организации',
                hintText: 'Например, ГБУЗ «МРЦРМБ» ЛНР',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) Navigator.pop(dialogContext, value.trim());
              },
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      await _saveOrganization(result);
    } else if (mounted && organizationName.isEmpty) {
      await _showOrganizationSetup();
    }
  }

  List<Widget> get pages => [
    DashboardPage(onNavigate: (index) => setState(() => selectedIndex = index), organizationName: organizationName.isEmpty ? _defaultOrganization : organizationName),
    const CartridgesPage(),
    const RequestsPage(),
    const EquipmentPage(),
    const MorePage(),
    const RevisionPage(),
  ];

  final List<String> titles = [
    'Главная',
    'Картриджи',
    'Заявки',
    'Оборудование',
    'Ещё',
    'Ревизия',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          selectedIndex == 0 ? 'IT-Мастер' : titles[selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Поиск по приложению',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalSearchPage())),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Настройки',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    organizationName: organizationName.isEmpty ? _defaultOrganization : organizationName,
                    onOrganizationChanged: _saveOrganization,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loadingOrganization
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: selectedIndex,
              children: pages,
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() => selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.print_outlined),
            selectedIcon: Icon(Icons.print_rounded),
            label: 'Картриджи',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: 'Заявки',
          ),
          NavigationDestination(
            icon: Icon(Icons.computer_outlined),
            selectedIcon: Icon(Icons.computer_rounded),
            label: 'Техника',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Ещё',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_ind_outlined),
            selectedIcon: Icon(Icons.assignment_ind),
            label: 'Ревизия',
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  final String organizationName;
  const DashboardPage({
    super.key,
    required this.onNavigate,
    this.organizationName = 'ГБУЗ «МРЦРМБ» ЛНР',
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF176B9A),
                Color(0xFF24436D),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.computer_rounded,
                color: Colors.white,
                size: 38,
              ),
              SizedBox(height: 18),
              Text(
                'Добро пожаловать!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Ваш персональный рабочий помощник',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 14),
              Text(
                organizationName,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Рабочие разделы',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: DashboardCard(title: 'Картриджи', subtitle: 'Приём и возврат', icon: Icons.print_rounded, color: const Color(0xFF247CB5), onTap: () => onNavigate(1))),
          const SizedBox(width: 12),
          Expanded(child: DashboardCard(title: 'Заявки', subtitle: 'Неисправности', icon: Icons.assignment_rounded, color: const Color(0xFF168B73), onTap: () => onNavigate(2))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DashboardCard(title: 'Оборудование', subtitle: 'Учёт техники', icon: Icons.devices_rounded, color: const Color(0xFF805CB4), onTap: () => onNavigate(3))),
          const SizedBox(width: 12),
          Expanded(child: DashboardCard(title: 'Расходники', subtitle: 'Запасы и детали', icon: Icons.inventory_2_rounded, color: const Color(0xFFC18435), onTap: () => onNavigate(4))),
        ]),
        const SizedBox(height: 12),
        DashboardCard(title: 'Ревизия', subtitle: 'Имущество сотрудников', icon: Icons.assignment_ind_rounded, color: const Color(0xFF287A62), onTap: () => onNavigate(5)),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 30,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'IT-Мастер готов к работе',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Добавляйте заявки, оборудование и ведите учёт картриджей.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DashboardCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const DashboardCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withAlpha(30),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 15),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const PlaceholderPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 76,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            const Chip(label: Text('Раздел в разработке')),
          ],
        ),
      ),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Widget _tile(BuildContext context, {required IconData icon, required String title, required String subtitle, required Widget page}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _open(context, page),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _tile(context, icon: Icons.menu_book_outlined, title: 'Инструкции и частые ошибки',
          subtitle: 'Canon, Pantum, Windows, Office, RJ45 и диагностика', page: const KnowledgeBasePage()),
        _tile(context, icon: Icons.lock_outline, title: 'Личные заметки',
          subtitle: 'Защищённые заметки на этом телефоне', page: const PrivateNotesPage()),
        _tile(context, icon: Icons.inventory_2_outlined, title: 'Расходные материалы',
          subtitle: 'Остатки, поступление, выдача и история', page: const ConsumablesPage()),
        _tile(context, icon: Icons.network_check_rounded, title: 'Проверка сети',
          subtitle: 'DNS, TCP-порты и локальные IP-адреса', page: const NetworkToolsPage()),
        _tile(context, icon: Icons.bar_chart_rounded, title: 'Отчёты',
          subtitle: 'Статистика и экспорт в CSV', page: const ReportsPage()),
        _tile(context, icon: Icons.backup_outlined, title: 'Резервная копия',
          subtitle: 'Создание и восстановление базы данных', page: const BackupPage()),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  final String organizationName;
  final Future<void> Function(String) onOrganizationChanged;

  const SettingsPage({
    super.key,
    required this.organizationName,
    required this.onOrganizationChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _organizationController;

  @override
  void initState() {
    super.initState();
    _organizationController = TextEditingController(text: widget.organizationName);
  }

  @override
  void dispose() {
    _organizationController.dispose();
    super.dispose();
  }

  Future<void> _saveOrganization() async {
    final value = _organizationController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название организации')),
      );
      return;
    }
    await widget.onOrganizationChanged(value);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Название организации сохранено')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Организация',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _organizationController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Название организации',
              hintText: 'Введите название организации',
              prefixIcon: Icon(Icons.business_outlined),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saveOrganization(),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saveOrganization,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Сохранить название'),
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Оформление'),
            subtitle: Text('Автоматически по настройкам телефона'),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Резервное копирование'),
            subtitle: const Text('Создание и восстановление копии базы'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupPage())),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('О программе'),
            subtitle: Text('IT-Мастер · Версия $appVersion'),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'IT-Мастер · ГБУЗ «МРЦРМБ» ЛНР\nДанные приложения хранятся локально на устройстве. '
                'Перед переносом на другой телефон создавайте резервную копию.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
