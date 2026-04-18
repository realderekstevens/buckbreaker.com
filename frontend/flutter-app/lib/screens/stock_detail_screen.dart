import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;
  const StockDetailScreen({super.key, required this.symbol});
  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic>? _stock;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final svc = context.read<StockService>();
      final results = await Future.wait([
        svc.getStock(widget.symbol),
        svc.getHistory(widget.symbol, limit: 30),
      ]);
      if (mounted) setState(() {
        _stock   = results[0] as Map<String, dynamic>?;
        _history = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.symbol,
        style: AppTextStyles.headline.copyWith(fontSize: 18)),
      actions: [
        IconButton(icon: const Icon(Icons.refresh_rounded, size: 20), onPressed: _load),
      ],
    ),
    body: _loading
        ? _buildSkeleton()
        : _error != null
            ? ErrorCard(_error!, onRetry: _load)
            : _stock == null
                ? const ErrorCard('Symbol not found in database.')
                : _buildBody(),
  );

  Widget _buildBody() {
    final s = _stock!;
    final chg = double.tryParse(s['performance_today']?.toString() ?? '') ?? 0.0;

    return Column(children: [
      // ── Price header ────────────────────────────────────────────────────
      Container(
        decoration: const BoxDecoration(
          gradient: AppColors.headerGradient,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['symbol'] ?? '',
                  style: AppTextStyles.headline.copyWith(fontSize: 26)),
                const SizedBox(height: 4),
                Text(s['major_index_membership'] ?? '',
                  style: AppTextStyles.monoSm),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fmtPrice(s['current_stock_price']),
                  style: AppTextStyles.priceLg),
                const SizedBox(height: 4),
                ChangeChip(s['performance_today'], showBg: true),
              ],
            ),
          ],
        ),
      ),

      // ── Tabs ─────────────────────────────────────────────────────────────
      Container(
        color: AppColors.bg2,
        child: TabBar(
          controller: _tabs,
          labelColor:          AppColors.accent,
          unselectedLabelColor:AppColors.text3,
          indicatorColor:      AppColors.accent,
          dividerColor:        AppColors.border,
          tabs: const [
            Tab(text: 'Fundamentals'),
            Tab(text: 'Performance'),
            Tab(text: 'History'),
          ],
        ),
      ),

      // ── Tab content ───────────────────────────────────────────────────────
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _buildFundamentals(s),
            _buildPerformance(s),
            _buildHistory(),
          ],
        ),
      ),
    ]);
  }

  Widget _buildFundamentals(Map<String, dynamic> s) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      // Key metrics grid
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.0,
        children: [
          StatTile(label: 'Market Cap',  value: fmtMcap(s['market_capitalization'])),
          StatTile(label: 'P/E (TTM)',   value: fmtNum(s['price_to_earnings_ttm'])),
          StatTile(label: 'Forward P/E', value: fmtNum(s['forward_price_to_earnings_next_fiscal_year'])),
          StatTile(label: 'EPS (TTM)',   value: fmtPrice(s['diluted_earnings_per_share_ttm'])),
          StatTile(label: 'Revenue',     value: fmtMcap(s['revenue_ttm'])),
          StatTile(label: 'Gross Mgn',   value: fmtPct(s['gross_margin_ttm']),
              valueColor: chgColor(s['gross_margin_ttm'])),
          StatTile(label: 'Net Margin',  value: fmtPct(s['net_profit_margin_ttm']),
              valueColor: chgColor(s['net_profit_margin_ttm'])),
          StatTile(label: 'ROE',         value: fmtPct(s['return_on_equity']),
              valueColor: chgColor(s['return_on_equity'])),
        ],
      ),
      const SizedBox(height: 12),

      // Technical panel
      AppPanel(title: 'Technical', child: Column(children: [
        _fundRow('RSI (14)',     fmtNum(s['relative_strength_index_14'], decimals: 1)),
        _fundRow('Beta',         fmtNum(s['beta'])),
        _fundRow('ATR (14)',     fmtNum(s['average_true_range_14'])),
        _fundRow('Rel Volume',   '${fmtNum(s['relative_volume'])}x'),
        _fundRow('52W High Δ',  s['distance_from_52_week_high'] ?? '—'),
        _fundRow('52W Low Δ',   s['distance_from_52_week_low'] ?? '—'),
        _fundRow('SMA 20',      s['distance_from_20_day_simple_moving_average'] ?? '—'),
        _fundRow('SMA 50',      s['distance_from_50_day_simple_moving_average'] ?? '—'),
        _fundRow('SMA 200',     s['distance_from_200_day_simple_moving_average'] ?? '—'),
      ])),
      const SizedBox(height: 12),

      // Analyst panel
      AppPanel(title: 'Analyst & Ownership', child: Column(children: [
        _fundRow('Analyst Target', fmtPrice(s['analyst_mean_price'])),
        _fundRow('Analyst Rating', fmtNum(s['analyst_mean_recommendation_1_buy_5_sell'])),
        _fundRow('Insider Own',    s['insider_ownership'] ?? '—'),
        _fundRow('Inst Own',       s['institutional_ownership'] ?? '—'),
        _fundRow('Short Float',    s['short_interest_share'] ?? '—'),
        _fundRow('Dividend %',     fmtPct(s['dividend_yield_annual_percentage'])),
        _fundRow('Earnings Date',  s['earnings_date'] ?? '—'),
        _fundRow('Employees',      fmtVol(s['full_time_employees'])),
      ])),
      const SizedBox(height: 24),
    ],
  );

  Widget _buildPerformance(Map<String, dynamic> s) {
    final periods = [
      ('Today',   s['performance_today']),
      ('Week',    s['performance_week']),
      ('Month',   s['performance_month']),
      ('Quarter', s['performance_quarter']),
      ('6 Month', s['performance_half_year']),
      ('YTD',     s['performance_year_to_date']),
      ('1 Year',  s['performance_year']),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AppPanel(
          title: 'Price Performance',
          child: Column(children: periods.map((p) {
            final n = double.tryParse(p.$2?.toString() ?? '') ?? 0.0;
            final color = n >= 0 ? AppColors.pos : AppColors.neg;
            final barW  = (n.abs().clamp(0.0, 25.0) / 25.0);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(width: 70,
                  child: Text(p.$1, style: AppTextStyles.monoSm)),
                Expanded(
                  child: LayoutBuilder(builder: (ctx, c) => Stack(
                    children: [
                      Container(height: 4, color: AppColors.border,
                          width: c.maxWidth),
                      Container(height: 4, color: color,
                          width: c.maxWidth * barW),
                    ],
                  )),
                ),
                const SizedBox(width: 12),
                SizedBox(width: 70,
                  child: ChangeChip(p.$2)),
              ]),
            );
          }).toList()),
        ),
        const SizedBox(height: 12),
        AppPanel(title: 'Volume', child: Column(children: [
          _fundRow('Volume',        fmtVol(s['volume'])),
          _fundRow('Avg Vol (3M)',  fmtVol(s['average_volume_3_month'])),
          _fundRow('Rel Volume',    '${fmtNum(s['relative_volume'])}x'),
        ])),
      ],
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Center(child: Text('No history available.',
          style: TextStyle(color: AppColors.text3)));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AppPanel(
          padding: EdgeInsets.zero,
          child: AppDataTable(
            headers: const ['Date', 'Price', '% Chg', 'Volume', 'RSI'],
            flex:    const [1.5, 1.0, 1.0, 1.2, 0.8],
            rows: _history.map((h) => [
              Text(h['time_recorded']?.toString().substring(0, 10) ?? '—',
                style: AppTextStyles.monoSm),
              Text(fmtPrice(h['current_stock_price']),
                style: AppTextStyles.monoSm),
              ChangeChip(h['performance_today']),
              Text(fmtVol(h['volume']), style: AppTextStyles.monoSm),
              Text(fmtNum(h['relative_strength_index_14'], decimals: 1),
                style: AppTextStyles.monoSm),
            ]).toList(),
          ),
        ),
      ],
    );
  }

  Widget _fundRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Text(label, style: AppTextStyles.monoSm),
      const Spacer(),
      Text(value, style: AppTextStyles.monoSm.copyWith(color: AppColors.text)),
    ]),
  );

  Widget _buildSkeleton() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      const SkeletonBox(height: 80),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.0,
        children: List.generate(8, (_) => const SkeletonBox(height: double.infinity)),
      ),
    ],
  );
}
