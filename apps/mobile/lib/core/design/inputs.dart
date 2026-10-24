import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The only text input for NorthStar screens, dialogs and sheets. Look comes
/// from `NorthstarTheme` (filled, rounded, accent focus ring); do not restyle
/// per screen and do not use a raw `TextField`/`TextFormField` in features.
class NsTextField extends StatelessWidget {
  const NsTextField({
    this.controller,
    this.label,
    this.hint,
    this.initialValue,
    this.enabled = true,
    this.autofocus = false,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.prefixIcon,
    this.dense = false,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  /// Tighter padding for fields sharing a row (e.g. reps / weight / unit).
  final bool dense;
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? initialValue;
  final bool enabled;
  final bool autofocus;
  final int? maxLength;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? prefixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
          : null,
    );
    if (initialValue != null && controller == null) {
      return TextFormField(
        initialValue: initialValue,
        enabled: enabled,
        autofocus: autofocus,
        maxLength: maxLength,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        decoration: decoration,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
      );
    }
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      decoration: decoration,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// A choice in an [NsDropdown].
class NsOption<T> {
  const NsOption(this.value, this.label);
  final T value;
  final String label;
}

/// The only single-choice select. Same field look as [NsTextField].
class NsDropdown<T> extends StatelessWidget {
  const NsDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.dense = false,
    super.key,
  });

  /// Tighter padding for fields sharing a row.
  final bool dense;
  final T value;
  final List<NsOption<T>> options;

  /// Null disables the control.
  final ValueChanged<T>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      borderRadius: BorderRadius.circular(16),
      dropdownColor: scheme.surface,
      icon: const Icon(Icons.expand_more),
      decoration: InputDecoration(
        labelText: label,
        contentPadding: dense
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
            : null,
      ),
      items: [
        for (final option in options)
          DropdownMenuItem<T>(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (next) {
              if (next != null) onChanged!(next);
            },
    );
  }
}

/// Selectable pill (period filters, unit toggles, "custom only"). Styling is
/// the theme's `chipTheme`.
class NsChip extends StatelessWidget {
  const NsChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: onSelected,
  );
}
