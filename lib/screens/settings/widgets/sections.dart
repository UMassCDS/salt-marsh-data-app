import 'package:flutter/material.dart';
import '../../../models/user/user.dart';
import 'settings_widgets.dart';

String _initials(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _formatDate(DateTime dt) => '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

String _formatDateTime(DateTime dt) {
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  return '${_months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour:$minute $period';
}

class AccountSection extends StatelessWidget {
  final User? user;
  final VoidCallback onSignOut;

  const AccountSection({super.key, required this.user, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(label: 'Account'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Text(
                        _initials(user?.fullName ?? ''),
                        style: textTheme.titleLarge?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  user?.fullName ?? '—',
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (user?.isSuperadmin == true)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.tertiaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Admin',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onTertiaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? '—',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              if (user?.createdAt != null)
                InfoTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Member since',
                  value: _formatDate(user!.createdAt!),
                ),
              if (user?.lastLogin != null) ...[
                Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                InfoTile(
                  icon: Icons.login_outlined,
                  label: 'Last login',
                  value: _formatDateTime(user!.lastLogin!),
                ),
              ],
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.logout,
                      size: 20, color: colorScheme.onErrorContainer),
                ),
                title: Text('Sign out',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w600,
                    )),
                onTap: onSignOut,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AppearanceSection extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode?> onChanged;

  const AppearanceSection({super.key, required this.themeMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(label: 'Appearance'),
        const SizedBox(height: 8),
        Card(
          child: RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: onChanged,
            child: Column(
              children: [
                ThemeOptionTile(
                  value: ThemeMode.system,
                  icon: Icons.brightness_auto_outlined,
                  label: 'System default',
                  subtitle: 'Follows your device theme',
                  accentColor: colorScheme.primary,
                  isFirst: true,
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                ThemeOptionTile(
                  value: ThemeMode.light,
                  icon: Icons.light_mode_outlined,
                  label: 'Light',
                  subtitle: 'Always use light theme',
                  accentColor: const Color(0xFFFFB300),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                ThemeOptionTile(
                  value: ThemeMode.dark,
                  icon: Icons.dark_mode_outlined,
                  label: 'Dark',
                  subtitle: 'Always use dark theme',
                  accentColor: const Color(0xFF5C6BC0),
                  isLast: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DataSection extends StatelessWidget {
  final bool uploading;
  final String statusLine;
  final VoidCallback onSendAll;
  final VoidCallback onSendOneDay;

  const DataSection({
    super.key,
    required this.uploading,
    required this.statusLine,
    required this.onSendAll,
    required this.onSendOneDay,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(label: 'Data'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: DataTileIcon(
                  icon: Icons.cloud_upload_outlined,
                  busy: uploading,
                ),
                title: Text('Send all data to server',
                    style: textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  uploading
                      ? statusLine
                      : 'Everything on this device. Photos are sent in '
                          'batches you can stop and resume.',
                  style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.55)),
                ),
                onTap: uploading ? null : onSendAll,
              ),
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              ListTile(
                leading: const DataTileIcon(
                  icon: Icons.event_outlined,
                  busy: false,
                ),
                title: Text('Send data from one day',
                    style: textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Pick a date. Much quicker when you only need one day.',
                  style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.55)),
                ),
                onTap: uploading ? null : onSendOneDay,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AboutSection extends StatelessWidget {
  final String versionLabel;

  const AboutSection({super.key, required this.versionLabel});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(label: 'About'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.water,
                      size: 20, color: colorScheme.onPrimaryContainer),
                ),
                title: Text('Salt Marsh Data',
                    style: textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text('Salt Marsh Data Collection',
                    style: textTheme.bodySmall?.copyWith(
                        color:
                            colorScheme.onSurface.withValues(alpha: 0.55))),
                trailing: Text(versionLabel,
                    style: textTheme.labelSmall?.copyWith(
                        color:
                            colorScheme.onSurface.withValues(alpha: 0.45))),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
