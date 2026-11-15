import 'package:flutter/material.dart';

class LoadingStateView extends StatelessWidget {
  final String? message;
  const LoadingStateView({super.key, this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (message != null) ...[const SizedBox(height: 16), Text(message!)],
      ],
    ),
  );
}

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class ErrorStateView extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;
  const ErrorStateView({super.key, this.error, this.onRetry});

  @override
  Widget build(BuildContext context) => EmptyStateView(
    icon: Icons.cloud_off_outlined,
    title: 'No pudimos cargar esta sección',
    message: error?.toString(),
    actionLabel: onRetry == null ? null : 'Reintentar',
    onAction: onRetry,
  );
}
