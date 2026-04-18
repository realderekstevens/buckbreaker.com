import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

// ── Formatting helpers ─────────────────────────────────────────────────────────
String fmtPrice(dynamic v) {
  if (v == null) return '—';
  final n = double.tryParse(v.toString());
  if (n == null) return v.toString();
  return '\$${n.toStringAsFixed(2)}';
}

String fmtPct(dynamic v) {
  if (v == null) return '—';
  final n = double.tryParse(v.toString().replaceAll('%', ''));
  if (n == null) return v.toString();
  return '${n >= 0 ? '+' : ''}${n.toStringAsFixed(2)}%';
}

String fmtVol(dynamic v) {
  if (v == null) return '—';
  final n = double.tryParse(v.toString());
  if (n == null) return v.toString();
  if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(2)}B';
  if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(2)}M';
  if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
  return n.toStringAsFixed(0);
}

String fmtMcap(dynamic v) => fmtVol(v);

String fmtNum(dynamic v, {int decimals = 2}) {
  if (v == null) return '—';
  final n = double.tryParse(v.toString());
  return n?.toStringAsFixed(decimals) ?? v.toString();
}

Color chgColor(dynamic v) {
  final n = double.tryParse(v?.toString() ?? '');
  if (n == null) return AppColors.text2;
  return n >= 0 ? AppColors.pos : AppColors.neg;
}

// ── AppPanel ───────────────────────────────────────────────────────────────────
class AppPanel extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets? padding;

  const AppPanel({
    super.key, required this.child,
    this.title, this.trailing, this.padding,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color:        AppColors.panel,
      borderRadius: BorderRadius.circular(10),
      border:       Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(children: [
              Text(title!.toUpperCase(),
                style: AppTextStyles.label.copyWith(
                  color: AppColors.text3, letterSpacing: 1.0)),
              if (trailing != null) ...[const Spacer(), trailing!],
            ]),
          ),
        Padding(
          padding: padding ?? const EdgeInsets.all(14),
          child: child,
        ),
      ],
    ),
  );
}

// ── StatTile ───────────────────────────────────────────────────────────────────
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final String? sub;

  const StatTile({
    super.key, required this.label, required this.value,
    this.valueColor, this.sub,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color:        AppColors.bg3,
      borderRadius: BorderRadius.circular(8),
      border:       Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTextStyles.label),
        const SizedBox(height: 4),
        Text(value,
          style: AppTextStyles.mono.copyWith(
            fontSize: 18, fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.text,
          )),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub!, style: AppTextStyles.monoSm),
        ],
      ],
    ),
  );
}

// ── ChangeChip ─────────────────────────────────────────────────────────────────
class ChangeChip extends StatelessWidget {
  final dynamic value;
  final bool showBg;
  const ChangeChip(this.value, {super.key, this.showBg = false});

  @override
  Widget build(BuildContext context) {
    final n    = double.tryParse(value?.toString() ?? '');
    final color = chgColor(value);
    final text  = fmtPct(value);
    if (showBg) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(5),
          border:       Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(text, style: AppTextStyles.monoSm.copyWith(color: color, fontWeight: FontWeight.w700)),
      );
    }
    return Text(text, style: AppTextStyles.monoSm.copyWith(color: color, fontWeight: FontWeight.w600));
  }
}

// ── DataRow / Table ────────────────────────────────────────────────────────────
class AppDataTable extends StatelessWidget {
  final List<String> headers;
  final List<List<Widget>> rows;
  final List<double>? flex;

  const AppDataTable({
    super.key, required this.headers, required this.rows, this.flex,
  });

  @override
  Widget build(BuildContext context) {
    final f = flex ?? List.filled(headers.length, 1.0);
    return Column(
      children: [
        // Header row
        Container(
          color: AppColors.bg3,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: List.generate(headers.length, (i) => Expanded(
              flex: (f[i] * 10).round(),
              child: Text(headers[i].toUpperCase(),
                style: AppTextStyles.label,
                textAlign: i == 0 ? TextAlign.left : TextAlign.right),
            )),
          ),
        ),
        // Data rows
        ...rows.asMap().entries.map((e) => Container(
          decoration: BoxDecoration(
            color: e.key.isEven ? Colors.transparent : AppColors.bg3.withOpacity(0.3),
            border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: List.generate(e.value.length, (i) => Expanded(
              flex: (f[i] * 10).round(),
              child: Align(
                alignment: i == 0 ? Alignment.centerLeft : Alignment.centerRight,
                child: e.value[i],
              ),
            )),
          ),
        )),
      ],
    );
  }
}

// ── Loading skeleton ───────────────────────────────────────────────────────────
class SkeletonBox extends StatelessWidget {
  final double height;
  final double? width;
  final BorderRadius? radius;

  const SkeletonBox({
    super.key, this.height = 16, this.width, this.radius,
  });

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor:      AppColors.bg3,
    highlightColor: AppColors.border2,
    child: Container(
      height:          height,
      width:           width,
      decoration: BoxDecoration(
        color:        AppColors.bg3,
        borderRadius: radius ?? BorderRadius.circular(6),
      ),
    ),
  );
}

class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(count, (i) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        SkeletonBox(height: 14, width: 60, radius: BorderRadius.circular(4)),
        const SizedBox(width: 12),
        Expanded(child: SkeletonBox(height: 14)),
        const SizedBox(width: 12),
        SkeletonBox(height: 14, width: 50),
      ]),
    )),
  );
}

// ── Error widget ───────────────────────────────────────────────────────────────
class ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorCard(this.message, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi_off_rounded, color: AppColors.neg, size: 40),
        const SizedBox(height: 12),
        Text(message,
          textAlign: TextAlign.center,
          style: AppTextStyles.mono.copyWith(color: AppColors.text2, fontSize: 13)),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ]),
    ),
  );
}

// ── Gold display (Patrician game) ──────────────────────────────────────────────
class GoldBadge extends StatelessWidget {
  final dynamic amount;
  const GoldBadge(this.amount, {super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.monetization_on_rounded, color: AppColors.gold, size: 16),
      const SizedBox(width: 4),
      Text(fmtVol(amount),
        style: AppTextStyles.mono.copyWith(
          color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 15)),
    ],
  );
}
