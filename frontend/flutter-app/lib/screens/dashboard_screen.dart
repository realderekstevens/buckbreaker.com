import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'stock_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _gainers  = [];
  List<Map<String, dynamic>> _losers   = [];
  List<Map<String, dynamic>> _active   = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final svc = context.read<StockService>();
      final results = await Future.wait([
        svc.getMarketSummary(),
        svc.getGainers(limit: 15),
        svc.getLosers(limit: 15),
        svc.getMostActive(limit: 15),
      ]);
      if (mounted) setState(() {
        _summary = results[0] as Map<String, dynamic>?;
        _gainers = results[1] as List<Map<String, dynamic>>;
        _losers  = results[2] as List<Map<String, dynamic>>;
        _active  = results[3] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          if (auth.isLoggedIn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.bg3,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border2),
                ),
                child: Text(auth.email ?? '',
                  style: AppTextStyles.monoSm.copyWith(fontSize: 11)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        backgroundColor: AppColors.panel,
        child: _loading
            ? _buildSkeleton()
            : _error != null
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(height: 400,
                        child: ErrorCard(_error!, onRetry: _load)))
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      // ── Market summary cards ─────────────────────────────────────────────
      if (_summary != null) ...[
        _SectionLabel('Market Snapshot'),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8,
          childAspectRatio: 2.2,
          children: [
            StatTile(
              label: 'Total Symbols',
              value: _summary!['total_symbols']?.toString() ?? '—',
            ),
            StatTile(
              label: 'Advancing',
              value: _summary!['advancing']?.toString() ?? '—',
              valueColor: AppColors.pos,
            ),
            StatTile(
              label: 'Declining',
              value: _summary!['declining']?.toString() ?? '—',
              valueColor: AppColors.neg,
            ),
            StatTile(
              label: 'Avg Change',
              value: fmtPct(_summary!['avg_change_pct']),
              valueColor: chgColor(_summary!['avg_change_pct']),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],

      // ── Top Gainers ──────────────────────────────────────────────────────
      _SectionLabel('Top Gainers 🟢',
          onMore: () => DefaultTabController.of(context).animateTo(1)),
      AppPanel(
        padding: EdgeInsets.zero,
        child: _StockMiniTable(_gainers),
      ),
      const SizedBox(height: 16),

      // ── Top Losers ───────────────────────────────────────────────────────
      _SectionLabel('Top Losers 🔴',
          onMore: () => DefaultTabController.of(context).animateTo(2)),
      AppPanel(
        padding: EdgeInsets.zero,
        child: _StockMiniTable(_losers),
      ),
      const SizedBox(height: 16),

      // ── Most Active ──────────────────────────────────────────────────────
      _SectionLabel('Most Active ⚡'),
      AppPanel(
        padding: EdgeInsets.zero,
        child: _StockMiniTable(_active, showVolume: true),
      ),
      const SizedBox(height: 24),
    ],
  );

  Widget _buildSkeleton() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.2,
        children: List.generate(4, (_) =>
          const SkeletonBox(height: double.infinity, radius: BorderRadius.zero)),
      ),
      const SizedBox(height: 16),
      const SkeletonBox(height: 14, width: 120),
      const SizedBox(height: 8),
      const SkeletonBox(height: 240),
      const SizedBox(height: 16),
      const SkeletonBox(height: 14, width: 120),
      const SizedBox(height: 8),
      const SkeletonBox(height: 240),
    ],
  );
}

// ── Section label with optional 'More' link ────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  final VoidCallback? onMore;
  const _SectionLabel(this.text, {this.onMore});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(text, style: AppTextStyles.title.copyWith(fontSize: 14)),
      if (onMore != null) ...[
        const Spacer(),
        TextButton(onPressed: onMore,
          child: Text('More →',
            style: AppTextStyles.monoSm.copyWith(color: AppColors.accent))),
      ],
    ]),
  );
}

// ── Compact stock list ─────────────────────────────────────────────────────────
class _StockMiniTable extends StatelessWidget {
  final List<Map<String, dynamic>> stocks;
  final bool showVolume;
  const _StockMiniTable(this.stocks, {this.showVolume = false});

  @override
  Widget build(BuildContext context) {
    if (stocks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No data available.',
          style: TextStyle(color: AppColors.text3, fontSize: 13)),
      );
    }
    return Column(
      children: stocks.map((s) => _StockRow(s, showVolume: showVolume)).toList(),
    );
  }
}

class _StockRow extends StatelessWidget {
  final Map<String, dynamic> stock;
  final bool showVolume;
  const _StockRow(this.stock, {this.showVolume = false});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.push(context, MaterialPageRoute(
      builder: (_) => StockDetailScreen(symbol: stock['symbol'] ?? ''),
    )),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(children: [
        // Symbol
        SizedBox(
          width: 68,
          child: Text(stock['symbol'] ?? '',
            style: AppTextStyles.mono.copyWith(fontWeight: FontWeight.w700)),
        ),
        // Price
        Expanded(
          child: Text(fmtPrice(stock['current_stock_price']),
            style: AppTextStyles.monoSm),
        ),
        // Volume (optional)
        if (showVolume)
          Expanded(
            child: Text(fmtVol(stock['volume']),
              style: AppTextStyles.monoSm, textAlign: TextAlign.right),
          ),
        // Change chip
        ChangeChip(stock['performance_today'], showBg: true),
      ]),
    ),
  );
}
