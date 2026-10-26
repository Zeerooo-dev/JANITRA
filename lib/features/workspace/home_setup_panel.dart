import 'package:flutter/material.dart';

import '../../core/aurora_glass.dart';
import '../../core/appearance_settings.dart';

/// Guides authorized Supervisors through workspace setup using existing actions.
/// This widget never creates a company, grants access, or submits data itself.
class HomeSetupPanel extends StatelessWidget {
  const HomeSetupPanel({
    super.key,
    required this.hasAgency,
    required this.hasClient,
    required this.hasWorkplace,
    required this.canAddAgency,
    required this.canManageAgency,
    required this.isAdmin,
    required this.onAddAgency,
    required this.onAddClient,
    required this.onAddWorkplace,
    required this.onManageTeam,
    required this.onRefreshAccess,
  });

  final bool hasAgency;
  final bool hasClient;
  final bool hasWorkplace;
  final bool canAddAgency;
  final bool canManageAgency;
  final bool isAdmin;
  final VoidCallback onAddAgency;
  final VoidCallback onAddClient;
  final VoidCallback onAddWorkplace;
  final VoidCallback onManageTeam;
  final VoidCallback onRefreshAccess;

  int get _nextStep => !hasAgency
      ? 0
      : !hasClient
      ? 1
      : !hasWorkplace
      ? 2
      : 3;

  bool get _canPerformNext => switch (_nextStep) {
    0 => canAddAgency,
    1 || 2 => canManageAgency,
    _ => true,
  };

  VoidCallback get _nextAction => switch (_nextStep) {
    0 => onAddAgency,
    1 => onAddClient,
    2 => onAddWorkplace,
    _ => onManageTeam,
  };

  static const _titles = [
    'Manpower agency',
    'Client company',
    'Workplace',
    'Team members',
  ];
  static const _descriptions = [
    'Create the agency that employs your cleaners',
    'Add a company that receives cleaning services',
    'Create a location for assigned work',
    'Invite or assign people to the workplace',
  ];
  static const _actions = [
    'Add Manpower Agency',
    'Add Client Company',
    'Add Workplace',
    'Manage Team',
  ];
  static const _icons = [
    Icons.business_outlined,
    Icons.apartment_outlined,
    Icons.location_on_outlined,
    Icons.people_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highContrast =
        context
            .dependOnInheritedWidgetOfExactType<AppearanceScope>()
            ?.notifier
            ?.highContrast ??
        false;
    final heroInk = highContrast ? colors.onSurface : colors.onPrimaryContainer;
    final next = _nextStep;
    final allowed = _canPerformNext;
    final heading = allowed
        ? switch (next) {
            0 => 'Set up your workspace',
            1 => 'Add your first client',
            2 => 'Create a workplace',
            _ => 'Bring your team onboard',
          }
        : 'Workspace access needed';
    final subheading = allowed
        ? switch (next) {
            0 => 'Start with a manpower agency. We\'ll guide you through the rest.',
            1 => 'Your manpower agency is ready. Add a client company next.',
            2 => 'Now add the location where cleaning work takes place.',
            _ => 'Your workplace is ready. Add or assign team members.',
          }
        : 'Ask your administrator to assign your workplace, then refresh access.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JanitraGlassPanel(
          key: const ValueKey('home-setup-hero'),
          padding: const EdgeInsets.all(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.56, 1],
            colors: [
              colors.primaryContainer.withValues(alpha: .87),
              Color.lerp(
                colors.primaryContainer,
                colors.tertiaryContainer,
                .35,
              )!.withValues(alpha: .83),
              colors.surface.withValues(alpha: .43),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    allowed ? _icons[next] : Icons.lock_outline,
                    color: heroInk,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                allowed ? 'LET\'S GET STARTED' : 'WORKSPACE ACCESS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: heroInk,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                heading,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: heroInk,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subheading,
                style: theme.textTheme.bodyMedium?.copyWith(color: heroInk),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('home-setup-primary-action'),
                  onPressed: allowed ? _nextAction : onRefreshAccess,
                  icon: Icon(
                    allowed ? Icons.add_circle_outline : Icons.refresh,
                  ),
                  label: Text(allowed ? _actions[next] : 'Refresh Access'),
                ),
              ),
              if (isAdmin && !hasAgency) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: onManageTeam,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Manage unassigned people'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              'Your setup checklist',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${next.clamp(0, 3)} of 3 ready',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          key: const ValueKey('home-setup-progress'),
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: next.clamp(0, 3) / 3,
            minHeight: 5,
            color: colors.primary,
            backgroundColor: colors.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 13),
        JanitraGlassCard(
          margin: EdgeInsets.zero,
          child: Column(
            children: List.generate(_titles.length, (index) {
              final complete = index < next && index < 3;
              final current = index == next;
              final actionable = current && allowed;
              return Column(
                children: [
                  if (index != 0) const Divider(height: 1, indent: 58),
                  ListTile(
                    key: ValueKey('home-setup-step-$index'),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 12,
                    ),
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: complete
                          ? colors.secondaryContainer
                          : current
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                      child: complete
                          ? Icon(
                              Icons.check,
                              size: 18,
                              color: colors.onSecondaryContainer,
                            )
                          : Icon(
                              _icons[index],
                              size: 18,
                              color: current
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                    ),
                    title: Text(
                      _titles[index],
                      style: TextStyle(
                        fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                        color: current ? colors.primary : colors.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      complete
                          ? 'Ready'
                          : current && !allowed
                          ? 'Requires additional access'
                          : current
                          ? _descriptions[index]
                          : 'Complete earlier steps first',
                    ),
                    trailing: actionable
                        ? const Icon(Icons.chevron_right)
                        : complete
                        ? Icon(
                            Icons.check_circle_outline,
                            color: colors.primary,
                          )
                        : null,
                    onTap: actionable ? _nextAction : null,
                  ),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onRefreshAccess,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh workspace access'),
          ),
        ),
      ],
    );
  }
}

/// Non-blocking quick action shown alongside the regular dashboard after setup.
/// It intentionally does not claim that personnel accounts have already been created.
class HomeTeamQuickAction extends StatelessWidget {
  const HomeTeamQuickAction({super.key, required this.onManageTeam});

  final VoidCallback onManageTeam;

  @override
  Widget build(BuildContext context) => JanitraGlassCard(
    margin: const EdgeInsets.only(bottom: 14),
    child: ListTile(
      leading: const Icon(Icons.group_add_outlined),
      title: const Text('Manage your team'),
      subtitle: const Text('Add people or update their assignments'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onManageTeam,
    ),
  );
}
