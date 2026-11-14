import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as im;

/// Coordinates always refer to the upright, EXIF-normalized source image.
class DisplayCrop {
  final double left, top, right, bottom;
  const DisplayCrop(this.left, this.top, this.right, this.bottom);
  static const full = DisplayCrop(0, 0, 1, 1);
}

class DisplayReading {
  final List<int?> values;
  final Uint8List preview;
  final DisplayCrop crop;
  final int elapsedMs;
  final String? issue;
  const DisplayReading(
    this.values,
    this.preview,
    this.crop,
    this.elapsedMs,
    this.issue,
  );
}

const segmentDigits = <String, int>{
  '1110111': 0, '0010010': 1, '1011101': 2, '1011011': 3,
  '0111010': 4, '1101011': 5, '1101111': 6, '1010010': 7,
  '1111111': 8, '1111011': 9,
  // LCD font variant with an upper-left stroke on 7 (no middle/bottom).
  '1110010': 7,
};

class _Blob {
  int left, top, right, bottom;
  final List<int> points;
  _Blob(this.left, this.top, this.right, this.bottom, this.points);
  int get width => right - left + 1;
  int get height => bottom - top + 1;
}

List<_Blob> _components(Uint8List mask, int w, int h) {
  final seen = Uint8List(mask.length);
  final blobs = <_Blob>[];
  for (var p = 0; p < mask.length; p++) {
    if (mask[p] == 0 || seen[p] != 0) continue;
    final queue = <int>[p];
    seen[p] = 1;
    final b = _Blob(p % w, p ~/ w, p % w, p ~/ w, queue);
    for (var i = 0; i < queue.length; i++) {
      final pos = queue[i], x = pos % w, y = pos ~/ w;
      b.left = math.min(b.left, x);
      b.right = math.max(b.right, x);
      b.top = math.min(b.top, y);
      b.bottom = math.max(b.bottom, y);
      for (final next in [
        if (x > 0) pos - 1,
        if (x + 1 < w) pos + 1,
        if (y > 0) pos - w,
        if (y + 1 < h) pos + w,
      ]) {
        if (mask[next] != 0 && seen[next] == 0) {
          seen[next] = 1;
          queue.add(next);
        }
      }
    }
    if (queue.length >= 8) blobs.add(b);
  }
  return blobs;
}

/// Local illumination subtraction keeps a shadow from becoming a digit.
Uint8List _ink(im.Image image) {
  final w = image.width, h = image.height, stride = w + 1;
  final integral = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0.0;
    for (var x = 0; x < w; x++) {
      row += image.getPixel(x, y).luminance;
      integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + row;
    }
  }
  final radius = math.max(8, (w * .09).round());
  final mask = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = math.max(0, x - radius), r = math.min(w, x + radius + 1);
      final t = math.max(0, y - radius), b = math.min(h, y + radius + 1);
      final mean =
          (integral[b * stride + r] -
              integral[t * stride + r] -
              integral[b * stride + l] +
              integral[t * stride + l]) /
          ((r - l) * (b - t));
      if (image.getPixel(x, y).luminance < mean - 11) mask[y * w + x] = 1;
    }
  }
  return mask;
}

List<(int, int)> _runs(List<int> projection, int threshold, int bridge) {
  final ranges = <(int, int)>[];
  var start = -1, last = -1;
  for (var i = 0; i < projection.length; i++) {
    if (projection[i] >= threshold) {
      if (start < 0) start = i;
      last = i;
    } else if (start >= 0 && i - last > bridge) {
      ranges.add((start, last));
      start = -1;
    }
  }
  if (start >= 0) ranges.add((start, last));
  return ranges;
}

