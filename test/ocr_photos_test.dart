import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as im;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cardiograph/core/vision/seven_segment.dart';

void main() {
  const expected = [
    [123, 88, 64],
    [132, 88, 69],
    [129, 82, 76],
    [127, 85, 67],
    [128, 80, 69],
    [128, 86, 66],
  ];
  const goldenHashes = [
    'abf883d657894a8a5ab8c1acaf44891d4ef7d937e6219c33935f4e3d3662136e',
    'acedc0b3d2c3be28eb85366dad7e55f1c480c619430c3335d2706ef8789122c5',
    'd5e21e050bf787b5ee71088fae70914793c1203fadb43ee9e7b5db0db08fe0f7',
    '279596ece250b90a2e6e28f025a0c5d9501db5eb38987c401bec39530dbbc9f0',
    'cab1b4c8869442e02b71cb9248f20ed23ddc322fc4610390d9070fe954600b49',
    'c1f507a670cd06e57375992439fc885dd2eac8c46c9495a599f094115b326013',
  ];
  final hasDataset = Directory('Documenti').existsSync();
  test(
    'Sei fotografie reali: localizzazione e ordine verticale',
    () async {
      var exact = 0;
      for (var i = 0; i < 6; i++) {
        final file = File(
          'Documenti/esempio foto per letture valori${i == 0 ? '' : i + 1}.jpg',
        );
        final bytes = file.readAsBytesSync();
        final hash = await Sha256().hash(bytes);
        expect(
          hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          goldenHashes[i],
          reason: 'Originale OCR modificato',
        );
        final result = decodeDisplay(bytes);
        // Actual results are printed only by the test, never by the application.
        // ignore: avoid_print
        print(
          'Foto ${i + 1}: ${result.values} (${result.elapsedMs} ms), atteso ${expected[i]}',
        );
        for (var j = 0; j < 3; j++) {
          if (result.values[j] != null) {
            expect(
              result.values[j],
              expected[i][j],
              reason: 'Nessuna cifra inventata/inversione in foto ${i + 1}',
            );
          }
        }
        if (i == 0) expect(result.values, expected[0]);
        if (result.values.toString() == expected[i].toString()) exact++;
      }
      expect(exact, 6);
    },
    skip: hasDataset
        ? false
        : 'Dataset privato locale richiesto: 6 JPG in Documenti/.',
  );
  test(
    'Localizzazione di tre righe con due/tre cifre, senza numero di cifre fisso',
    () {
      for (final values in [
        [234, 101, 112],
        [98, 76, 54],
      ]) {
        final image = im.Image(width: 300, height: 430);
        final background = im.ColorRgb8(210, 210, 210),
            black = im.ColorRgb8(10, 10, 10);
        im.fill(image, color: background);
        im.fillRect(image, x1: 20, y1: 20, x2: 280, y2: 410, color: black);
        im.fillRect(image, x1: 32, y1: 32, x2: 268, y2: 398, color: background);
        for (var row = 0; row < 3; row++) {
          final digits = values[row].toString();
          for (var i = 0; i < digits.length; i++) {
            final digit = int.parse(digits[i]);
            final pattern = segmentDigits.entries
                .firstWhere((e) => e.value == digit)
                .key;
            final x = 60 + (3 - digits.length + i) * 60, y = 75 + row * 105;
            final boxes = [
              (8, 0, 40, 8),
              (0, 8, 8, 36),
              (40, 8, 48, 36),
              (8, 36, 40, 44),
              (0, 44, 8, 72),
              (40, 44, 48, 72),
              (8, 72, 40, 80),
            ];
            for (var j = 0; j < 7; j++) {
              if (pattern[j] == '1') {
                final b = boxes[j];
                im.fillRect(
                  image,
                  x1: x + b.$1,
                  y1: y + b.$2,
                  x2: x + b.$3,
                  y2: y + b.$4,
                  color: black,
                );
              }
            }
          }
        }
        final result = decodeDisplay(
          Uint8List.fromList(im.encodeJpg(image, quality: 100)),
        );
        expect(result.values, values);
      }
    },
  );
  test(
    'Orientamento EXIF, ritaglio e qualità insufficiente',
    () {
      final bytes = File(
        'Documenti/esempio foto per letture valori4.jpg',
      ).readAsBytesSync();
      final initial = decodeDisplay(bytes);
      final rerun = decodeDisplay(bytes, crop: initial.crop);
      expect(rerun.values, [127, 85, 67]);
      final rotated = im.copyRotate(im.decodeImage(bytes)!, angle: -90);
      rotated.exif.imageIfd.orientation = 6;
      expect(
        decodeDisplay(
          Uint8List.fromList(im.encodeJpg(rotated, quality: 98)),
        ).values,
        [127, 85, 67],
      );
      final blank = im.Image(width: 300, height: 430);
      im.fill(blank, color: im.ColorRgb8(180, 180, 180));
      expect(decodeDisplay(Uint8List.fromList(im.encodePng(blank))).values, [
        null,
        null,
        null,
      ]);
      expect(
        () => decodeDisplay(bytes, crop: const DisplayCrop(.9, 0, .1, 1)),
        throwsFormatException,
      );
    },
    skip: hasDataset
        ? false
        : 'Dataset privato locale richiesto per EXIF/crop.',
  );
}
