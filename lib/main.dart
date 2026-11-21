
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  await AppDb.instance.init();
  runApp(const MistfitApp());
}

final supabase = Supabase.instance.client;
final money = NumberFormat.currency(
  locale: 'en_PK', symbol: 'Rs. ', decimalDigits: 0,
);

class AppDb {
  AppDb._();
  static final instance = AppDb._();
  Database? db;

  Future<void> init() async {
    final path = p.join(await getDatabasesPath(), 'mistfit_business.db');
    db = await openDatabase(path, version: 1, onCreate: (d, v) async {
      await d.execute('''CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, sku TEXT, size TEXT, color TEXT,
        cost REAL NOT NULL, price REAL NOT NULL,
        stock INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)''');
      await d.execute('''CREATE TABLE sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER,
        product_name TEXT NOT NULL, qty INTEGER NOT NULL,
        unit_price REAL NOT NULL, unit_cost REAL NOT NULL,
        total REAL NOT NULL, date TEXT NOT NULL)''');
      await d.execute('''CREATE TABLE expenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL, category TEXT NOT NULL,
        amount REAL NOT NULL, date TEXT NOT NULL)''');
    });
  }

  Future<List<Map<String, Object?>>> rows(String table) =>
      db!.query(table, orderBy: 'id DESC');

  Future<int> add(String table, Map<String, Object?> values) =>
      db!.insert(table, values);

  Future<int> update(String table, int id, Map<String, Object?> values) =>
      db!.update(table, values, where: 'id=?', whereArgs: [id]);

  Future<int> delete(String table, int id) =>
      db!.delete(table, where: 'id=?', whereArgs: [id]);

  Future<void> recordSale(Map<String, Object?> product, int qty) async {
    await db!.transaction((txn) async {
      final id = product['id'] as int;
      final stock = product['stock'] as int;
      if (qty <= 0 || qty > stock) {
        throw Exception('Stock available nahi hai.');
      }
      final price = (product['price'] as num).toDouble();
      final cost = (product['cost'] as num).toDouble();
      await txn.insert('sales', {
        'product_id': id,
        'product_name': product['name'],
        'qty': qty,
        'unit_price': price,
        'unit_cost': cost,
        'total': price * qty,
        'date': DateTime.now().toIso8601String(),
      });
      await txn.update('products', {'stock': stock - qty},
          where: 'id=?', whereArgs: [id]);
    });
  }

  Future<Map<String, double>> totals() async {
    final s = await db!.rawQuery(
      'SELECT COALESCE(SUM(total),0) revenue, '
      'COALESCE(SUM((unit_price-unit_cost)*qty),0) gross FROM sales');
    final e = await db!.rawQuery(
      'SELECT COALESCE(SUM(amount),0) expenses FROM expenses');
    final revenue = (s.first['revenue'] as num).toDouble();
    final gross = (s.first['gross'] as num).toDouble();
    final expenses = (e.first['expenses'] as num).toDouble();
    return {
      'revenue': revenue,
      'gross': gross,
      'expenses': expenses,
      'net': gross - expenses,
    };
  }
}

