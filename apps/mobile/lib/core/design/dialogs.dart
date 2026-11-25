import 'package:flutter/material.dart';

/// Modal dialog frame. Shape, colors and type come from `dialogTheme`.
/// Use for forms; use [showNsConfirm] for yes/no questions.
class NsDialog extends StatelessWidget {
  const NsDialog({
    required this.title,
    required this.content,
    required this.actions,
    super.key,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: content,
    actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    actions: actions,
  );
}

/// Opens a form dialog built from [NsDialog].
Future<T?> showNsDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(context: context, builder: builder);

/// Yes/no question. Dismissing the dialog counts as "no".
Future<bool> showNsConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => NsDialog(
      title: title,
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return yes == true;
}

/// Bottom sheet for pickers. Shape and drag handle come from the theme.
Future<T?> showNsSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double heightFactor = 0.78,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) => FractionallySizedBox(
    heightFactor: heightFactor,
    child: builder(sheetContext),
  ),
);

/// Short, non-blocking message. Style comes from `snackBarTheme`. An optional
/// [actionLabel] adds one action button that runs [onAction]; the message
/// still times out. Returns the controller so a screen can close its own
/// message when it goes away.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showNsMessage(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final hasAction = actionLabel != null && onAction != null;
  return ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      // Flutter keeps a snackbar with an action until dismissed; ours time out.
      persist: hasAction ? false : null,
      duration: Duration(seconds: hasAction ? 6 : 4),
      action: hasAction
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ),
  );
}
