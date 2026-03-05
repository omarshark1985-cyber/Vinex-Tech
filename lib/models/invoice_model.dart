import 'package:hive/hive.dart';
import 'invoice_item_model.dart';

part 'invoice_model.g.dart';

/// The invoice header – one invoice can have many InvoiceItem lines
@HiveType(typeId: 5)
class Invoice extends HiveObject {
  @HiveField(0)
  late String id; // UUID

  @HiveField(1)
  late int invoiceNumber; // رقم الفاتورة (تسلسل تلقائي)

  @HiveField(2)
  late String customerName; // اسم الزبون

  @HiveField(3)
  late DateTime invoiceDate; // تاريخ الفاتورة

  @HiveField(4)
  late List<InvoiceItem> items; // بنود الفاتورة

  @HiveField(5)
  late String notes; // الملاحظات

  @HiveField(6)
  late double totalAmount; // المبلغ الإجمالي بعد الخصم

  @HiveField(7)
  late double discount; // قيمة الخصم (مبلغ ثابت)

  Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.customerName,
    required this.invoiceDate,
    required this.items,
    this.notes = '',
    required this.totalAmount,
    this.discount = 0,
  });

  /// مجموع بنود الفاتورة قبل الخصم
  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + item.totalPrice);

  /// Re-calculate total from items (للتوافق مع الكود القديم)
  double get computedTotal => subtotal;
}
