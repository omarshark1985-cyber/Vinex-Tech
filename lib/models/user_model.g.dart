// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppUserAdapter extends TypeAdapter<AppUser> {
  @override
  final int typeId = 0;

  @override
  AppUser read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppUser(
      username: fields[0] as String,
      password: fields[1] as String,
      role: fields[2] as String,
      displayName: fields[15] as String,
      canViewSales: fields[3] as bool,
      canViewPurchases: fields[4] as bool,
      canViewInventory: fields[5] as bool,
      canViewReports: fields[6] as bool,
      canAddSales: fields[7] as bool,
      canDeleteSales: fields[8] as bool,
      canAddPurchases: fields[9] as bool,
      canDeletePurchases: fields[10] as bool,
      canAddInventory: fields[11] as bool,
      canEditInventory: fields[12] as bool,
      canDeleteInventory: fields[13] as bool,
      canExportReports: fields[14] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, AppUser obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.username)
      ..writeByte(1)
      ..write(obj.password)
      ..writeByte(2)
      ..write(obj.role)
      ..writeByte(3)
      ..write(obj.canViewSales)
      ..writeByte(4)
      ..write(obj.canViewPurchases)
      ..writeByte(5)
      ..write(obj.canViewInventory)
      ..writeByte(6)
      ..write(obj.canViewReports)
      ..writeByte(7)
      ..write(obj.canAddSales)
      ..writeByte(8)
      ..write(obj.canDeleteSales)
      ..writeByte(9)
      ..write(obj.canAddPurchases)
      ..writeByte(10)
      ..write(obj.canDeletePurchases)
      ..writeByte(11)
      ..write(obj.canAddInventory)
      ..writeByte(12)
      ..write(obj.canEditInventory)
      ..writeByte(13)
      ..write(obj.canDeleteInventory)
      ..writeByte(14)
      ..write(obj.canExportReports)
      ..writeByte(15)
      ..write(obj.displayName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUserAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
