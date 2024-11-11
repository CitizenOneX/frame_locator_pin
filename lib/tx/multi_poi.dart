import 'dart:convert';
import 'dart:typed_data';

import 'package:simple_frame_app/tx_msg.dart';

/// A point-of-interest ready for display on Frame
class Poi {
  int spriteCode;
  int x;
  int paletteOffset;
  String label;

  Poi({
    required this.spriteCode,
    this.x = 1,
    this.paletteOffset = 0,
    this.label = '',
  });

  Uint8List pack() {
    final stringBytes = utf8.encode(label);
    final strlen = stringBytes.length;

    Uint8List bytes = Uint8List(5 + strlen);
    bytes[0] = spriteCode & 0xFF;
    bytes[1] = x >> 8;   // x msb
    bytes[2] = x & 0xFF; // x lsb
    bytes[3] = paletteOffset & 0x0F; // 0..15
    bytes[4] = strlen & 0xFF;
    bytes.setRange(5, strlen + 5, stringBytes);

    return bytes;
  }
}

/// A Message representing the location of multiple points of interest (POIs)
class TxMultiPoi extends TxMsg {
  List<Poi> pois;

  TxMultiPoi({
    required super.msgCode,
    required this.pois
  });

  @override
  Uint8List pack() {
    List<Uint8List> packedPois = pois.map((poi) => poi.pack()).toList();
    Uint8List bytes = Uint8List(2 + packedPois.fold(0, (sum, list) => sum + list.length));

    bytes[0] = msgCode;
    bytes[1] = packedPois.length;

    int offset = 2;

    for (var poiBytes in packedPois) {
      bytes.setRange(offset, offset + poiBytes.length, poiBytes);
      offset += poiBytes.length;
    }

    return bytes;
  }
}
