import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// A QR code that is always dark-on-light, even in the dark theme, so phone
/// cameras scan it reliably (docs/13 §6 "QR"). 16 px quiet zone.
///
/// The QR payload itself is produced by the pairing layer; this widget only
/// renders the string it is given and never reads or logs it.
class TdQrTile extends StatelessWidget {
  const TdQrTile({
    super.key,
    required this.data,
    this.size = 220,
    this.semanticLabel = 'Pairing QR code',
  });

  final String data;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return Semantics(
      label: semanticLabel,
      image: true,
      child: TdSurface(
        color: tokens.qrTile,
        radius: TdRadius.md,
        border: false,
        padding: const EdgeInsets.all(TdSpace.s16),
        child: QrImageView(
          data: data,
          version: QrVersions.auto,
          size: size,
          gapless: true,
          backgroundColor: tokens.qrTile,
          eyeStyle: QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: tokens.qrInk,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: tokens.qrInk,
          ),
        ),
      ),
    );
  }
}
