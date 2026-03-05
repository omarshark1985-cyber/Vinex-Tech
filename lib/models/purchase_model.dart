import 'package:hive/hive.dart';

part 'purchase_model.g.dart';

@HiveType(typeId: 2)
class Purchase extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String itemName;

  @HiveField(2)
  late double quantity;

  @HiveField(3)
  late double unitPrice;

  @HiveField(4)
  late double totalPrice;

  @HiveField(5)
  late String supplierName;

  @HiveField(6)
  late DateTime date;

  @HiveField(7)
  late String notes;

  Purchase({
    required this.id,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.supplierName,
    required this.date,
    this.notes = '',
  });
}
