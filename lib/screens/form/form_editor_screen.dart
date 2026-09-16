import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mass_marsh_app/screens/form/field_editor_dialog.dart';

class FormEditorScreen extends ConsumerStatefulWidget {
  final int orgId;
  final String formType; // 'common', 'vegetation', 'hydrology', 'elevation'

  const FormEditorScreen({
    Key? key,
    required this.orgId,
    required this.formType,
  }) : super(key: key);

  @override
  ConsumerState<FormEditorScreen> createState() => _FormEditorScreenState();
}

class _FormEditorScreenState extends ConsumerState<FormEditorScreen> {
  final List<Map<String, dynamic>> customFields = [];

  final Map<String, List<String>> formSections = {
    'common': ['General Information', 'Crew Details', 'Location'],
    'vegetation': ['Plot Information', 'Species Data', 'Observations'],
    'hydrology': ['Water Measurements', 'Well Information', 'RTK Data'],
    'elevation': ['Point Information', 'Elevation Data', 'Feature Details'],
  };

  @override
  void initState() {
    super.initState();
  }

  void _removeField(int index) {
    setState(() {
      customFields.removeAt(index);
    });
  }

  void _showAddFieldDialog() {
    showDialog(
      context: context,
      builder: (context) => FieldEditorDialog(
        availableSections: formSections[widget.formType] ?? [],
        onSave: (fieldData) {
          setState(() {
            customFields.add(fieldData);
          });
        },
      ),
    );
  }

  void _publishForm() {
    if (customFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No custom fields to publish')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish Form Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to publish ${customFields.length} custom field(s) for the ${widget.formType} form.',
            ),
            const SizedBox(height: 16),
            const Text('This will be applied to all users in your organization.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Implement actual publishing logic
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Form published successfully!'),
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('Publish'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${widget.formType} Form'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header with form info
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Organization ID: ${widget.orgId}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${customFields.length} Custom Field(s)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _publishForm,
                  icon: const Icon(Icons.publish),
                  label: const Text('Publish'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          // Custom fields list
          Expanded(
            child: customFields.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.note_add,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No custom fields yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add fields to customize this form for your organization',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ReorderableListView(
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        final item = customFields.removeAt(oldIndex);
                        customFields.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (int i = 0; i < customFields.length; i++)
                        _buildFieldListItem(i, customFields[i]),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddFieldDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Field'),
      ),
    );
  }

  Widget _buildFieldListItem(int index, Map<String, dynamic> field) {
    return Card(
      key: ValueKey(index),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Text(field['label']),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                  label: Text(field['type']),
                  avatar: const Icon(Icons.category, size: 14),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 8),
                if (field['required'] == true)
                  const Chip(
                    label: Text('Required'),
                    avatar: Icon(Icons.star, size: 14),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            if (field['section'] != null) ...[
              const SizedBox(height: 4),
              Text(
                'Section: ${field['section']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _removeField(index),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
