int _lastGeneratedProductId = 0;

String _newProductId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  _lastGeneratedProductId =
      now > _lastGeneratedProductId ? now : _lastGeneratedProductId + 1;
  return _lastGeneratedProductId.toString();
}

const kInternalProductCodePrefix = 'CR-PROD-';

String _formatInternalProductCode(int number) {
  return '$kInternalProductCodePrefix${number.toString().padLeft(6, '0')}';
}

String normalizeInternalProductCode(String value) {
  return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

bool _publishedFromJson(Map<String, Object?> json,
    {required bool defaultValue}) {
  final value = json['isPublished'] ??
      json['is_published'] ??
      json['published'] ??
      json['visible_to_customer'];
  if (value == null) return defaultValue;
  if (value is bool) return value;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes' || text == 'published') {
    return true;
  }
  if (text == 'false' || text == '0' || text == 'no' || text == 'hidden') {
    return false;
  }
  return defaultValue;
}

String _normalPublishKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

List<String> _stringListFromJson(Object? value) {
  if (value == null) return const [];
  if (value is List) {
    return _cleanUniqueStrings(value.map((item) => item.toString()));
  }
  return _cleanUniqueStrings(
      value.toString().split(RegExp(r'[,;\n]')).map((item) => item.trim()));
}

List<String> _cleanUniqueStrings(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) continue;
    if (result
        .any((item) => _normalPublishKey(item) == _normalPublishKey(clean))) {
      continue;
    }
    result.add(clean);
  }
  return result;
}

class ProductDraft {
  ProductDraft({
    String? id,
    required this.name,
    this.sku = '',
    this.internalProductCode = '',
    required this.category,
    required this.subcategory,
    this.brand = '',
    this.sizeSpec = '',
    this.finishColor = '',
    this.sellingPrice = '0.00',
    this.imagePath = '',
    this.notes = '',
    this.keywords = const [],
    this.imagePaths = const [],
    this.imageFinishTags = const {},
    this.imageRevision = 0,
    this.variations = const [],
    this.isPublished = false,
    this.isComingSoon = false,
    this.isArchived = false,
    this.archivedAt = '',
  }) : id = id ?? _newProductId();

  final String id;
  final String name;
  final String sku;
  final String internalProductCode;
  final String category;
  final String subcategory;
  final String brand;
  final String sizeSpec;
  final String finishColor;
  final String sellingPrice;
  final String imagePath;
  final String notes;
  final List<String> keywords;
  final List<String> imagePaths;
  final Map<String, String> imageFinishTags;
  final int imageRevision;
  final List<VariationDraft> variations;
  final bool isPublished;
  final bool isComingSoon;
  final bool isArchived;
  final String archivedAt;

