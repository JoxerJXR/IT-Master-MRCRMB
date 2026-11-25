import 'cartridges.dart';

import 'package:flutter/material.dart';

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
  int selectedIndex = 0;

  List<Widget> get pages => [
    DashboardPage(onNavigate: (index) => setState(() => selectedIndex = index)),
    const CartridgesPage(),
    PlaceholderPage(
      title: 'Заявки',
      subtitle: 'Учёт неисправностей и выполненных работ',
      icon: Icons.assignment_rounded,
    ),
    PlaceholderPage(
      title: 'Оборудование',
      subtitle: 'Компьютеры, принтеры и оргтехника',
      icon: Icons.computer_rounded,
    ),
    MorePage(),
  ];

  final List<String> titles = [
    'Главная',
    'Картриджи',
    'Заявки',
    'Оборудование',
    'Ещё',
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
            tooltip: 'Настройки',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsPage(),
                ),
              );
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
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
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const DashboardPage({super.key, required this.onNavigate});

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
          child: const Column(
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
                'ГБУЗ «МРЦРМБ» ЛНР',
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        MenuTile(
          icon: Icons.inventory_2_outlined,
          title: 'Расходные материалы',
          subtitle: 'Тонер, бумага и комплектующие',
        ),
        MenuTile(
          icon: Icons.menu_book_outlined,
          title: 'Справочник',
          subtitle: 'Ошибки принтеров и инструкции',
        ),
        MenuTile(
          icon: Icons.network_check_rounded,
          title: 'Проверка сети',
          subtitle: 'IP-адреса и доступность устройств',
        ),
        MenuTile(
          icon: Icons.bar_chart_rounded,
          title: 'Отчёты',
          subtitle: 'История и статистика',
        ),
        MenuTile(
          icon: Icons.backup_outlined,
          title: 'Резервная копия',
          subtitle: 'Сохранение и восстановление данных',
        ),
      ],
    );
  }
}

class MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const MenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: 28,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Оформление'),
            subtitle: Text('Автоматически по настройкам телефона'),
          ),
          ListTile(
            leading: Icon(Icons.backup_outlined),
            title: Text('Резервное копирование'),
            subtitle: Text('Локальное сохранение данных'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('О программе'),
            subtitle: Text('IT-Мастер · Версия 1.0.0'),
          ),
        ],
      ),
    );
  }
}

