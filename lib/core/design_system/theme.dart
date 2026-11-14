import 'package:flutter/material.dart';

Widget _buttonRelief(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => DecoratedBox(
  decoration: BoxDecoration(
    gradient: states.contains(WidgetState.disabled)
        ? null
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: .07),
              Colors.transparent,
              Colors.black.withValues(alpha: .04),
            ],
            stops: const [0, .35, 1],
          ),
  ),
  child: child,
);

class Brand {
  static const spacing = 8.0, cardRadius = 24.0, blur = 18.0;
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
  scaffoldBackgroundColor: Colors.transparent,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Brand.blue,
    primary: Brand.blue,
    secondary: Brand.ink,
    error: Brand.red,
    surface: Colors.white,
    onSurface: Brand.navy,
  ),
  extensions: [SurfaceStyle(opaque: opaque)],
  textTheme: ThemeData.light().textTheme
      .apply(bodyColor: Brand.navy, displayColor: Brand.navy)
      .copyWith(bodyMedium: const TextStyle(fontSize: 16, color: Brand.navy)),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: Brand.navy,
    surfaceTintColor: Colors.transparent,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      elevation: 7,
      shadowColor: Brand.blue.withValues(alpha: .32),
      side: BorderSide(color: Colors.white.withValues(alpha: .6)),
    ).copyWith(backgroundBuilder: _buttonRelief),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 52),
      foregroundColor: Brand.blue,
      backgroundColor: Colors.white.withValues(alpha: .85),
      elevation: 3,
      shadowColor: Brand.navy.withValues(alpha: .15),
      side: BorderSide(color: Brand.blue.withValues(alpha: .32)),
    ).copyWith(backgroundBuilder: _buttonRelief),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: opaque
        ? Colors.white
        : const Color(0xfff3faff).withValues(alpha: .90),
    elevation: 18,
    shadowColor: Brand.navy.withValues(alpha: .3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Colors.white, width: 1.5),
    ),
  ),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: opaque
        ? Colors.white
        : const Color(0xffedf7fd).withValues(alpha: .90),
    elevation: 18,
    shadowColor: Color(0x33142D4E),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      side: BorderSide(color: Colors.white, width: 1.5),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    indicatorColor: Colors.white,
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: Colors.white, width: 2),
    ),
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? Brand.blue : Brand.navy,
      ),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        color: states.contains(WidgetState.selected) ? Brand.blue : Brand.navy,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    ),
  ),
);