  factory ProductDraft.fromJson(Map<String, Object?> json) {
    final rawId = (json['id'] ?? '').toString().trim();
    return ProductDraft(
      id: rawId.isEmpty ? null : rawId,
      name: (json['name'] ?? '').toString(),
      sku: (json['sku'] ?? '').toString(),
      internalProductCode: (json['internalProductCode'] ??
              json['internal_product_code'] ??
              json['crimsonProductCode'] ??
              json['crimson_product_code'] ??
              '')
          .toString(),
      category: (json['category'] ?? '').toString(),
      subcategory: (json['subcategory'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      sizeSpec: (json['sizeSpec'] ?? '').toString(),
      finishColor: (json['finishColor'] ?? '').toString(),
      sellingPrice: (json['sellingPrice'] ?? '0.00').toString(),
      imagePath: (json['imagePath'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      keywords: _stringListFromJson(json['keywords'] ?? json['tags']),
      imagePaths: ((json['imagePaths'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList(),
      imageFinishTags: ((json['imageFinishTags'] as Map?) ??
              (json['image_finish_tags'] as Map?) ??
              const {})
          .map((key, value) => MapEntry(key.toString(), value.toString())),
      imageRevision:
          int.tryParse((json['imageRevision'] ?? '0').toString()) ?? 0,
      isPublished: _publishedFromJson(json, defaultValue: true),
      isComingSoon: json['isComingSoon'] == true,
      variations: ((json['variations'] as List?) ?? const [])
          .whereType<Map>()
          .map((value) =>
              VariationDraft.fromJson(Map<String, Object?>.from(value)))
          .toList(),
      isArchived: json['isArchived'] == true,
      archivedAt: (json['archivedAt'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'sku': sku,
      'internalProductCode': internalProductCode,
      'category': category,
      'subcategory': subcategory,
      'brand': brand,
      'sizeSpec': sizeSpec,
      'finishColor': finishColor,
      'sellingPrice': sellingPrice,
      'imagePath': imagePath,
      'notes': notes,
      'keywords': keywords,
      'imagePaths': imagePaths,
      'imageFinishTags': imageFinishTags,
      'imageRevision': imageRevision,
      'variations': variations.map((variation) => variation.toJson()).toList(),
      'isPublished': isPublished,
      'isComingSoon': isComingSoon,
      'isArchived': isArchived,
      'archivedAt': archivedAt,
    };
  }

  ProductDraft copyWith({
    String? id,
    String? name,
    String? sku,
    String? internalProductCode,
    String? category,
    String? subcategory,
    String? brand,
    String? sizeSpec,
    String? finishColor,
    String? sellingPrice,
    String? imagePath,
    String? notes,
    List<String>? keywords,
    List<String>? imagePaths,
    Map<String, String>? imageFinishTags,
    int? imageRevision,
    List<VariationDraft>? variations,
    bool? isPublished,
    bool? isComingSoon,
    bool? isArchived,
    String? archivedAt,
  }) {
    return ProductDraft(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      internalProductCode: internalProductCode ?? this.internalProductCode,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      brand: brand ?? this.brand,
      sizeSpec: sizeSpec ?? this.sizeSpec,
      finishColor: finishColor ?? this.finishColor,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      imagePath: imagePath ?? this.imagePath,
      notes: notes ?? this.notes,
      keywords: keywords ?? this.keywords,
      imagePaths: imagePaths ?? this.imagePaths,
      imageFinishTags: imageFinishTags ?? this.imageFinishTags,
      imageRevision: imageRevision ?? this.imageRevision,
      variations: variations ?? this.variations,
      isPublished: isPublished ?? this.isPublished,
      isComingSoon: isComingSoon ?? this.isComingSoon,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
    );
  }
}

class VariationDraft {
  const VariationDraft({
    this.size = '',
    this.finish = '',
    this.breadth = '',
    this.length = '',
    this.height = '',
    this.thickness = '',
    required this.price,
    this.sku = '',
    this.notes = '',
  });

  final String size;
  final String finish;
  final String breadth;
  final String length;
  final String height;
  final String thickness;
  final String price;
  final String sku;
  final String notes;

  factory VariationDraft.fromJson(Map<String, Object?> json) {
    return VariationDraft(
      size: (json['size'] ?? '').toString(),
      finish: (json['finish'] ?? '').toString(),
      breadth: (json['breadth'] ?? json['width'] ?? '').toString(),
      length: (json['length'] ?? '').toString(),
      height: (json['height'] ?? '').toString(),
      thickness: (json['thickness'] ?? '').toString(),
      price: (json['price'] ?? '0.00').toString(),
      sku: (json['sku'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'size': size,
      'finish': finish,
      'breadth': breadth,
      'length': length,
      'height': height,
      'thickness': thickness,
      'price': price,
      'sku': sku,
      'notes': notes,
    };
  }
}

class StockItemDraft {
  StockItemDraft({
    String? id,
    required this.displayProductId,
    required this.displayProductName,
    this.stockSku = '',
    this.brand = '',
    this.size = '',
    this.finish = '',
    this.category = '',
    this.subcategory = '',
    this.material = '',
    this.isActive = true,
    this.createdAt = '',
    this.updatedAt = '',
  }) : id = id ?? _newProductId();

  final String id;
  final String displayProductId;
  final String displayProductName;
  final String stockSku;
  final String brand;
  final String size;
  final String finish;
  final String category;
  final String subcategory;
  final String material;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  factory StockItemDraft.fromJson(Map<String, Object?> json) {
    final rawId = (json['id'] ?? '').toString().trim();
    return StockItemDraft(
      id: rawId.isEmpty ? null : rawId,
      displayProductId: (json['displayProductId'] ??
              json['display_product_id'] ??
              json['productId'] ??
              json['product_id'] ??
              '')
          .toString(),
      displayProductName: (json['displayProductName'] ??
              json['display_product_name'] ??
              json['productName'] ??
              json['product_name'] ??
              '')
          .toString(),
      stockSku: (json['stockSku'] ?? json['stock_sku'] ?? json['sku'] ?? '')
          .toString(),
      brand: (json['brand'] ?? '').toString(),
      size: (json['size'] ?? '').toString(),
      finish: (json['finish'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      subcategory: (json['subcategory'] ?? '').toString(),
      material: (json['material'] ?? '').toString(),
      isActive: json['isActive'] != false && json['is_active'] != false,
      createdAt: (json['createdAt'] ?? json['created_at'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? json['updated_at'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'displayProductId': displayProductId,
        'displayProductName': displayProductName,
        'stockSku': stockSku,
        'brand': brand,
        'size': size,
        'finish': finish,
        'category': category,
        'subcategory': subcategory,
        'material': material,
        'isActive': isActive,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  StockItemDraft copyWith({
    String? id,
    String? displayProductId,
    String? displayProductName,
    String? stockSku,
    String? brand,
    String? size,
    String? finish,
    String? category,
    String? subcategory,
    String? material,
    bool? isActive,
    String? createdAt,
    String? updatedAt,
  }) {
    return StockItemDraft(
      id: id ?? this.id,
      displayProductId: displayProductId ?? this.displayProductId,
      displayProductName: displayProductName ?? this.displayProductName,
      stockSku: stockSku ?? this.stockSku,
      brand: brand ?? this.brand,
      size: size ?? this.size,
      finish: finish ?? this.finish,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      material: material ?? this.material,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum StockVoucherType {
  inward,
  outward,
  adjustment,
  transfer;

  static StockVoucherType fromText(String value) {
    final clean = value.trim().toLowerCase();
    return StockVoucherType.values.firstWhere(
      (type) => type.name == clean,
      orElse: () => StockVoucherType.inward,
    );
  }

  String get label => switch (this) {
        StockVoucherType.inward => 'Inward',
        StockVoucherType.outward => 'Outward',
        StockVoucherType.adjustment => 'Adjustment',
        StockVoucherType.transfer => 'Transfer',
      };
}

class StockVoucherItemDraft {
  const StockVoucherItemDraft({
    this.stockItemId = '',
    required this.productId,
    required this.productName,
    this.stockSku = '',
    this.brand = '',
    this.size = '',
    this.finish = '',
    this.godown = '',
    required this.quantity,
    this.notes = '',
  });

  final String stockItemId;
  final String productId;
  final String productName;
  final String stockSku;
  final String brand;
  final String size;
  final String finish;
  final String godown;
  final double quantity;
  final String notes;

  factory StockVoucherItemDraft.fromJson(Map<String, Object?> json) {
    return StockVoucherItemDraft(
      stockItemId:
          (json['stockItemId'] ?? json['stock_item_id'] ?? '').toString(),
      productId: (json['productId'] ?? json['product_id'] ?? '').toString(),
      productName:
          (json['productName'] ?? json['product_name'] ?? '').toString(),
      stockSku: (json['stockSku'] ?? json['stock_sku'] ?? json['sku'] ?? '')
          .toString(),
      brand: (json['brand'] ?? '').toString(),
      size: (json['size'] ?? '').toString(),
      finish: (json['finish'] ?? '').toString(),
      godown: (json['godown'] ?? '').toString(),
      quantity: double.tryParse((json['quantity'] ?? '0').toString()) ?? 0,
      notes: (json['notes'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() => {
        'stockItemId': stockItemId,
        'productId': productId,
        'productName': productName,
        'stockSku': stockSku,
        'brand': brand,
        'size': size,
        'finish': finish,
        'godown': godown,
        'quantity': quantity,
        'notes': notes,
      };
}

class StockVoucherDraft {
  StockVoucherDraft({
    String? id,
    required this.type,
    required this.voucherNumber,
    required this.date,
    this.partyName = '',
    this.reference = '',
    this.notes = '',
    this.items = const [],
    this.createdAt = '',
  }) : id = id ?? _newProductId();

  final String id;
  final StockVoucherType type;
  final String voucherNumber;
  final String date;
  final String partyName;
  final String reference;
  final String notes;
  final List<StockVoucherItemDraft> items;
  final String createdAt;

  factory StockVoucherDraft.fromJson(Map<String, Object?> json) {
    return StockVoucherDraft(
      id: (json['id'] ?? '').toString().trim().isEmpty
          ? null
          : (json['id'] ?? '').toString(),
      type: StockVoucherType.fromText((json['type'] ?? '').toString()),
      voucherNumber:
          (json['voucherNumber'] ?? json['voucher_number'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      partyName: (json['partyName'] ?? json['party_name'] ?? '').toString(),
      reference: (json['reference'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((value) =>
              StockVoucherItemDraft.fromJson(Map<String, Object?>.from(value)))
          .toList(),
      createdAt: (json['createdAt'] ?? json['created_at'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'voucherNumber': voucherNumber,
        'date': date,
        'partyName': partyName,
        'reference': reference,
        'notes': notes,
        'items': items.map((item) => item.toJson()).toList(),
        'createdAt': createdAt,
      };

  double get signedQuantity {
    final total = items.fold<double>(0, (sum, item) => sum + item.quantity);
    return switch (type) {
      StockVoucherType.inward => total,
      StockVoucherType.outward => -total,
      StockVoucherType.adjustment => total,
      StockVoucherType.transfer => 0,
    };
  }
}

enum CustomerOrderStatus {
  draft,
  placed,
  confirmed,
  packed,
  dispatched,
  delivered,
  cancelled,
  rejected;

  static CustomerOrderStatus fromText(String value) {
    final clean = value.trim().toLowerCase();
    return CustomerOrderStatus.values.firstWhere(
      (status) => status.name == clean,
      orElse: () => CustomerOrderStatus.draft,
    );
  }

  String get label => switch (this) {
        CustomerOrderStatus.draft => 'Draft',
        CustomerOrderStatus.placed => 'Pending Approval',
        CustomerOrderStatus.confirmed => 'Approved',
        CustomerOrderStatus.packed => 'Packed',
        CustomerOrderStatus.dispatched => 'Dispatched',
        CustomerOrderStatus.delivered => 'Delivered',
        CustomerOrderStatus.cancelled => 'Cancelled',
        CustomerOrderStatus.rejected => 'Rejected',
      };
}

double _orderDiscountPercent(String value) {
  final parsed = double.tryParse(value.replaceAll('%', '').trim()) ?? 0;
  if (parsed <= 0) return 0;
  return parsed.clamp(0, 100).toDouble();
}

class CustomerOrderItemDraft {
  const CustomerOrderItemDraft({
    required this.productId,
    required this.productName,
    this.stockItemId = '',
    this.stockSku = '',
    this.brand = '',
    this.size = '',
    this.finish = '',
    this.imagePath = '',
    required this.quantity,
    required this.unitPrice,
    this.defaultDiscount = '',
    this.revisedDiscount = '',
    this.finalDiscount = '',
    this.approvedQuantity = 0,
    this.dispatchedQuantity = 0,
    this.notes = '',
  });

  final String productId;
  final String productName;
  final String stockItemId;
  final String stockSku;
  final String brand;
  final String size;
  final String finish;
  final String imagePath;
  final double quantity;
  final double unitPrice;
  final String defaultDiscount;
  final String revisedDiscount;
  final String finalDiscount;
  final double approvedQuantity;
  final double dispatchedQuantity;
  final String notes;

  factory CustomerOrderItemDraft.fromJson(Map<String, Object?> json) {
    return CustomerOrderItemDraft(
      productId: (json['productId'] ?? json['product_id'] ?? '').toString(),
      productName:
          (json['productName'] ?? json['product_name'] ?? '').toString(),
      stockItemId:
          (json['stockItemId'] ?? json['stock_item_id'] ?? '').toString(),
      stockSku: (json['stockSku'] ?? json['stock_sku'] ?? json['sku'] ?? '')
          .toString(),
      brand: (json['brand'] ?? '').toString(),
      size: (json['size'] ?? '').toString(),
      finish: (json['finish'] ?? '').toString(),
      imagePath: (json['imagePath'] ?? json['image_path'] ?? '').toString(),
      quantity: double.tryParse((json['quantity'] ?? '0').toString()) ?? 0,
      unitPrice: double.tryParse(
              (json['unitPrice'] ?? json['unit_price'] ?? '0').toString()) ??
          0,
      defaultDiscount:
          (json['defaultDiscount'] ?? json['default_discount'] ?? '')
              .toString(),
      revisedDiscount:
          (json['revisedDiscount'] ?? json['revised_discount'] ?? '')
              .toString(),
      finalDiscount:
          (json['finalDiscount'] ?? json['final_discount'] ?? '').toString(),
      approvedQuantity: double.tryParse(
              (json['approvedQuantity'] ?? json['approved_quantity'] ?? '0')
                  .toString()) ??
          0,
      dispatchedQuantity: double.tryParse(
              (json['dispatchedQuantity'] ?? json['dispatched_quantity'] ?? '0')
                  .toString()) ??
          0,
      notes: (json['notes'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() => {
        'productId': productId,
        'productName': productName,
        'stockItemId': stockItemId,
        'stockSku': stockSku,
        'brand': brand,
        'size': size,
        'finish': finish,
        'imagePath': imagePath,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'defaultDiscount': defaultDiscount,
        'revisedDiscount': revisedDiscount,
        'finalDiscount': effectiveDiscountText,
        'approvedQuantity': approvedQuantity,
        'dispatchedQuantity': dispatchedQuantity,
        'notes': notes,
      };

  String get effectiveDiscountText {
    if (finalDiscount.trim().isNotEmpty) return finalDiscount.trim();
    if (revisedDiscount.trim().isNotEmpty) return revisedDiscount.trim();
    return defaultDiscount.trim();
  }

  double get discountMultiplier =>
      1 - (_orderDiscountPercent(effectiveDiscountText) / 100);

  double get baseLineTotal => quantity * unitPrice;
  double get lineDiscountAmount => baseLineTotal - lineTotal;
  double get discountedUnitPrice => unitPrice * discountMultiplier;
  double get lineTotal => quantity * unitPrice * discountMultiplier;
  double get effectiveApprovedQuantity =>
      approvedQuantity > 0 ? approvedQuantity : 0;
  double get approvedLineTotal =>
      effectiveApprovedQuantity * unitPrice * discountMultiplier;

  CustomerOrderItemDraft copyWith({
    String? productId,
    String? productName,
    String? stockItemId,
    String? stockSku,
    String? brand,
    String? size,
    String? finish,
    String? imagePath,
    double? quantity,
    double? unitPrice,
    String? defaultDiscount,
    String? revisedDiscount,
    String? finalDiscount,
    double? approvedQuantity,
    double? dispatchedQuantity,
    String? notes,
  }) {
    return CustomerOrderItemDraft(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      stockItemId: stockItemId ?? this.stockItemId,
      stockSku: stockSku ?? this.stockSku,
      brand: brand ?? this.brand,
      size: size ?? this.size,
      finish: finish ?? this.finish,
      imagePath: imagePath ?? this.imagePath,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      defaultDiscount: defaultDiscount ?? this.defaultDiscount,
      revisedDiscount: revisedDiscount ?? this.revisedDiscount,
      finalDiscount: finalDiscount ?? this.finalDiscount,
      approvedQuantity: approvedQuantity ?? this.approvedQuantity,
      dispatchedQuantity: dispatchedQuantity ?? this.dispatchedQuantity,
      notes: notes ?? this.notes,
    );
  }
}

class CustomerOrderDraft {
  CustomerOrderDraft({
    String? id,
    required this.orderNumber,
    this.customerAccountId = '',
    this.customerType = 'legacy',
    this.customerName = '',
    this.customerPhone = '',
    this.customerNotes = '',
    this.salesman = '',
    this.approvedBy = '',
    this.dispatchDetails = '',
    this.additionalDiscountPercent = 0,
    this.status = CustomerOrderStatus.draft,
    this.items = const [],
    this.createdAt = '',
    this.updatedAt = '',
  }) : id = id ?? _newProductId();

  final String id;
  final String orderNumber;
  /// Empty for legacy and retail orders. Regular orders use an auth user ID.
  final String customerAccountId;
  /// 'regular', 'retail', or 'legacy' for pre-existing unassigned orders.
  final String customerType;
  final String customerName;
  final String customerPhone;
  final String customerNotes;
  final String salesman;
  final String approvedBy;
  final String dispatchDetails;
  final double additionalDiscountPercent;
  final CustomerOrderStatus status;
  final List<CustomerOrderItemDraft> items;
  final String createdAt;
  final String updatedAt;

  factory CustomerOrderDraft.fromJson(Map<String, Object?> json) {
    return CustomerOrderDraft(
      id: (json['id'] ?? '').toString().trim().isEmpty
          ? null
          : (json['id'] ?? '').toString(),
      orderNumber:
          (json['orderNumber'] ?? json['order_number'] ?? '').toString(),
      customerAccountId:
          (json['customerAccountId'] ?? json['customer_account_id'] ?? '').toString(),
      customerType: (json['customerType'] ?? json['customer_type'] ?? 'legacy').toString(),
      customerName:
          (json['customerName'] ?? json['customer_name'] ?? '').toString(),
      customerPhone:
          (json['customerPhone'] ?? json['customer_phone'] ?? '').toString(),
      customerNotes:
          (json['customerNotes'] ?? json['customer_notes'] ?? '').toString(),
      salesman: (json['salesman'] ?? '').toString(),
      approvedBy: (json['approvedBy'] ?? json['approved_by'] ?? '').toString(),
      dispatchDetails:
          (json['dispatchDetails'] ?? json['dispatch_details'] ?? '')
              .toString(),
      additionalDiscountPercent: _orderDiscountPercent(
        (json['additionalDiscountPercent'] ??
                json['additional_discount_percent'] ??
                '0')
            .toString(),
      ),
      status: CustomerOrderStatus.fromText((json['status'] ?? '').toString()),
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((value) =>
              CustomerOrderItemDraft.fromJson(Map<String, Object?>.from(value)))
          .toList(),
      createdAt: (json['createdAt'] ?? json['created_at'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? json['updated_at'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'orderNumber': orderNumber,
        'customerAccountId': customerAccountId,
        'customerType': customerType,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerNotes': customerNotes,
        'salesman': salesman,
        'approvedBy': approvedBy,
        'dispatchDetails': dispatchDetails,
        'additionalDiscountPercent': additionalDiscountPercent,
        'status': status.name,
        'items': items.map((item) => item.toJson()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  CustomerOrderDraft copyWith({
    String? orderNumber,
    String? customerAccountId,
    String? customerType,
    String? customerName,
    String? customerPhone,
    String? customerNotes,
    String? salesman,
    String? approvedBy,
    String? dispatchDetails,
    double? additionalDiscountPercent,
    CustomerOrderStatus? status,
    List<CustomerOrderItemDraft>? items,
    String? createdAt,
    String? updatedAt,
  }) {
    return CustomerOrderDraft(
      id: id,
      orderNumber: orderNumber ?? this.orderNumber,
      customerAccountId: customerAccountId ?? this.customerAccountId,
      customerType: customerType ?? this.customerType,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerNotes: customerNotes ?? this.customerNotes,
      salesman: salesman ?? this.salesman,
      approvedBy: approvedBy ?? this.approvedBy,
      dispatchDetails: dispatchDetails ?? this.dispatchDetails,
      additionalDiscountPercent:
          additionalDiscountPercent ?? this.additionalDiscountPercent,
      status: status ?? this.status,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  double get baseSubtotal =>
      items.fold<double>(0, (sum, item) => sum + item.baseLineTotal);
  double get lineDiscountTotal => baseSubtotal - discountedSubtotal;
  double get discountedSubtotal =>
      items.fold<double>(0, (sum, item) => sum + item.lineTotal);
  double get additionalDiscountAmount =>
      discountedSubtotal * additionalDiscountPercent / 100;
  double get total => discountedSubtotal - additionalDiscountAmount;
  double get approvedSubtotal =>
      items.fold<double>(0, (sum, item) => sum + item.approvedLineTotal);
  double get approvedTotal =>
      approvedSubtotal * (1 - additionalDiscountPercent / 100);
}

class VariationMatrix {
  const VariationMatrix({
    required this.sizes,
    required this.finishes,
    required this.prices,
    required this.extraLines,
  });

  final List<String> sizes;
  final List<String> finishes;
  final Map<String, String> prices;
  final List<String> extraLines;

  String key(String finish, String size) => '$finish\u001f$size';
}

class ImportParseResult {
  const ImportParseResult({
    required this.products,
    required this.errors,
  });

  final List<ProductDraft> products;
  final List<String> errors;
}

class BulkPasteImportResult {
  const BulkPasteImportResult({
    required this.products,
    required this.categories,
    required this.errors,
    this.format = BulkPasteImportFormat.unknown,
  });

  final List<ProductDraft> products;
  final List<CategoryDraft> categories;
  final List<String> errors;
  final BulkPasteImportFormat format;
}

enum BulkPasteImportFormat {
  unknown,
  longRows,
  widePriceMatrix,
}

class CategoryDraft {
  const CategoryDraft({
    required this.name,
    this.subcategories = const [],
    this.keywords = const [],
    this.imagePath = '',
    this.isPublished = false,
    this.subcategoryImages = const {},
    this.subcategoryPublished = const {},
    this.discountPercent = 0,
  });

  final String name;
  final List<String> subcategories;
  final List<String> keywords;
  final String imagePath;
  final bool isPublished;
  final Map<String, String> subcategoryImages;
  final Map<String, bool> subcategoryPublished;
  final double discountPercent;

  factory CategoryDraft.fromJson(Map<String, Object?> json) {
    final subcategories = ((json['subcategories'] as List?) ?? const [])
        .map((value) => value.toString())
        .toList();
    final hasPublishedMap = json['subcategoryPublished'] is Map ||
        json['subcategory_published'] is Map;
    final publishedMap = ((json['subcategoryPublished'] as Map?) ??
            (json['subcategory_published'] as Map?) ??
            const {})
        .map((key, value) => MapEntry(key.toString(), value == true));
    return CategoryDraft(
      name: (json['name'] ?? '').toString(),
      subcategories: subcategories,
      keywords: _stringListFromJson(json['keywords'] ?? json['tags']),
      imagePath: (json['imagePath'] ?? '').toString(),
      isPublished: _publishedFromJson(json, defaultValue: true),
      subcategoryImages: ((json['subcategoryImages'] as Map?) ?? const {})
          .map((key, value) => MapEntry(key.toString(), value.toString())),
      subcategoryPublished: hasPublishedMap
          ? publishedMap
          : {for (final subcategory in subcategories) subcategory: true},
      discountPercent: _orderDiscountPercent(
        (json['discountPercent'] ?? json['discount_percent'] ?? '0').toString(),
      ),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'subcategories': subcategories,
      'keywords': keywords,
      'imagePath': imagePath,
      'isPublished': isPublished,
      'subcategoryImages': subcategoryImages,
      'subcategoryPublished': subcategoryPublished,
      'discountPercent': discountPercent,
    };
  }

  CategoryDraft copyWith({
    String? name,
    List<String>? subcategories,
    List<String>? keywords,
    String? imagePath,
    bool? isPublished,
    Map<String, String>? subcategoryImages,
    Map<String, bool>? subcategoryPublished,
    double? discountPercent,
  }) {
    return CategoryDraft(
      name: name ?? this.name,
      subcategories: subcategories ?? this.subcategories,
      keywords: keywords ?? this.keywords,
      imagePath: imagePath ?? this.imagePath,
      isPublished: isPublished ?? this.isPublished,
      subcategoryImages: subcategoryImages ?? this.subcategoryImages,
      subcategoryPublished: subcategoryPublished ?? this.subcategoryPublished,
      discountPercent: discountPercent ?? this.discountPercent,
    );
  }

  bool isSubcategoryPublished(String name) {
    final target = _normalPublishKey(name);
    for (final entry in subcategoryPublished.entries) {
      if (_normalPublishKey(entry.key) == target) return entry.value;
    }
    return isPublished;
  }
}

double categoryDiscountFor(
    List<CategoryDraft> categories, String categoryName) {
  final target = categoryName.trim().toLowerCase();
  if (target.isEmpty) return 0;
  for (final category in categories) {
    if (category.name.trim().toLowerCase() == target) {
      return category.discountPercent;
    }
  }
  return 0;
}

class SearchTerminologyDraft {
  const SearchTerminologyDraft({
    required this.canonical,
    this.aliases = const [],
  });

  final String canonical;
  final List<String> aliases;

  factory SearchTerminologyDraft.fromJson(Map<String, Object?> json) {
    return SearchTerminologyDraft(
      canonical: (json['canonical'] ?? json['term'] ?? '').toString().trim(),
      aliases: ((json['aliases'] as List?) ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }

  Map<String, Object?> toJson() => {
        'canonical': canonical,
        'aliases': aliases,
      };

  SearchTerminologyDraft copyWith({
    String? canonical,
    List<String>? aliases,
  }) {
    return SearchTerminologyDraft(
      canonical: canonical ?? this.canonical,
      aliases: aliases ?? this.aliases,
    );
  }
}

const builtInSearchTerminology = <SearchTerminologyDraft>[
  SearchTerminologyDraft(
    canonical: 'Rose Gold',
    aliases: ['RG', 'R/G', 'RoseGold', 'Rose-Gold'],
  ),
  SearchTerminologyDraft(
    canonical: 'Matt Black',
    aliases: ['MB', 'M/B', 'Mat Black', 'Matte Black', 'MattBlack'],
  ),
  SearchTerminologyDraft(
    canonical: 'Stainless Steel',
    aliases: ['SS', 'S/S', 'Stainless', 'StainlessSteel'],
  ),
  SearchTerminologyDraft(
    canonical: 'Chrome',
    aliases: ['CP', 'C/P', 'Chrome Plated'],
  ),
  SearchTerminologyDraft(
    canonical: 'Gold Yellow',
    aliases: ['GY', 'G/Y'],
  ),
  SearchTerminologyDraft(
    canonical: 'Matt',
    aliases: ['Mat', 'Matte'],
  ),
  SearchTerminologyDraft(
    canonical: 'Handle',
    aliases: ['Handles'],
  ),
  SearchTerminologyDraft(
    canonical: 'Knob',
    aliases: ['Knobs'],
  ),
];

class PhotoInboxImage {
  const PhotoInboxImage({required this.path, this.finish = ''});

  final String path;
  final String finish;

  factory PhotoInboxImage.fromJson(Map<String, Object?> json) =>
      PhotoInboxImage(
        path: (json['path'] ?? '').toString(),
        finish: (json['finish'] ?? '').toString(),
      );

  Map<String, Object?> toJson() => {'path': path, 'finish': finish};

  PhotoInboxImage copyWith({String? path, String? finish}) =>
      PhotoInboxImage(path: path ?? this.path, finish: finish ?? this.finish);
}

class PhotoInboxDraft {
  PhotoInboxDraft({
    String? id,
    this.images = const [],
    this.name = '',
    this.category = '',
    this.subcategory = '',
    this.brand = '',
    this.notes = '',
    this.convertedProductId = '',
    this.mergedIntoDraftId = '',
  }) : id = id ?? _newProductId();

  final String id;
  final List<PhotoInboxImage> images;
  final String name;
  final String category;
  final String subcategory;
  final String brand;
  final String notes;
  final String convertedProductId;
  final String mergedIntoDraftId;

  bool get isConverted => convertedProductId.trim().isNotEmpty;
  bool get isActive => !isConverted && mergedIntoDraftId.trim().isEmpty;

  factory PhotoInboxDraft.fromJson(Map<String, Object?> json) =>
      PhotoInboxDraft(
        id: (json['id'] ?? '').toString().trim().isEmpty
            ? null
            : (json['id'] ?? '').toString(),
        images: ((json['images'] as List?) ?? const [])
            .whereType<Map>()
            .map((value) =>
                PhotoInboxImage.fromJson(Map<String, Object?>.from(value)))
            .toList(),
        name: (json['name'] ?? '').toString(),
        category: (json['category'] ?? '').toString(),
        subcategory: (json['subcategory'] ?? '').toString(),
        brand: (json['brand'] ?? '').toString(),
        notes: (json['notes'] ?? '').toString(),
        convertedProductId: (json['convertedProductId'] ?? '').toString(),
        mergedIntoDraftId: (json['mergedIntoDraftId'] ?? '').toString(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'images': images.map((image) => image.toJson()).toList(),
        'name': name,
        'category': category,
        'subcategory': subcategory,
        'brand': brand,
        'notes': notes,
        'convertedProductId': convertedProductId,
        'mergedIntoDraftId': mergedIntoDraftId,
      };

  PhotoInboxDraft copyWith({
    List<PhotoInboxImage>? images,
    String? name,
    String? category,
    String? subcategory,
    String? brand,
    String? notes,
    String? convertedProductId,
    String? mergedIntoDraftId,
  }) =>
      PhotoInboxDraft(
        id: id,
        images: images ?? this.images,
        name: name ?? this.name,
        category: category ?? this.category,
        subcategory: subcategory ?? this.subcategory,
        brand: brand ?? this.brand,
        notes: notes ?? this.notes,
        convertedProductId: convertedProductId ?? this.convertedProductId,
        mergedIntoDraftId: mergedIntoDraftId ?? this.mergedIntoDraftId,
      );
}

class CatalogueState {
  const CatalogueState({
    this.products = const [],
    this.photoInbox = const [],
    this.categories = const [],
    this.brands = const [],
    this.brandImages = const {},
    this.bannerImagePaths = const [],
    this.stockVouchers = const [],
    this.stockItems = const [],
    this.customerOrders = const [],
    this.customerStockStatuses = const {},
    this.searchTerminology = const [],
    this.resetGeneration = '',
    this.updatedAt = '',
  });

  final List<ProductDraft> products;
  final List<PhotoInboxDraft> photoInbox;
  final List<CategoryDraft> categories;
  final List<String> brands;
  final Map<String, String> brandImages;
  final List<String> bannerImagePaths;
  final List<StockVoucherDraft> stockVouchers;
  final List<StockItemDraft> stockItems;
  final List<CustomerOrderDraft> customerOrders;
  /// Customer-safe status strings only; no inventory quantities are stored here.
  final Map<String, String> customerStockStatuses;
  final List<SearchTerminologyDraft> searchTerminology;
  final String resetGeneration;
  final String updatedAt;

  factory CatalogueState.fromJson(Map<String, Object?> json) {
    final products = ((json['products'] as List?) ?? const [])
        .whereType<Map>()
        .map((value) => ProductDraft.fromJson(Map<String, Object?>.from(value)))
        .toList();
    return CatalogueState(
      products: ensureProductIdentity(products),
      photoInbox: ((json['photoInbox'] as List?) ?? const [])
          .whereType<Map>()
          .map((value) =>
              PhotoInboxDraft.fromJson(Map<String, Object?>.from(value)))
          .toList(),
      categories: ((json['categories'] as List?) ?? const [])
          .whereType<Map>()
          .map((value) =>
              CategoryDraft.fromJson(Map<String, Object?>.from(value)))
          .toList(),
      brands: ((json['brands'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList(),
      brandImages: ((json['brandImages'] as Map?) ?? const {})
          .map((key, value) => MapEntry(key.toString(), value.toString())),
      bannerImagePaths: ((json['bannerImagePaths'] as List?) ?? const [])
          .map((value) => value.toString())
          .where((value) => value.trim().isNotEmpty)
          .toList(),
      stockVouchers: ((json['stockVouchers'] as List?) ??
              (json['stock_vouchers'] as List?) ??
              const [])
          .whereType<Map>()
          .map((value) =>
              StockVoucherDraft.fromJson(Map<String, Object?>.from(value)))
          .toList(),
      stockItems: ((json['stockItems'] as List?) ??
              (json['stock_items'] as List?) ??
              const [])
          .whereType<Map>()
          .map((value) =>
              StockItemDraft.fromJson(Map<String, Object?>.from(value)))
          .toList(),
      customerOrders: ((json['customerOrders'] as List?) ??
              (json['customer_orders'] as List?) ??
              const [])
          .whereType<Map>()
          .map((value) =>
              CustomerOrderDraft.fromJson(Map<String, Object?>.from(value)))
          .toList(),
      customerStockStatuses: ((json['customerStockStatuses'] as Map?) ?? const {})
          .map((key, value) => MapEntry(key.toString(), value.toString())),
      searchTerminology: ((json['searchTerminology'] as List?) ??
              (json['search_terminology'] as List?) ??
              const [])
          .whereType<Map>()
          .map((value) => SearchTerminologyDraft.fromJson(
                Map<String, Object?>.from(value),
              ))
          .where((entry) => entry.canonical.trim().isNotEmpty)
          .toList(),
      resetGeneration: (json['resetGeneration'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'products': products.map((product) => product.toJson()).toList(),
      'photoInbox': photoInbox.map((draft) => draft.toJson()).toList(),
      'categories': categories.map((category) => category.toJson()).toList(),
      'brands': brands,
      'brandImages': brandImages,
      'bannerImagePaths': bannerImagePaths,
      'stockVouchers':
          stockVouchers.map((voucher) => voucher.toJson()).toList(),
      'stockItems': stockItems.map((item) => item.toJson()).toList(),
      'customerOrders': customerOrders.map((order) => order.toJson()).toList(),
      if (customerStockStatuses.isNotEmpty) 'customerStockStatuses': customerStockStatuses,
      'searchTerminology':
          searchTerminology.map((entry) => entry.toJson()).toList(),
      'resetGeneration': resetGeneration,
      'updatedAt': updatedAt,
    };
  }

  CatalogueState copyWith({
    List<ProductDraft>? products,
    List<PhotoInboxDraft>? photoInbox,
    List<CategoryDraft>? categories,
    List<String>? brands,
    Map<String, String>? brandImages,
    List<String>? bannerImagePaths,
    List<StockVoucherDraft>? stockVouchers,
    List<StockItemDraft>? stockItems,
    List<CustomerOrderDraft>? customerOrders,
    Map<String, String>? customerStockStatuses,
    List<SearchTerminologyDraft>? searchTerminology,
    String? resetGeneration,
    String? updatedAt,
  }) {
    return CatalogueState(
      products: products ?? this.products,
      photoInbox: photoInbox ?? this.photoInbox,
      categories: categories ?? this.categories,
      brands: brands ?? this.brands,
      brandImages: brandImages ?? this.brandImages,
      bannerImagePaths: bannerImagePaths ?? this.bannerImagePaths,
      stockVouchers: stockVouchers ?? this.stockVouchers,
      stockItems: stockItems ?? this.stockItems,
      customerOrders: customerOrders ?? this.customerOrders,
      customerStockStatuses: customerStockStatuses ?? this.customerStockStatuses,
      searchTerminology: searchTerminology ?? this.searchTerminology,
      resetGeneration: resetGeneration ?? this.resetGeneration,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

List<ProductDraft> ensureProductIdentity(List<ProductDraft> products) {
  return ensureInternalProductCodes(ensureUniqueProductIds(products));
}

List<ProductDraft> ensureInternalProductCodes(List<ProductDraft> products) {
  var nextNumber = _highestInternalProductNumber(products) + 1;
  final seen = <String>{};
  final result = <ProductDraft>[];

  for (final product in products) {
    var code = normalizeInternalProductCode(product.internalProductCode);
    if (code.isEmpty || seen.contains(code)) {
      do {
        code = _formatInternalProductCode(nextNumber++);
      } while (seen.contains(code));
    }
    seen.add(code);
    result.add(product.copyWith(internalProductCode: code));
  }

  return result;
}

int _highestInternalProductNumber(List<ProductDraft> products) {
  var highest = 0;
  for (final product in products) {
    final code = normalizeInternalProductCode(product.internalProductCode);
    if (!code.startsWith(kInternalProductCodePrefix)) continue;
    final suffix = code.substring(kInternalProductCodePrefix.length);
    final number = int.tryParse(suffix);
    if (number != null && number > highest) highest = number;
  }
  return highest;
}

List<ProductDraft> ensureUniqueProductIds(List<ProductDraft> products) {
  final seen = <String>{};
  final collisionCounts = <String, int>{};
  final result = <ProductDraft>[];

  for (final product in products) {
    final originalId = product.id.trim();
    if (originalId.isNotEmpty && seen.add(originalId)) {
      result.add(product);
      continue;
    }

    final base = originalId.isEmpty ? 'product' : originalId;
    var occurrence = (collisionCounts[base] ?? 0) + 1;
    var replacement = _repairedProductId(product, base, occurrence);
    while (!seen.add(replacement)) {
      occurrence++;
      replacement = _repairedProductId(product, base, occurrence);
    }
    collisionCounts[base] = occurrence;
    result.add(product.copyWith(id: replacement));
  }

  return result;
}

String _repairedProductId(
  ProductDraft product,
  String base,
  int occurrence,
) {
  final identity = [
    product.name,
    product.sku,
    product.category,
    product.subcategory,
    occurrence.toString(),
  ].map((value) => value.trim().toLowerCase()).join('|');
  return '$base-${_stableIdHash(identity)}';
}

String _stableIdHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
