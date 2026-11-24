import 'package:flutter/material.dart';
import '../data/customer_management_repository.dart';
import 'customer_account_form.dart';

typedef CustomerRepositoryProvider = Future<CustomerManagementRepository> Function();

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key, required this.repository});
  final CustomerRepositoryProvider repository;
  @override
  State<CustomerManagementScreen> createState() => _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  late Future<List<ManagedCustomer>> customers;
  @override
  void initState() { super.initState(); reload(); }
  void reload() { customers = widget.repository().then((value) => value.list()); }

  Future<void> add(List<ManagedCustomer> existing) async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => CustomerAccountForm(
      existingNames: existing.map((c) => c.name).toList(),
      onCreate: ({required name, required userId, required password, required role, required phone, required address, required city}) async {
        final repo = await widget.repository();
        await repo.create(name: name, userId: userId, password: password, role: role, phone: phone, address: address, city: city);
      },
    )));
    if (created == true && mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customers')),
    body: FutureBuilder<List<ManagedCustomer>>(future: customers, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Customer service is unavailable. Check your connection and try again.'), const SizedBox(height: 12), OutlinedButton(onPressed: () => setState(reload), child: const Text('Retry'))])));
      final rows = snapshot.data ?? [];
      return Column(children: [Padding(padding: const EdgeInsets.all(16), child: Row(children: [Expanded(child: Text('${rows.length} registered accounts')), FilledButton.icon(onPressed: () => add(rows), icon: const Icon(Icons.person_add_outlined), label: const Text('Add customer'))])), Expanded(child: rows.isEmpty ? const Center(child: Text('No registered customers yet.')) : ListView.builder(itemCount: rows.length, itemBuilder: (context, i) { final c = rows[i]; return ListTile(title: Text(c.name), subtitle: Text('${c.loginId} · ${c.role} · ${c.status}'), trailing: c.phone.isEmpty ? null : Text(c.phone)); }))]);
    }),
  );
}
