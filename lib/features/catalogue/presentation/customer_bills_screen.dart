import 'package:flutter/material.dart';
import '../data/cloud_catalogue_repository.dart';
import '../domain/customer_bill.dart';

class CustomerBillsScreen extends StatefulWidget {
  const CustomerBillsScreen(
      {super.key, required this.repository, this.title = 'My Bills'});
  final Future<CloudCatalogueRepository?> Function() repository;
  final String title;
  @override
  State<CustomerBillsScreen> createState() => _CustomerBillsScreenState();
}

class _CustomerBillsScreenState extends State<CustomerBillsScreen> {
  late Future<List<CustomerBill>> _bills;
  @override
  void initState() {
    super.initState();
    _bills = _load();
  }

  Future<List<CustomerBill>> _load() async {
    final cloud = await widget.repository();
    if (cloud == null) {
      throw StateError('Connect to the internet and sign in to view bills.');
    }
    return cloud.pullBills();
  }

  void _open(CustomerBill bill) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text('Bill ${bill.billNumber}'),
            content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Order: ${bill.orderNumber}'),
                      Text('Customer: ${bill.customerName}'),
                      Text('Date: ${bill.createdAt}'),
                      const Divider(),
                      for (final item in bill.items)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text((item['productName'] ?? '').toString()),
                            subtitle: Text([
                              item['size'],
                              item['finish'],
                              item['brand']
                            ]
                                .where(
                                    (v) => v != null && v.toString().isNotEmpty)
                                .join(' · ')),
                            trailing: Text(
                                '${item['quantity']} × Rs. ${item['unitPrice']}\nRs. ${item['lineTotal']}',
                                textAlign: TextAlign.right)),
                      Text(
                          'Additional discount: ${bill.payload['additionalDiscountPercent'] ?? 0}%'),
                      Text('Total: Rs. ${bill.total}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                    ]))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'))
            ],
          ));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title), actions: [
          IconButton(
              onPressed: () => setState(() => _bills = _load()),
              icon: const Icon(Icons.refresh))
        ]),
        body: FutureBuilder<List<CustomerBill>>(
            future: _bills,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: Text('Could not load bills: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final bills = snapshot.data!;
              if (bills.isEmpty) {
                return const Center(child: Text('No bills yet.'));
              }
              return ListView.builder(
                  itemCount: bills.length,
                  itemBuilder: (context, index) {
                    final bill = bills[index];
                    return ListTile(
                        title: Text(bill.billNumber),
                        subtitle:
                            Text('${bill.orderNumber} · ${bill.createdAt}'),
                        trailing: Text('Rs. ${bill.total}'),
                        onTap: () => _open(bill));
                  });
            }),
      );
}
