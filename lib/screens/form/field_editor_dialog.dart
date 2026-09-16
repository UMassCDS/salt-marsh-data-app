import 'package:flutter/material.dart';

class FieldEditorDialog extends StatefulWidget {
  final String? initialLabel;
  final String? initialId;
  final String? initialType;
  final bool initialRequired;
  final String? initialSection;
  final List<String> availableSections;
  final Function(Map<String, dynamic>) onSave;

  const FieldEditorDialog({
    Key? key,
    this.initialLabel,
    this.initialId,
    this.initialType,
    this.initialRequired = false,
    this.initialSection,
    required this.availableSections,
    required this.onSave,
  }) : super(key: key);

  @override
  State<FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends State<FieldEditorDialog> {
  late TextEditingController labelController;
  late TextEditingController idController;
  late TextEditingController helpTextController;
  late String selectedType;
  late bool isRequired;
  late String? selectedSection;
  late List<String> dropdownOptions;
  late TextEditingController minValueController;
  late TextEditingController maxValueController;

  final List<String> fieldTypes = [
    'text',
    'number',
    'date',
    'dropdown',
    'file',
    'textarea',
  ];

  @override
  void initState() {
    super.initState();
    labelController = TextEditingController(text: widget.initialLabel ?? '');
    idController = TextEditingController(text: widget.initialId ?? '');
    helpTextController = TextEditingController();
    selectedType = widget.initialType ?? 'text';
    isRequired = widget.initialRequired;
    selectedSection = widget.initialSection;
    dropdownOptions = [];
    minValueController = TextEditingController();
    maxValueController = TextEditingController();
  }

  @override
  void dispose() {
    labelController.dispose();
    idController.dispose();
    helpTextController.dispose();
    minValueController.dispose();
    maxValueController.dispose();
    super.dispose();
  }

  void _addDropdownOption() {
    showDialog(
      context: context,
      builder: (context) {
        final optionController = TextEditingController();
        return AlertDialog(
          title: const Text('Add Option'),
          content: TextField(
            controller: optionController,
            decoration: const InputDecoration(
              labelText: 'Option Label',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (optionController.text.isNotEmpty) {
                  setState(() {
                    dropdownOptions.add(optionController.text);
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _saveField() {
    if (labelController.text.isEmpty || idController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Label and ID are required')),
      );
      return;
    }

    final fieldData = {
      'label': labelController.text,
      'id': idController.text,
      'type': selectedType,
      'required': isRequired,
      'section': selectedSection,
      'helpText': helpTextController.text.isNotEmpty
          ? helpTextController.text
          : null,
      'dropdownOptions': selectedType == 'dropdown' ? dropdownOptions : null,
      'minValue': minValueController.text.isNotEmpty
          ? int.tryParse(minValueController.text)
          : null,
      'maxValue': maxValueController.text.isNotEmpty
          ? int.tryParse(maxValueController.text)
          : null,
    };

    widget.onSave(fieldData);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Field Editor'),
          automaticallyImplyLeading: false,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Basic Info Section
              _buildSectionTitle('Basic Information'),
              const SizedBox(height: 12),
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Field Label *',
                  hintText: 'e.g., Additional Comments',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: idController,
                decoration: const InputDecoration(
                  labelText: 'Field ID *',
                  hintText: 'e.g., additional_comments',
                  helperText: 'Unique identifier (lowercase, underscore only)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // Field Configuration
              _buildSectionTitle('Field Configuration'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Field Type *',
                  border: OutlineInputBorder(),
                ),
                items: fieldTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedType = value ?? 'text';
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: selectedSection,
                decoration: const InputDecoration(
                  labelText: 'Section',
                  border: OutlineInputBorder(),
                ),
                items: widget.availableSections.map((section) {
                  return DropdownMenuItem(
                    value: section,
                    child: Text(section),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedSection = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: helpTextController,
                decoration: const InputDecoration(
                  labelText: 'Help Text',
                  hintText: 'Guidance for field completion',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: const Text('Required Field'),
                value: isRequired,
                onChanged: (value) {
                  setState(() {
                    isRequired = value ?? false;
                  });
                },
              ),
              const SizedBox(height: 20),

              // Type-specific options
              if (selectedType == 'dropdown') ...[
                _buildSectionTitle('Dropdown Options'),
                const SizedBox(height: 12),
                if (dropdownOptions.isNotEmpty)
                  Column(
                    children: [
                      ...dropdownOptions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final option = entry.value;
                        return ListTile(
                          title: Text(option),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                dropdownOptions.removeAt(index);
                              });
                            },
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                  ),
                ElevatedButton.icon(
                  onPressed: _addDropdownOption,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Option'),
                ),
                const SizedBox(height: 20),
              ],

              if (selectedType == 'number') ...[
                _buildSectionTitle('Number Constraints'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minValueController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Min Value',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: maxValueController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max Value',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // Preview
              _buildSectionTitle('Preview'),
              const SizedBox(height: 12),
              Card(
                color: Colors.grey[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labelController.text.isEmpty
                            ? 'Field Label'
                            : labelController.text,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (helpTextController.text.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          helpTextController.text,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        selectedType == 'text'
                            ? 'Text field'
                            : selectedType == 'number'
                                ? 'Numeric input'
                                : selectedType == 'date'
                                    ? 'Date picker'
                                    : selectedType == 'dropdown'
                                        ? 'Dropdown (${dropdownOptions.length} options)'
                                        : selectedType == 'textarea'
                                            ? 'Text area'
                                            : 'File upload',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveField,
                  child: const Text('Save Field'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.blue[700],
          ),
    );
  }
}
