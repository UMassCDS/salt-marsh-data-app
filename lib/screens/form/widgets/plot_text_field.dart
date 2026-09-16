import 'package:flutter/material.dart';

// A single field in a plot card that mutates plot state by field name via
// [onChanged] - keeps PlotCard's field list a plain data-driven list rather
// than one bespoke setState callback per field.
class PlotTextField extends StatelessWidget {
  final String field;
  final String currentValue;
  final String label;
  final IconData icon;
  final bool isNumber;
  final bool isDropdown;
  final bool isOptional;
  final int maxLines;
  final List<String>? dropdownOptions;
  final TextEditingController? controller;
  final void Function(String field, String value) onChanged;

  const PlotTextField({
    super.key,
    required this.field,
    required this.currentValue,
    required this.label,
    required this.icon,
    required this.onChanged,
    this.isNumber = false,
    this.isDropdown = false,
    this.isOptional = false,
    this.maxLines = 1,
    this.dropdownOptions,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    if (isDropdown && dropdownOptions != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: currentValue.isEmpty ? null : currentValue,
          items: dropdownOptions!.map((option) {
            return DropdownMenuItem(
              value: option,
              child: Text(option),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) onChanged(field, value);
          },
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(icon),
          ),
          validator: (value) {
            if (!isOptional && (value == null || value.isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        initialValue: controller != null ? null : currentValue,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        onChanged: (value) => onChanged(field, value),
        validator: (value) {
          if (!isOptional && (value == null || value.isEmpty)) {
            return 'This field is required';
          }
          return null;
        },
      ),
    );
  }
}
