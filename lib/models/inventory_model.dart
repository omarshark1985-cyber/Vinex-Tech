import 'package:hive/hive.dart';

part 'inventory_model.g.dart';

@HiveType(typeId: 3)
class InventoryItem extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String itemName;

  @HiveField(2)
  late String category;

  @HiveField(3)
  late double quantity;

  @HiveField(4)
  late double unitPrice;

  @HiveField(5)
  late double minStock;

  @HiveField(6)
  late String unit;

  @HiveField(7)
  late String description;

  @HiveField(8)
  late DateTime lastUpdated;

  InventoryItem({
    required this.id,
    required this.itemName,
    required this.category,
    required this.quantity,
    required this.unitPrice,
    required this.minStock,
    required this.unit,
    this.description = '',
    required this.lastUpdated,
  });

  bool get isLowStock => quantity <= minStock;
  double get totalValue => quantity * unitPrice;
}
