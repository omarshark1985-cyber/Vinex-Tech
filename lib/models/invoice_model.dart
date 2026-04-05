import 'package:hive/hive.dart';
import 'invoice_item_model.dart';

part 'invoice_model.g.dart';

/// نوع الفاتورة
enum InvoiceType { sale, quote }

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

  @HiveField(8)
  late String invoiceType; // 'sale' | 'quote'

  @HiveField(9)
  double downPayment; // الدفعة الأولية (0 = لا توجد)

  Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.customerName,
    required this.invoiceDate,
    required this.items,
    this.notes = '',
    required this.totalAmount,
    this.discount = 0,
    this.invoiceType = 'sale',
    this.downPayment = 0,
  });

  /// هل هي فاتورة عرض؟
  bool get isQuote => invoiceType == 'quote';

  /// هل هي فاتورة بيع؟
  bool get isSale => invoiceType == 'sale';

  /// المبلغ المتبقي بعد الدفعة الأولية
  double get remainingAmount =>
      (totalAmount - downPayment).clamp(0, double.infinity);

  /// هل توجد دفعة أولية؟
  bool get hasDownPayment => downPayment > 0;

  /// مجموع بنود الفاتورة قبل الخصم
  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + item.totalPrice);

  /// Re-calculate total from items (للتوافق مع الكود القديم)
  double get computedTotal => subtotal;
}
