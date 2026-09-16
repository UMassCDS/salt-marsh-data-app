import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mass_marsh_app/screens/form/form_editor_screen.dart';

class FormManagementScreen extends ConsumerStatefulWidget {
  final int orgId;
  final String orgName;

  const FormManagementScreen({
    Key? key,
    required this.orgId,
    required this.orgName,
  }) : super(key: key);

  @override
  ConsumerState<FormManagementScreen> createState() =>
      _FormManagementScreenState();
}

class _FormManagementScreenState extends ConsumerState<FormManagementScreen> {
  final List<Map<String, dynamic>> forms = [
    {
      'name': 'Common Form',
      'id': 'common',
      'description': 'Questions asked in all monitoring types',
      'icon': Icons.info,
      'fields': 6,
    },
    {
      'name': 'Vegetation Monitoring',
      'id': 'vegetation',
      'description': 'Plot-based vegetation surveys',
      'icon': Icons.eco,
      'fields': 12,
    },
    {
      'name': 'Hydrology Monitoring',
      'id': 'hydrology',
      'description': 'Water level and well measurements',
      'icon': Icons.water,
      'fields': 10,
    },
    {
      'name': 'Elevation Monitoring',
      'id': 'elevation',
      'description': 'Point elevation data collection',
      'icon': Icons.terrain,
      'fields': 8,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Form Management'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header with org info
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.blue[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Organization',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.orgName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Add custom fields to these forms to collect additional organization-specific data.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          // Forms list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: forms.length,
              itemBuilder: (context, index) {
                final form = forms[index];
                return _buildFormCard(context, form);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(BuildContext context, Map<String, dynamic> form) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FormEditorScreen(
                orgId: widget.orgId,
                formType: form['id'],
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    form['icon'],
                    size: 32,
                    color: Colors.blue[600],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          form['name'],
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          form['description'],
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FormEditorScreen(
                            orgId: widget.orgId,
                            formType: form['id'],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Chip(
                    label: Text('${form['fields']} base fields'),
                    avatar: const Icon(Icons.checklist, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: const Text('0 custom fields'),
                    avatar: const Icon(Icons.add_circle, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
