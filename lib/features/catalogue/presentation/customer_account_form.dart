import 'package:flutter/material.dart';

import '../domain/customer_account_rules.dart';

/// Account creation form. The caller must provide an admin-authorized server
/// operation; the password is never written into the local catalogue.
class CustomerAccountForm extends StatefulWidget {
  const CustomerAccountForm({super.key, required this.existingNames, required this.onCreate});

  final List<String> existingNames;
  final Future<void> Function({
    required String name,
    required String userId,
    required String password,
    required String role,
    required String phone,
    required String address,
    required String city,
  }) onCreate;

  @override
  State<CustomerAccountForm> createState() => _CustomerAccountFormState();
}

class _CustomerAccountFormState extends State<CustomerAccountForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final userId = TextEditingController();
  final password = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final city = TextEditingController();
  String role = 'customer';
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    for (final c in [name, userId, password, phone, address, city]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !(form.currentState?.validate() ?? false)) return;
    setState(() { busy = true; error = ''; });
    try {
      await widget.onCreate(
        name: name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
        userId: normalizeCustomerUserId(userId.text),
        password: password.text,
        role: role,
        phone: phone.text.trim(),
        address: address.text.trim(),
        city: city.text.trim(),
      );
      password.clear();
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add customer')),
    body: Form(key: form, child: ListView(padding: const EdgeInsets.all(20), children: [
      TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Customer name'), validator: (s) => validateRegularCustomerName(s ?? '', widget.existingNames)),
      TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Phone / WhatsApp'), keyboardType: TextInputType.phone),
      TextFormField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
      TextFormField(controller: city, decoration: const InputDecoration(labelText: 'City')),
      TextFormField(controller: userId, decoration: const InputDecoration(labelText: 'User ID'), autocorrect: false, validator: (s) => validateCustomerUserId(s ?? '')),
      TextFormField(controller: password, decoration: const InputDecoration(labelText: 'Password'), obscureText: true, autocorrect: false, validator: (s) => (s ?? '').length < 8 ? 'Use at least 8 characters.' : null),
      DropdownButtonFormField<String>(initialValue: role, decoration: const InputDecoration(labelText: 'Role'), items: const [DropdownMenuItem(value: 'customer', child: Text('Customer')), DropdownMenuItem(value: 'owner', child: Text('Owner')), DropdownMenuItem(value: 'admin', child: Text('Admin'))], onChanged: busy ? null : (v) => setState(() => role = v ?? 'customer')),
      if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 20),
      FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Creating…' : 'Create customer')),
    ])),
  );
}
