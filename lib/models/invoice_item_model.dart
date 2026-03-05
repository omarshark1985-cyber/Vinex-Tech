import 'package:hive/hive.dart';

part 'invoice_item_model.g.dart';

/// A single line item inside an invoice
@HiveType(typeId: 4)
class InvoiceItem extends HiveObject {
  @HiveField(0)
  late int sequence; // رقم التسلسل

  @HiveField(1)
  late String itemName; // اسم المادة

  @HiveField(2)
  late double quantity; // الكمية

  @HiveField(3)
  late double unitPrice; // سعر الوحدة

  @HiveField(4)
  late double totalPrice; // المبلغ = الكمية × السعر

  InvoiceItem({
    required this.sequence,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });
}
