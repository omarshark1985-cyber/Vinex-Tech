import 'package:flutter/material.dart';

/// Responsive utility — call R.of(context) once per build, then use its fields.
///
/// Breakpoints:
///   mobile  : width < 480
///   tablet  : 480 ≤ width < 800
///   desktop : width ≥ 800
class R {
  final double width;
  final double height;
  final bool isMobile;
  final bool isTablet;
  final bool isDesktop;

  const R._({
    required this.width,
    required this.height,
    required this.isMobile,
    required this.isTablet,
    required this.isDesktop,
  });

  factory R.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final h = mq.size.height;
    return R._(
      width: w,
      height: h,
      isMobile: w < 480,
      isTablet: w >= 480 && w < 800,
      isDesktop: w >= 800,
    );
  }

  // ── Font sizes ───────────────────────────────────────────────────────────────

  /// Huge headline  (web 28 / tablet 25 / mobile 22)
  double get fs28 => isMobile ? 22 : isTablet ? 25 : 28;

  /// Large headline  (web 24 / tablet 21 / mobile 19)
  double get fs24 => isMobile ? 19 : isTablet ? 21 : 24;

  /// Medium headline (web 20 / tablet 18 / mobile 17)
  double get fs20 => isMobile ? 17 : isTablet ? 18 : 20;

  /// Section title   (web 18 / tablet 17 / mobile 16)
  double get fs18 => isMobile ? 16 : isTablet ? 17 : 18;

  /// Card title      (web 17 / tablet 16 / mobile 15)
  double get fs17 => isMobile ? 15 : isTablet ? 16 : 17;

  /// Body large      (web 16 / tablet 15 / mobile 15)
  double get fs16 => isMobile ? 15 : isTablet ? 15 : 16;

  /// Body medium     (web 15 / tablet 14 / mobile 14)
  double get fs15 => isMobile ? 14 : isTablet ? 14 : 15;

  /// Body small      (web 14 / tablet 14 / mobile 13)
  double get fs14 => isMobile ? 13 : isTablet ? 14 : 14;

  /// Caption / label (web 13 / tablet 13 / mobile 12)
  double get fs13 => isMobile ? 12 : isTablet ? 13 : 13;

  /// Tiny hint       (web 12 / tablet 12 / mobile 12)
  double get fs12 => isMobile ? 12 : isTablet ? 12 : 12;

  /// Extra tiny      (web 11 / tablet 11 / mobile 11)
  double get fs11 => isMobile ? 11 : isTablet ? 11 : 11;

  // ── Spacing ──────────────────────────────────────────────────────────────────

  /// Horizontal page padding
  double get hPad => isMobile ? 14.0 : isTablet ? 18.0 : 24.0;

  /// Card internal padding
  double get cardPad => isMobile ? 14.0 : isTablet ? 16.0 : 20.0;

  /// Standard gap between elements
  double get gap => isMobile ? 10.0 : isTablet ? 12.0 : 14.0;

  /// Small gap
  double get gapS => isMobile ? 6.0 : 8.0;

  /// Large gap
  double get gapL => isMobile ? 16.0 : isTablet ? 20.0 : 24.0;

  // ── Icon sizes ───────────────────────────────────────────────────────────────

  double get iconLg => isMobile ? 24.0 : isTablet ? 26.0 : 30.0;
  double get iconMd => isMobile ? 20.0 : 22.0;
  double get iconSm => isMobile ? 16.0 : 18.0;

  // ── Grid columns ─────────────────────────────────────────────────────────────

  int get gridCols => isMobile ? 2 : isTablet ? 3 : 4;

  // ── Aspect ratio for dashboard cards ─────────────────────────────────────────

  double get cardAspect => isMobile ? 1.0 : isTablet ? 1.0 : 1.1;

  // ── AppBar title font ─────────────────────────────────────────────────────────

  double get appBarFs => isMobile ? 17.0 : 20.0;

  // ── Button height ─────────────────────────────────────────────────────────────

  double get btnHeight => isMobile ? 48.0 : 52.0;

  // ── Helper: choose between mobile and desktop value ───────────────────────────

  T pick<T>(T mobile, T desktop) => isMobile ? mobile : desktop;
}
