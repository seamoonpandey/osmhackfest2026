// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RoadReportAdapter extends TypeAdapter<RoadReport> {
  @override
  final int typeId = 1;

  @override
  RoadReport read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RoadReport(
      id: fields[0] as String,
      lat: fields[1] as double?,
      lng: fields[2] as double?,
      osmNodeId: fields[3] as String?,
      roadName: fields[4] as String?,
      severity: fields[5] as Severity,
      issueType: fields[10] as String?,
      description: fields[6] as String,
      imageUrl: fields[7] as String?,
      timestamp: fields[8] as DateTime,
      isSynced: fields[9] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, RoadReport obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.lat)
      ..writeByte(2)
      ..write(obj.lng)
      ..writeByte(3)
      ..write(obj.osmNodeId)
      ..writeByte(4)
      ..write(obj.roadName)
      ..writeByte(5)
      ..write(obj.severity)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.imageUrl)
      ..writeByte(8)
      ..write(obj.timestamp)
      ..writeByte(9)
      ..write(obj.isSynced)
      ..writeByte(10)
      ..write(obj.issueType);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoadReportAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SeverityAdapter extends TypeAdapter<Severity> {
  @override
  final int typeId = 0;

  @override
  Severity read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return Severity.level1;
      case 1:
        return Severity.level2;
      case 2:
        return Severity.level3;
      case 3:
        return Severity.level4;
      case 4:
        return Severity.level5;
      default:
        return Severity.level1;
    }
  }

  @override
  void write(BinaryWriter writer, Severity obj) {
    switch (obj) {
      case Severity.level1:
        writer.writeByte(0);
        break;
      case Severity.level2:
        writer.writeByte(1);
        break;
      case Severity.level3:
        writer.writeByte(2);
        break;
      case Severity.level4:
        writer.writeByte(3);
        break;
      case Severity.level5:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeverityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
