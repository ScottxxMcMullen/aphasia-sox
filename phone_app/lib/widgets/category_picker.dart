import 'package:flutter/material.dart';

/// Returned by the picker's list in place of a real category name to mean
/// "the user wants to type a new one". A leading space keeps it from ever
/// colliding with a real category, since [canonicaliseCategory] trims.
const String _newCategorySentinel = ' new';

/// Reuses an existing category when [typed] matches one apart from case or
/// surrounding spaces. Without this, "church" and "Church" become two tiles
/// that look identical on the grid but hold different phrases — a split
/// that is hard to notice and harder to undo.
///
/// Returns the empty string when [typed] is blank, which callers treat as
/// "no category chosen".
String canonicaliseCategory(String typed, List<String> existing) {
  final trimmed = typed.trim();
  for (final category in existing) {
    if (category.toLowerCase() == trimmed.toLowerCase()) {
      return category;
    }
  }
  return trimmed;
}

/// Asks which category to use, offering [categories] plus the option to name
/// a new one. Returns the chosen name — canonicalised against [categories] —
/// or null if the user backed out at either step.
///
/// [exclude] drops one entry from the list; pass the phrase's current
/// category when moving, so the only options are ones that would actually
/// change something.
Future<String?> showCategoryPicker({
  required BuildContext context,
  required List<String> categories,
  required String title,
  String? exclude,
}) async {
  final offered = categories.where((c) => c != exclude).toList();
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final category in offered)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(category),
            child: Text(category),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(_newCategorySentinel),
          child: const Text('New category...'),
        ),
      ],
    ),
  );

  if (choice == null) {
    return null;
  }
  if (choice != _newCategorySentinel) {
    return choice;
  }
  if (!context.mounted) {
    return null;
  }
  return _promptForNewCategory(context, categories);
}

Future<String?> _promptForNewCategory(
  BuildContext context,
  List<String> categories,
) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Name the new category'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'For example: Church'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (name == null) {
    return null;
  }
  final canonical = canonicaliseCategory(name, categories);
  return canonical.isEmpty ? null : canonical;
}
