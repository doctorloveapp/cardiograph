import 'package:flutter/material.dart';

class Brand {
  static const spacing = 8.0, cardRadius = 24.0, blur = 10.0;
  static const canvas = Color(0xFFF4F9FD),
      blue = Color(0xFF1261C9),
      sky = Color(0xFF78C8EE),
      mint = Color(0xFF08D8BF),
      soft = Color(0xFFE5FAF5),
      ink = Color(0xFF006D62),
      navy = Color(0xFF142D4E),
      red = Color(0xFFB42338);
}

@immutable
class SurfaceStyle extends ThemeExtension<SurfaceStyle> {
  final bool opaque;
  const SurfaceStyle({this.opaque = false});
  @override
  SurfaceStyle copyWith({bool? opaque}) =>
      SurfaceStyle(opaque: opaque ?? this.opaque);
  @override
  SurfaceStyle lerp(covariant SurfaceStyle? other, double t) =>
      t < .5 ? this : other ?? this;
}

ThemeData appTheme(bool opaque) => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: Brand.canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Brand.blue,
    primary: Brand.blue,
    secondary: Brand.ink,
    error: Brand.red,
    surface: Colors.white,
  ),
  extensions: [SurfaceStyle(opaque: opaque)],
  textTheme: ThemeData.light().textTheme
      .apply(bodyColor: Brand.navy, displayColor: Brand.navy)
      .copyWith(bodyMedium: const TextStyle(fontSize: 16, color: Brand.navy)),
  appBarTheme: const AppBarTheme(
    backgroundColor: Brand.canvas,
    foregroundColor: Brand.navy,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  navigationBarTheme: const NavigationBarThemeData(indicatorColor: Brand.soft),
);