class MistfitApp extends StatelessWidget {
  const MistfitApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MISTFIT Business OS',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0D12),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFD5B36A),
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF11151D),
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF151A24),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF171D28),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          return supabase.auth.currentSession == null
              ? const LoginPage()
              : const HomePage();
        },
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool hidePassword = true;
  String? error;

  Future<void> login() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Email aur password enter karein.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await supabase.auth.signInWithPassword(
        email: email.text.trim(),
        password: password.text,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Internet check karein.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.storefront,
                  size: 65, color: Color(0xFFD5B36A)),
              const SizedBox(height: 18),
              const Text('MISTFIT',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  )),
              const SizedBox(height: 6),
              const Text('BUSINESS OS',
                  style: TextStyle(
                    color: Color(0xFFD5B36A),
                    letterSpacing: 3,
                  )),
              const SizedBox(height: 38),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: password,
                obscureText: hidePassword,
                onSubmitted: (_) => login(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => hidePassword = !hidePassword),
                    icon: Icon(hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 14),
                Text(error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: loading ? null : login,
                  child: loading
                      ? const CircularProgressIndicator()
                      : const Text('LOGIN'),
                ),
              ),
              const SizedBox(height: 20),
              const Text('MISTFIT team members only',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  int refresh = 0;

  void reload() => setState(() => refresh++);

  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(key: ValueKey('d$refresh'), onChanged: reload),
      ProductsPage(key: ValueKey('p$refresh'), onChanged: reload),
      SalesPage(key: ValueKey('s$refresh'), onChanged: reload),
      ExpensesPage(key: ValueKey('e$refresh'), onChanged: reload),
      const AnalystPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('MISTFIT / BUSINESS OS',
            style: TextStyle(fontSize: 15, letterSpacing: 1.2)),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => supabase.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF11151D),
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Products'),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale),
            label: 'Sales'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Expenses'),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome),
            label: 'AI Analyst'),
        ],
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  final VoidCallback onChanged;
  const Dashboard({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: Future.wait([
      AppDb.instance.totals(),
      AppDb.instance.rows('products'),
      AppDb.instance.rows('sales'),
    ]),
    builder: (context, snap) {
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final t = snap.data![0] as Map<String, double>;
      final products = snap.data![1] as List<Map<String, Object?>>;
      final sales = snap.data![2] as List<Map<String, Object?>>;
      final low = products.where((x) => (x['stock'] as int) <= 5).length;

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('BUSINESS OVERVIEW',
              style: TextStyle(
                color: Color(0xFFD5B36A),
                letterSpacing: 2,
                fontSize: 12)),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.55,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              Metric('Revenue', money.format(t['revenue']),
                  Icons.trending_up),
              Metric('Gross profit', money.format(t['gross']),
                  Icons.account_balance_wallet),
              Metric('Expenses', money.format(t['expenses']),
                  Icons.payments_outlined),
              Metric('Net profit*', money.format(t['net']),
                  Icons.insights),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BUSINESS SNAPSHOT',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  InfoLine('Products listed', '${products.length}'),
                  InfoLine('Sales recorded', '${sales.length}'),
                  InfoLine('Low-stock products', '$low'),
                  const Divider(height: 22),
                  const Text(
                    '*Net profit = gross product profit minus recorded expenses.',
                    style: TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await showProductForm(context);
              onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add your first product'),
          ),
        ],
      );
    },
  );
}

class Metric extends StatelessWidget {
  final String title, value;
  final IconData icon;
  const Metric(this.title, this.value, this.icon, {super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: const Color(0xFFD5B36A), size: 20),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 17)),
          Text(title,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      ),
    ),
  );
}

class InfoLine extends StatelessWidget {
  final String a, b;
  const InfoLine(this.a, this.b, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(a, style: const TextStyle(color: Colors.white70)),
        Text(b, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

class ProductsPage extends StatelessWidget {
  final VoidCallback onChanged;
  const ProductsPage({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        await showProductForm(context);
        onChanged();
      },
      icon: const Icon(Icons.add),
      label: const Text('Add product'),
    ),
    body: FutureBuilder(
      future: AppDb.instance.rows('products'),
      builder: (c, s) {
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = s.data!;
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No products yet',
            body: 'Apni T-shirts aur stock yahan add karein.');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (c, i) {
            final x = items[i];
            return Card(
              child: ListTile(
                title: Text('${x['name']}'),
                subtitle: Text(
                  'SKU: ${x['sku'] ?? '-'} • '
                  '${x['size'] ?? 'No size'} / ${x['color'] ?? 'No color'}\n'
                  'Cost ${money.format(x['cost'])} | '
                  'Price ${money.format(x['price'])}'),
                isThreeLine: true,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${x['stock']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                    const Text('stock',
                        style: TextStyle(
                          fontSize: 10, color: Colors.white60)),
                  ],
                ),
                onTap: () async {
                  await showProductForm(context, existing: x);
                  onChanged();
                },
              ),
            );
          },
        );
      },
    ),
  );
}

