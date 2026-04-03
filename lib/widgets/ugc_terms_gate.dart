import 'package:flutter/material.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/screens/privacy_policy_screen.dart';
import 'package:mobile/screens/terms_of_use_screen.dart';
import 'package:mobile/theme/spot_theme.dart';

class UgcTermsSummary extends StatelessWidget {
  const UgcTermsSummary({super.key, this.showWordmark = true});

  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showWordmark) ...[
          Text(l10n.appTitle, style: SpotType.wordmark),
          const SizedBox(height: SpotSpacing.md),
        ],
        Text(l10n.ugcTermsTitle, style: SpotType.heading),
        const SizedBox(height: SpotSpacing.sm),
        Text(l10n.ugcTermsSubtitle, style: SpotType.bodySecondary),
        const SizedBox(height: SpotSpacing.xl),
        Container(
          padding: const EdgeInsets.all(SpotSpacing.lg),
          decoration: SpotDecoration.cardBordered(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.ugcTermsSafetyHeading, style: SpotType.subheading),
              const SizedBox(height: SpotSpacing.md),
              _TermsBullet(text: l10n.ugcTermsBulletRespect),
              _TermsBullet(text: l10n.ugcTermsBulletModeration),
              _TermsBullet(text: l10n.ugcTermsBulletReporting),
              _TermsBullet(text: l10n.ugcTermsBulletEnforcement),
            ],
          ),
        ),
      ],
    );
  }
}

class UgcTermsGate extends StatefulWidget {
  const UgcTermsGate({
    super.key,
    required this.onAccept,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final Future<void> Function() onAccept;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  State<UgcTermsGate> createState() => _UgcTermsGateState();
}

class _UgcTermsGateState extends State<UgcTermsGate> {
  bool _hasAgreed = false;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_isSubmitting || !_hasAgreed) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.onAccept();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        SpotSpacing.xxl,
        SpotSpacing.xxxl,
        SpotSpacing.xxl,
        SpotSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UgcTermsSummary(),
          const SizedBox(height: SpotSpacing.lg),
          Container(
            padding: const EdgeInsets.all(SpotSpacing.md),
            decoration: SpotDecoration.card(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _hasAgreed,
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _hasAgreed = value ?? false),
                ),
                const SizedBox(width: SpotSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 11),
                    child: Text(
                      l10n.ugcTermsAgreement,
                      style: SpotType.bodySecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpotSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _hasAgreed && !_isSubmitting ? _submit : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: SpotSpacing.md),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: SpotColors.onAccent,
                        strokeWidth: 1.5,
                      ),
                    )
                  : Text(l10n.ugcTermsAgreeButton),
            ),
          ),
          const SizedBox(height: SpotSpacing.md),
          const _LegalLinksRow(),
          if (widget.secondaryActionLabel != null &&
              widget.onSecondaryAction != null) ...[
            const SizedBox(height: SpotSpacing.sm),
            TextButton(
              onPressed: _isSubmitting ? null : widget.onSecondaryAction,
              child: Text(
                widget.secondaryActionLabel!,
                style: SpotType.bodySecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegalLinksRow extends StatelessWidget {
  const _LegalLinksRow();

  void _openTerms(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TermsOfUseScreen()),
    );
  }

  void _openPrivacy(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: SpotSpacing.sm,
      children: [
        _LinkButton(
          label: l10n.ugcTermsViewTerms,
          onTap: () => _openTerms(context),
        ),
        Text('·', style: SpotType.bodySecondary),
        _LinkButton(
          label: l10n.ugcTermsViewPrivacy,
          onTap: () => _openPrivacy(context),
        ),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: SpotType.bodySecondary.copyWith(
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class _TermsBullet extends StatelessWidget {
  const _TermsBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: SpotColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: SpotSpacing.md),
          Expanded(child: Text(text, style: SpotType.bodySecondary)),
        ],
      ),
    );
  }
}