int? decodeSegments(Uint8List ink, int w, int h, int l, int t, int r, int b) {
  final dw = r - l + 1, dh = b - t + 1;
  if (dh < 12) return null;
  // A narrow pair of vertical strokes is the digit 1, not a padded arbitrary digit.
  if (dw / dh < .26) {
    var occupied = 0;
    for (var y = t; y <= b; y++) {
      if (List.generate(dw, (i) => ink[y * w + l + i]).any((v) => v == 1)) {
        occupied++;
      }
    }
    return occupied / dh > .78 ? 1 : null;
  }
  if (dw / dh < .30 || dw / dh > .95) return null;
  const patches = [
    (.5, .07, .40, .10),
    (.14, .27, .13, .24),
    (.86, .27, .13, .24),
    (.5, .5, .40, .10),
    (.14, .74, .13, .24),
    (.84, .74, .13, .24),
    (.5, .93, .40, .10),
  ];
  final states = <String>[];
  final occupancies = <double>[];
  for (final p in patches) {
    final x0 = (l + (p.$1 - p.$3 / 2) * dw).round().clamp(l, r);
    final x1 = (l + (p.$1 + p.$3 / 2) * dw).round().clamp(l, r);
    final y0 = (t + (p.$2 - p.$4 / 2) * dh).round().clamp(t, b);
    final y1 = (t + (p.$2 + p.$4 / 2) * dh).round().clamp(t, b);
    var dark = 0, count = 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        dark += ink[y * w + x];
        count++;
      }
    }
    final occupancy = dark / count;
    occupancies.add(occupancy);
    states.add(occupancy >= .46 ? '1' : '0');
  }
  if (occupancies.any((v) => v > .22 && v < .46)) return null;
  return segmentDigits[states.join()];
}

List<int?> _readRows(im.Image lcd) {
  final w = lcd.width, h = lcd.height;
  final mask = _ink(lcd);
  // Remove specks and labels/icons smaller than a number's vertical strokes.
  final projection = List<int>.filled(h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      projection[y] += mask[y * w + x];
    }
  }
  final rows = _runs(
    projection,
    math.max(3, (w * .055).round()),
    math.max(2, (h * .025).round()),
  ).where((r) => r.$2 - r.$1 > h * .10 && r.$2 - r.$1 < h * .40).toList();
  if (rows.length != 3) return [null, null, null];
  final values = <int?>[];
  for (final row in rows) {
    final columns = List<int>.filled(w, 0);
    for (var x = 0; x < w; x++) {
      for (var y = row.$1; y <= row.$2; y++) {
        columns[x] += mask[y * w + x];
      }
    }
    final chars = _runs(
      columns,
      math.max(2, ((row.$2 - row.$1) * .09).round()),
      math.max(1, (w * .007).round()),
    );
    final digits = <int?>[];
    for (final c in chars) {
      var top = h, bottom = -1;
      for (var y = row.$1; y <= row.$2; y++) {
        var count = 0;
        for (var x = c.$1; x <= c.$2; x++) {
          count += mask[y * w + x];
        }
        // Ignore isolated dirt/reflection pixels when locating a character's top/bottom.
        if (count >= math.max(2, ((c.$2 - c.$1 + 1) * .13).round())) {
          top = math.min(top, y);
          bottom = math.max(bottom, y);
        }
      }
      // Battery/OK symbols may be adjacent to a row, but are much shorter.
      if (bottom - top < (row.$2 - row.$1) * .70 ||
          c.$1 < w * .035 ||
          c.$2 > w * .965) {
        continue;
      }
      digits.add(decodeSegments(mask, w, h, c.$1, top, c.$2, bottom));
    }
    values.add(
      digits.length >= 2 && digits.length <= 3 && digits.every((d) => d != null)
          ? int.tryParse(digits.join())
          : null,
    );
  }
  return values.map((v) => v != null && v >= 1 && v <= 999 ? v : null).toList();
}