Future<void> showProductForm(
  BuildContext context, {Map<String, Object?>? existing}
) async {
  final name = TextEditingController(text: existing?['name'] as String? ?? '');
  final sku = TextEditingController(text: existing?['sku'] as String? ?? '');
  final size = TextEditingController(text: existing?['size'] as String? ?? '');
  final color = TextEditingController(text: existing?['color'] as String? ?? '');
  final cost = TextEditingController(
      text: existing == null ? '' : '${existing['cost']}');
  final price = TextEditingController(
      text: existing == null ? '' : '${existing['price']}');
  final stock = TextEditingController(
      text: existing == null ? '0' : '${existing['stock']}');

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Add product' : 'Edit product'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          field(name, 'Product name'),
          field(sku, 'SKU / code'),
          field(size, 'Size (S, M, L, XL)'),
          field(color, 'Color'),
          field(cost, 'Unit cost (Rs.)', numeric: true),
          field(price, 'Selling price (Rs.)', numeric: true),
          field(stock, 'Opening stock', numeric: true),
        ]),
      ),
      actions: [
        if (existing != null)
          TextButton(
            onPressed: () async {
              await AppDb.instance.delete('products', existing['id'] as int);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete')),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final n = double.tryParse(cost.text);
            final pr = double.tryParse(price.text);
            final st = int.tryParse(stock.text);
            if (name.text.trim().isEmpty ||
                n == null || pr == null || st == null ||
                n < 0 || pr < 0 || st < 0) return;

            final values = {
              'name': name.text.trim(),
              'sku': sku.text.trim(),
              'size': size.text.trim(),
              'color': color.text.trim(),
              'cost': n,
              'price': pr,
              'stock': st,
              'created_at': DateTime.now().toIso8601String(),
            };

            if (existing == null) {
              await AppDb.instance.add('products', values);
            } else {
              await AppDb.instance.update(
                  'products', existing['id'] as int, values);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Save')),
      ],
    ),
  );
}

Widget field(TextEditingController c, String label, {bool numeric = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      ),
    );

class SalesPage extends StatelessWidget {
  final VoidCallback onChanged;
  const SalesPage({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        await showSaleForm(context);
        onChanged();
      },
      icon: const Icon(Icons.add_shopping_cart),
      label: const Text('Record sale'),
    ),
    body: FutureBuilder(
      future: AppDb.instance.rows('sales'),
      builder: (c, s) {
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.point_of_sale,
            title: 'No sales recorded',
            body: 'Sale record karne par stock automatically kam hoga.');
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: s.data!.map((x) => Card(
            child: ListTile(
              title: Text('${x['product_name']} × ${x['qty']}'),
              subtitle: Text(DateFormat('dd MMM yyyy, hh:mm a').format(
                  DateTime.parse(x['date'] as String))),
              trailing: Text(money.format(x['total']),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          )).toList(),
        );
      },
    ),
  );
}

Future<void> showSaleForm(BuildContext context) async {
  final products = await AppDb.instance.rows('products');
  if (!context.mounted) return;
  if (products.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pehle product add karein.')));
    return;
  }

  int selected = products.first['id'] as int;
  final qty = TextEditingController(text: '1');

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Record sale'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            value: selected,
            isExpanded: true,
            items: products.map((x) => DropdownMenuItem(
              value: x['id'] as int,
              child: Text('${x['name']} (stock ${x['stock']})',
                  overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) {
              if (v != null) set(() => selected = v);
            },
          ),
          const SizedBox(height: 12),
          field(qty, 'Quantity', numeric: true),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final product = products.firstWhere((x) => x['id'] == selected);
              final q = int.tryParse(qty.text) ?? 0;
              try {
                await AppDb.instance.recordSale(product, q);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(
                    e.toString().replaceAll('Exception: ', ''))));
              }
            },
            child: const Text('Save sale')),
        ],
      ),
    ),
  );
}

