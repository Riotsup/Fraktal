library;

import 'package:flutter/material.dart';
import 'localization_controller.dart';

class LocalizationScope extends InheritedNotifier<LocalizationController> {
  const LocalizationScope({
    super.key,
    required LocalizationController controller,
    required super.child,
  }) : super(notifier: controller);

  static LocalizationController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LocalizationScope>();
    assert(scope != null, 'LocalizationScope is missing');
    return scope!.notifier!;
  }
}

extension LocalizedBuildContext on BuildContext {
  String tr(String keyOrDefault, [Map<String, Object?> args = const {}]) =>
      LocalizationScope.of(this).resolve(keyOrDefault, args);
}

/// Drop-in localized Text. Every visible string passed here is resolved through
/// the active standard/project catalogs before Flutter paints it.
class LText extends StatelessWidget {
  final String data;
  final Map<String, Object?> args;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  const LText(
    this.data, {
    super.key,
    this.args = const {},
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  @override
  Widget build(BuildContext context) => Text(
        context.tr(data, args),
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel:
            semanticsLabel == null ? null : context.tr(semanticsLabel!),
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
}
