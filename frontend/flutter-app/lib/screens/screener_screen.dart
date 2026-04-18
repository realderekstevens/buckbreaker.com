import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'stock_detail_screen.dart';

class ScreenerScreen extends StatefulWidget {
  const ScreenerScreen({super.key});
  @override
  State<ScreenerScreen> createState() => _ScreenerScreenState();
}

class _ScreenerScreenState extends State<ScreenerScreen> {
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  int  _total   = 0;
  String? _error;

  // Filter state
  String _mcap   = '';
  String _pe     = '';
  String _rsi    = '';
  String _perf   = '';
  String _div    = '';
  String _order  = 'market_capitalization.desc';

  Future<void> _runScreen() async {
    setState(() { _loading = true; _error = null; });
    try {
      final filters = <String, String>{
        'current_stock_price': 'not.is.null',
        if (_mcap.isNotEmpty) 'market_capitalization': _mcap,
        if (_pe.isNotEmpty)   'price_to_earnings_ttm': _pe,
        if (_rsi.isNotEmpty)  'relative_strength_index_14': _rsi,
        if (_perf.isNotEmpty) 'performance_today': _perf,
        if (_div.isNotEmpty)  'dividend_yield_annual_percentage': _div,
      };
      final r = await context.read<StockService>().getLatestQuotes(
        limit: 100, filters: filters, order: _order,
      );
      setState(() {
        _results = r;
        _total   = r.length;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stock Screener')),
    body: Column(children: [
      // ── Filter strip ──────────────────────────────────────────────────────
      Container(
        color: AppColors.bg2,
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            Expanded(child: _dropdown('Market Cap', _mcap, const {
              '': 'Any',
              'gte.1000000000000': 'Mega (>1T)',
              'gte.10000000000':   'Large (>10B)',
              'gte.2000000000':    'Mid (>2B)',
              'lt.2000000000':     'Small (<2B)',
            }, (v) => setState(() => _mcap = v))),
            const SizedBox(width: 8),
            Expanded(child: _dropdown('P/E', _pe, const {
              '': 'Any',
              'lte.10':  '<10',
              'lte.20':  '<20',
              'lte.30':  '<30',
              'gte.30':  '>30',
            }, (v) => setState(() => _pe = v))),
            const SizedBox(width: 8),
            Expanded(child: _dropdown('RSI', _rsi, const {
              '': 'Any',
              'lte.30': 'Oversold',
              'gte.70': 'Overbought',
              'gte.50': 'Bullish',
            }, (v) => setState(() => _rsi = v))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _dropdown('Today %', _perf, const {
              '': 'Any',
              'gte.0':  'Positive',
              'gte.3':  'Up 3%+',
              'gte.5':  'Up 5%+',
              'lte.0':  'Negative',
              'lte.-5': 'Down 5%+',
            }, (v) => setState(() => _perf = v))),
            const SizedBox(width: 8),
            Expanded(child: _dropdown('Dividend', _div, const {
              '': 'Any',
              'gte.1': 'Pays dividend',
              'gte.3': 'High yield >3%',
              'gte.5': 'Very high >5%',
            }, (v) => setState(() => _div = v))),
            const SizedBox(width: 8),
            Expanded(child: _dropdown('Sort', _order, const {
              'market_capitalization.desc': 'Mkt Cap ↓',
              'performance_today.desc':     '% Today ↓',
              'performance_today.asc':      '% Today ↑',
              'volume.desc':                'Volume ↓',
              'price_to_earnings_ttm.asc':  'P/E ↑',
              'dividend_yield_annual_percentage.desc': 'Div % ↓',
            }, (v) => setState(() => _order = v))),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _runScreen,
              icon: _loading
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.search_rounded, size: 18),
              label: Text(_loading ? 'Searching…' : 'Run Screen'),
            ),
          ),
        ]),
      ),

      // Result count
      if (_total > 0)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('$_total results',
              style: AppTextStyles.monoSm.copyWith(color: AppColors.text3)),
          ),
        ),

      // ── Results ───────────────────────────────────────────────────────────
      Expanded(
        child: _error != null
            ? ErrorCard(_error!, onRetry: _runScreen)
            : _results.isEmpty && !_loading
                ? const Center(
                    child: Text('Set filters above and tap Run Screen.',
                      style: TextStyle(color: AppColors.text3)))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) {
                      final s = _results[i];
                      return InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => StockDetailScreen(
                              symbol: s['symbol'] ?? ''),
                        )),
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: AppColors.border, width: 0.5)),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          child: Row(children: [
                            SizedBox(width: 68,
                              child: Text(s['symbol'] ?? '',
                                style: AppTextStyles.mono.copyWith(
                                    fontWeight: FontWeight.w700))),
                            Expanded(child: Text(
                              fmtPrice(s['current_stock_price']),
                              style: AppTextStyles.monoSm)),
                            const SizedBox(width: 8),
                            Text(fmtMcap(s['market_capitalization']),
                              style: AppTextStyles.monoSm.copyWith(
                                  color: AppColors.text3, fontSize: 11)),
                            const SizedBox(width: 12),
                            ChangeChip(s['performance_today'], showBg: true),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]),
  );

  Widget _dropdown(String label, String value, Map<String, String> items,
      ValueChanged<String> onChange) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: AppTextStyles.label),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        dropdownColor: AppColors.panel,
        style: AppTextStyles.monoSm.copyWith(color: AppColors.text),
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          isDense: true,
        ),
        items: items.entries.map((e) => DropdownMenuItem(
          value: e.key,
          child: Text(e.value,
            style: AppTextStyles.monoSm.copyWith(
                color: AppColors.text, fontSize: 12),
            overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: (v) { if (v != null) onChange(v); },
      ),
    ],
  );
}
