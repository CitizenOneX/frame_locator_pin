import 'dart:typed_data';

import 'package:simple_frame_app/tx_msg.dart';

///
class TxSpritePosition extends TxMsg {
  int spriteCode;
  int x;
  int y;
  int paletteOffset;

  TxSpritePosition({
    required super.msgCode,
    required this.spriteCode,
    this.x = 1,
    this.y = 1,
    this.paletteOffset = 0
    });

  @override
  Uint8List pack() {
    return Uint8List.fromList([spriteCode & 0xFF, x >> 8 & 0xFF, x & 0xFF, y >> 8 & 0xFF, y & 0xFF, paletteOffset & 0x0F]);
  }
}