DisplayReading decodeDisplay(Uint8List bytes, {DisplayCrop? crop}) {
  final watch = Stopwatch()..start();
  final decoded = im.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Fotografia non leggibile');
  var source = im.bakeOrientation(decoded);
  final selected = crop ?? DisplayCrop.full;
  if (selected.left < 0 ||
      selected.top < 0 ||
      selected.right > 1 ||
      selected.bottom > 1 ||
      selected.right - selected.left < .05 ||
      selected.bottom - selected.top < .05) {
    throw const FormatException('Ritaglio non valido');
  }
  source = im.copyCrop(
    source,
    x: (selected.left * source.width).floor(),
    y: (selected.top * source.height).floor(),
    width: ((selected.right - selected.left) * source.width).floor(),
    height: ((selected.bottom - selected.top) * source.height).floor(),
  );
  if (math.max(source.width, source.height) > 1400) {
    source = im.copyResize(
      source,
      width: source.width >= source.height ? 1400 : null,
      height: source.height > source.width ? 1400 : null,
    );
  }
  final w = source.width, h = source.height;
  _Blob? frame;
  var score = 0.0;
  for (final threshold in [65, 85, 105]) {
    final mask = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (source.getPixel(x, y).luminance < threshold) mask[y * w + x] = 1;
      }
    }
    for (final b in _components(mask, w, h)) {
      final area = b.width * b.height,
          ratio = b.height / b.width,
          density = b.points.length / area;
      if (b.left < 2 ||
          b.top < 2 ||
          b.right >= w - 2 ||
          b.bottom >= h - 2 ||
          area < w * h * .025 ||
          area > w * h * .8 ||
          ratio < .75 ||
          ratio > 2.3 ||
          density < .09 ||
          density > .68) {
        continue;
      }
      final value = area / (1 + (((b.left + b.right) / 2 - w / 2) / w).abs());
      if (value > score) {
        frame = b;
        score = value;
      }
    }
  }
  var lcd = source;
  var displayCrop = selected;
  if (frame != null) {
    final sw = selected.right - selected.left,
        sh = selected.bottom - selected.top;
    displayCrop = DisplayCrop(
      selected.left + (frame.left / w - .025).clamp(0, 1) * sw,
      selected.top + (frame.top / h - .025).clamp(0, 1) * sh,
      selected.left + (frame.right / w + .025).clamp(0, 1) * sw,
      selected.top + (frame.bottom / h + .025).clamp(0, 1) * sh,
    );
    var bestArea = double.infinity, bestAngle = 0.0;
    var bounds = <double>[];
    for (var degrees = -25; degrees <= 25; degrees++) {
      final a = degrees * math.pi / 180, c = math.cos(a), s = math.sin(a);
      var l = double.infinity,
          t = double.infinity,
          r = double.negativeInfinity,
          b = double.negativeInfinity;
      for (var i = 0; i < frame.points.length; i += 4) {
        final p = frame.points[i],
            x = p % w,
            y = p ~/ w,
            u = x * c + y * s,
            v = -x * s + y * c;
        l = math.min(l, u);
        r = math.max(r, u);
        t = math.min(t, v);
        b = math.max(b, v);
      }
      final area = (r - l) * (b - t);
      if (area < bestArea) {
        bestArea = area;
        bestAngle = a;
        bounds = [l, t, r, b];
      }
    }
    final fw = bounds[2] - bounds[0], fh = bounds[3] - bounds[1];
    final ow = (fw * .80).round(), oh = (fh * .80).round();
    lcd = im.Image(width: ow, height: oh);
    final c = math.cos(bestAngle), s = math.sin(bestAngle);
    for (var y = 0; y < oh; y++) {
      for (var x = 0; x < ow; x++) {
        final u = bounds[0] + fw * .10 + x, v = bounds[1] + fh * .10 + y;
        final sx = (u * c - v * s).round().clamp(0, w - 1),
            sy = (u * s + v * c).round().clamp(0, h - 1);
        lcd.setPixel(x, y, source.getPixel(sx, sy));
      }
    }
  }
  final values = _readRows(lcd);
  return DisplayReading(
    values,
    Uint8List.fromList(im.encodeJpg(lcd, quality: 90)),
    displayCrop,
    watch.elapsedMilliseconds,
    values.any((v) => v == null)
        ? 'Completa o verifica i campi incerti.'
        : null,
  );
}