class ExpensesPage extends StatelessWidget {
  final VoidCallback onChanged;
  const ExpensesPage({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        await showExpenseForm(context);
        onChanged();
      },
      icon: const Icon(Icons.add),
      label: const Text('Add expense'),
    ),
    body: FutureBuilder(
      future: AppDb.instance.rows('expenses'),
      builder: (c, s) {
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.data!.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long,
            title: 'No expenses recorded',
            body: 'Rent, packaging, marketing aur doosre kharchay add karein.');
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: s.data!.map((x) => Card(
            child: ListTile(
              title: Text('${x['title']}'),
              subtitle: Text(
                '${x['category']} • ${DateFormat('dd MMM yyyy').format(
                    DateTime.parse(x['date'] as String))}'),
              trailing: Text(money.format(x['amount'])),
            ),
          )).toList(),
        );
      },
    ),
  );
}

Future<void> showExpenseForm(BuildContext context) async {
  final title = TextEditingController();
  final amount = TextEditingController();
  String category = 'Operations';

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Add expense'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          field(title, 'Expense title'),
          field(amount, 'Amount (Rs.)', numeric: true),
          DropdownButtonFormField<String>(
            value: category,
            items: [
              'Operations', 'Packaging', 'Marketing', 'Rent',
              'Salary', 'Delivery', 'Other'
            ].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
            onChanged: (v) {
              if (v != null) set(() => category = v);
            },
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final a = double.tryParse(amount.text);
              if (title.text.trim().isEmpty || a == null || a <= 0) return;
              await AppDb.instance.add('expenses', {
                'title': title.text.trim(),
                'category': category,
                'amount': a,
                'date': DateTime.now().toIso8601String(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save')),
        ],
      ),
    ),
  );
}

class AnalystPage extends StatelessWidget {
  const AnalystPage({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: Future.wait([
      AppDb.instance.totals(),
      AppDb.instance.rows('products'),
      AppDb.instance.rows('sales'),
    ]),
    builder: (c, s) {
      if (!s.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final t = s.data![0] as Map<String, double>;
      final products = s.data![1] as List<Map<String, Object?>>;
      final sales = s.data![2] as List<Map<String, Object?>>;
      final low = products.where((x) => (x['stock'] as int) <= 5).toList();
      final loss = products.where(
        (x) => (x['price'] as num) <= (x['cost'] as num)).toList();

      final insights = <Widget>[];

      if (products.isEmpty) {
        insights.add(const Insight(
          icon: Icons.info_outline,
          title: 'Data needed',
          body: 'Products add karne ke baad analysis hoga.',
          warning: false));
      }
      if (low.isNotEmpty) {
        insights.add(Insight(
          icon: Icons.warning_amber,
          title: 'Low stock alert',
          body: '${low.length} product(s) ka stock 5 ya us se kam hai.',
          warning: true));
      }
      if (loss.isNotEmpty) {
        insights.add(Insight(
          icon: Icons.trending_down,
          title: 'Pricing alert',
          body: '${loss.length} product(s) ki selling price cost se zyada nahi.',
          warning: true));
      }
      if (sales.isEmpty) {
        insights.add(const Insight(
          icon: Icons.bar_chart,
          title: 'Sales trend unavailable',
          body: 'Sales records add karna zaroori hai.',
          warning: false));
      }
      if (sales.isNotEmpty && t['net']! < 0) {
        insights.add(const Insight(
          icon: Icons.error_outline,
          title: 'Recorded costs exceed gross profit',
          body: 'Recorded expenses aur pricing review karein.',
          warning: true));
      }
      if (insights.isEmpty) {
        insights.add(const Insight(
          icon: Icons.check_circle_outline,
          title: 'No rule-based warning found',
          body: 'Configured checks ke mutabiq warning nahi mili.',
          warning: false));
      }

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('MISTFIT AI ANALYST',
              style: TextStyle(
                color: Color(0xFFD5B36A),
                letterSpacing: 2,
                fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Offline rule-based business checks',
              style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 14),
          ...insights,
          const SizedBox(height: 12),
          const Text('Analysis limits',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Text(
            'Ye basic offline analysis hai, trained generative AI nahi. '
            'Suggestions saved records aur built-in rules par based hain.',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      );
    },
  );
}

class Insight extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final bool warning;

  const Insight({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.warning,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: warning
              ? Colors.orangeAccent : const Color(0xFFD5B36A)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(body,
                    style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, body;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: const Color(0xFFD5B36A)),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60)),
        ],
      ),
    ),
  );
}
