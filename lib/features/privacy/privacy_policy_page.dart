import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  late final _policy = rootBundle.loadString('assets/privacy/policy.json').then(
    (raw) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      for (final key in [
        'application',
        'operator',
        'effectiveDate',
        'updatedDate',
      ]) {
        if (data[key] is! String || (data[key] as String).trim().isEmpty) {
          throw const FormatException('Policy publication details incomplete');
        }
      }
      return data;
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy Policy')),
    body: SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: _policy,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'The Privacy Policy is unavailable in this installation. Please contact the application operator.',
              ),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final theme = Theme.of(context);
          return SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'JANITRA Privacy Policy',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Effective date: ${data['effectiveDate']}\nLast updated: ${data['updatedDate']}',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Developer / operator: ${data['operator']}',
                      ),
                      for (final section
                          in (data['sections'] as List)
                              .cast<Map<String, dynamic>>()) ...[
                        const SizedBox(height: 24),
                        Semantics(
                          header: true,
                          child: Text(
                            section['title'] as String,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        for (final text
                            in (section['paragraphs'] as List? ?? [])) ...[
                          const SizedBox(height: 12),
                          Text(
                            text as String,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ],
                        for (final text
                            in (section['bullets'] as List? ?? [])) ...[
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  '),
                              Expanded(
                                child: Text(
                                  text as String,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
