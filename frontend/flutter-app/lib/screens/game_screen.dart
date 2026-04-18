import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

// ── City factoids ──────────────────────────────────────────────────────────────
// Displayed on city cards — historically inspired flavour text
const _cityFacts = <String, String>{
  'Lübeck':      'Queen of the Hanseatic League — controls Baltic trade since 1143. Ships leave daily for Riga, Reval, and Novgorod.',
  'Hamburg':     'Gateway to the North Sea. Famous for herring and cloth. The Elbe makes her the richest inland port in the league.',
  'Riga':        'Easternmost major Hanseatic port. Amber, furs, and Livonian grain flow through her docks year-round.',
  'Gdansk':      'Danzig controls the great Vistula river trade. Grain from Poland piles high on her wharves every harvest.',
  'Reval':       'Tallinn\'s old name. Estonian wool and Russian wax funnel through here before heading west to Bruges.',
  'Novgorod':    'The great Russian trading city. Sable furs, honey, and wax beyond imagination — if you can survive the journey.',
  'Stockholm':   'Swedish iron and copper are among the finest in Europe. The city sits like a crown over the Baltic sea lanes.',
  'Bergen':      'Fish, fish, and more fish. Bergen's dried cod feeds half of Europe. The smell is unforgettable.',
  'London':      'English wool is the finest cloth base in the known world. The Steelyard is the Hanseatic heart of England.',
  'Brugge':      'The cloth capital of the western world. Every colour and weave can be found — for the right price.',
  'Cologne':     'Rhineland wine and metalwork. The cathedral is the tallest structure most merchants will ever see.',
  'Visby':       'Island of Gotland commands the central Baltic. Once the wealthiest city in the league — now faded but still proud.',
  'Malmö':       'Danish herring in abundance. The Sound toll makes every ship passing through pay tribute to the Danish crown.',
  'Oslo':        'Norwegian timber in vast quantities. The dark forests behind the city seem to go on forever.',
  'Rostock':     'A fine Baltic port with excellent shipbuilding yards. Known for quality hulls and reliable craftsmen.',
  'Stettin':     'Controls the Oder river mouth. Pomeranian grain and amber move through her quays in great volume.',
  'Aalborg':     'Danish port controlling the Limfjord passage. Herring and cattle are her main trades.',
  'Ripen':       'Small but ancient Danish trading town. Known for fine leather and steady local demand.',
  'Edinburgh':   'Scottish wool is rough but cheap. Pirates lurk along the northern sea routes — sail with care.',
  'Groningen':   'Inland Frisian city. Good for grain and cloth redistribution into the German hinterlands.',
  'Bremen':      'River city on the Weser. Fish and wool come downriver; manufactured goods go back up.',
  'Torun':       'Polish interior city. Far from the sea but rich in grain. You will need a river boat to reach her.',
  'Ladoga':      'Russian lake city. Furs from the deep forests of Rus arrive here before heading west.',
  'Scarborough': 'English coastal town. Wool and fish, modest volume, but a useful waypoint on the North Sea route.',
};

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic>? _player;
  List<Map<String, dynamic>> _fleet   = [];
  List<Map<String, dynamic>> _cities  = [];
  List<Map<String, dynamic>> _arbView = [];
  List<Map<String, dynamic>> _tradeLog= [];
  bool _loading = true;
  String? _error;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final svc = context.read<GameService>();
      final results = await Future.wait([
        svc.getPlayer(),
        svc.getFleet(),
        svc.getCities(),
        svc.getArbitrage(),
        svc.getTradeLog(limit: 30),
      ]);
      if (mounted) setState(() {
        _player   = results[0] as Map<String, dynamic>?;
        _fleet    = results[1] as List<Map<String, dynamic>>;
        _cities   = results[2] as List<Map<String, dynamic>>;
        _arbView  = results[3] as List<Map<String, dynamic>>;
        _tradeLog = results[4] as List<Map<String, dynamic>>;
        _loading  = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _advanceDay() async {
    setState(() => _advancing = true);
    try {
      await context.read<GameService>().advanceDay();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚓ Day advanced. Year ${_player?['game_year']}, Day ${_player?['game_day']}'),
            backgroundColor: AppColors.panel,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.neg),
        );
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  String get _seasonLabel {
    final day = int.tryParse(_player?['game_day']?.toString() ?? '') ?? 1;
    if (day <= 91)  return 'Winter ❄️';
    if (day <= 182) return 'Spring 🌱';
    if (day <= 273) return 'Summer ☀️';
    return 'Autumn 🍂';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: _player == null
          ? const Text('⚓ Patrician III')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚓ Patrician III', style: TextStyle(fontSize: 16)),
                Text(
                  'Year ${_player!['game_year']} · Day ${_player!['game_day']} · $_seasonLabel',
                  style: AppTextStyles.monoSm.copyWith(fontSize: 11),
                ),
              ],
            ),
      actions: [
        if (_player != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: GoldBadge(_player!['gold']),
          ),
        IconButton(
          icon: _advancing
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: AppColors.accent))
              : const Icon(Icons.skip_next_rounded),
          tooltip: 'Advance 1 Day',
          onPressed: _advancing ? null : _advanceDay,
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: _load,
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : _error != null
            ? ErrorCard(_error!, onRetry: _load)
            : Column(children: [
                // Tab bar
                Container(
                  color: AppColors.bg2,
                  child: TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    labelColor:           AppColors.accent,
                    unselectedLabelColor: AppColors.text3,
                    indicatorColor:       AppColors.accent,
                    dividerColor:         AppColors.border,
                    tabs: const [
                      Tab(text: '🏙 Cities'),
                      Tab(text: '⛵ Fleet'),
                      Tab(text: '📊 Arbitrage'),
                      Tab(text: '📜 Log'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildCities(),
                      _buildFleet(),
                      _buildArbitrage(),
                      _buildTradeLog(),
                    ],
                  ),
                ),
              ]),
  );

  // ── Cities tab ───────────────────────────────────────────────────────────────
  Widget _buildCities() => RefreshIndicator(
    onRefresh: _load,
    color: AppColors.accent,
    backgroundColor: AppColors.panel,
    child: ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _cities.length,
      itemBuilder: (ctx, i) {
        final city = _cities[i];
        final name = city['name'] as String? ?? '';
        final fact = _cityFacts[name] ?? 'A Hanseatic trading city on the Baltic route.';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _showCityDetail(city),
            child: Container(
              decoration: BoxDecoration(
                color:        AppColors.panel,
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(name, style: AppTextStyles.title),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color:        AppColors.sea.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                        border:       Border.all(color: AppColors.sea),
                      ),
                      child: Text(
                        city['region'] as String? ?? '',
                        style: AppTextStyles.monoSm.copyWith(
                            color: AppColors.sea, fontSize: 10),
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.text3, size: 18),
                  ]),
                  const SizedBox(height: 6),
                  Text(fact,
                    style: AppTextStyles.monoSm.copyWith(
                        color: AppColors.text2, height: 1.5),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.people_outline,
                        color: AppColors.text3, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      fmtVol(city['population']),
                      style: AppTextStyles.monoSm.copyWith(fontSize: 11),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Future<void> _showCityDetail(Map<String, dynamic> city) async {
    final name    = city['name'] as String? ?? '';
    final svc     = context.read<GameService>();
    List<Map<String, dynamic>> market = [];
    try { market = await svc.getMarket(name); } catch (_) {}

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, ctrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ListView(controller: ctrl, children: [
            Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(name, style: AppTextStyles.headline),
            const SizedBox(height: 4),
            Text(_cityFacts[name] ?? '',
              style: AppTextStyles.monoSm.copyWith(
                  color: AppColors.text2, height: 1.5)),
            const SizedBox(height: 16),
            Text('MARKET', style: AppTextStyles.label),
            const SizedBox(height: 8),
            if (market.isEmpty)
              const Text('No market data.',
                  style: TextStyle(color: AppColors.text3, fontSize: 13))
            else
              AppDataTable(
                headers: const ['Good', 'Buy', 'Sell', 'Stock'],
                flex:    const [1.5, 1.0, 1.0, 1.0],
                rows: market.map((m) => [
                  Text(m['good'] as String? ?? '',
                      style: AppTextStyles.monoSm.copyWith(fontWeight: FontWeight.w600)),
                  Text(fmtPrice(m['current_buy']),  style: AppTextStyles.monoSm),
                  Text(fmtPrice(m['current_sell']), style: AppTextStyles.monoSm),
                  Text(m['stock']?.toString() ?? '—', style: AppTextStyles.monoSm),
                ]).toList(),
              ),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  // ── Fleet tab ────────────────────────────────────────────────────────────────
  Widget _buildFleet() => _fleet.isEmpty
      ? const Center(child: Text('No ships found.',
          style: TextStyle(color: AppColors.text3)))
      : ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: _fleet.length,
          itemBuilder: (ctx, i) {
            final ship     = _fleet[i];
            final status   = ship['status'] as String? ?? 'docked';
            final etaDays  = ship['eta_days'] as int? ?? 0;
            final isSailing = status == 'sailing';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color:  AppColors.panel,
                  border: Border.all(
                    color: isSailing ? AppColors.accent.withOpacity(0.5) : AppColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(ship['name'] as String? ?? '',
                        style: AppTextStyles.title),
                      const SizedBox(width: 8),
                      Text(ship['ship_type'] as String? ?? '',
                        style: AppTextStyles.monoSm.copyWith(
                            color: AppColors.text3, fontSize: 11)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSailing
                              ? AppColors.accent.withOpacity(0.15)
                              : AppColors.pos.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: isSailing ? AppColors.accent : AppColors.pos),
                        ),
                        child: Text(
                          isSailing ? '⛵ Sailing' : '🚢 Docked',
                          style: AppTextStyles.monoSm.copyWith(
                            color: isSailing ? AppColors.accent : AppColors.pos,
                            fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      _shipStat('Location',
                        isSailing
                          ? '${ship['destination'] ?? '?'}  (${etaDays}d)'
                          : ship['current_city'] as String? ?? ''),
                      const SizedBox(width: 24),
                      _shipStat('Cargo',
                        '${ship['cargo_used'] ?? 0} / ${ship['cargo_cap'] ?? 0}'),
                    ]),
                    // Cargo progress bar
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (ship['cargo_cap'] ?? 0) > 0
                            ? (ship['cargo_used'] ?? 0) /
                              (ship['cargo_cap'] as num).toDouble()
                            : 0,
                        backgroundColor: AppColors.bg3,
                        color:           AppColors.accent,
                        minHeight:       4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

  Widget _shipStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTextStyles.label),
      const SizedBox(height: 2),
      Text(value,
        style: AppTextStyles.monoSm.copyWith(color: AppColors.text)),
    ],
  );

  // ── Arbitrage tab ────────────────────────────────────────────────────────────
  Widget _buildArbitrage() => _arbView.isEmpty
      ? const Center(child: Text('No arbitrage data available.',
          style: TextStyle(color: AppColors.text3)))
      : ListView(
          padding: const EdgeInsets.all(10),
          children: [
            AppPanel(
              title: 'Best Profit Opportunities',
              padding: EdgeInsets.zero,
              child: AppDataTable(
                headers: const ['Good', 'Buy At', 'Sell At', 'Profit/u'],
                flex:    const [1.2, 1.0, 1.0, 1.0],
                rows: _arbView.map((a) => [
                  Text(a['good'] as String? ?? '',
                    style: AppTextStyles.monoSm.copyWith(fontWeight: FontWeight.w600)),
                  Text('${a['buy_city'] ?? '?'}\n${fmtPrice(a['buy_price'])}',
                    style: AppTextStyles.monoSm),
                  Text('${a['sell_city'] ?? '?'}\n${fmtPrice(a['sell_price'])}',
                    style: AppTextStyles.monoSm),
                  Text(fmtPrice(a['profit_per_unit']),
                    style: AppTextStyles.monoSm.copyWith(color: AppColors.pos)),
                ]).toList(),
              ),
            ),
          ],
        );

  // ── Trade log tab ─────────────────────────────────────────────────────────────
  Widget _buildTradeLog() => _tradeLog.isEmpty
      ? const Center(child: Text('No trade history yet.',
          style: TextStyle(color: AppColors.text3)))
      : ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: _tradeLog.length,
          itemBuilder: (ctx, i) {
            final t      = _tradeLog[i];
            final action = t['action'] as String? ?? '';
            final isBuy  = action == 'buy';
            final isSell = action == 'sell';
            final color  = isBuy  ? AppColors.neg
                          : isSell ? AppColors.pos
                          : AppColors.text3;
            final icon   = isBuy  ? Icons.shopping_cart_outlined
                          : isSell ? Icons.sell_outlined
                          : Icons.anchor_rounded;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                decoration: BoxDecoration(
                  color:  AppColors.panel,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${action.toUpperCase()}  ${t['good_name'] ?? ''}  ×${t['quantity'] ?? ''}',
                        style: AppTextStyles.monoSm.copyWith(
                            color: AppColors.text, fontWeight: FontWeight.w600)),
                      Text(
                        '${t['city'] ?? ''}  ·  Y${t['game_year']} D${t['game_day']}',
                        style: AppTextStyles.monoSm),
                    ],
                  )),
                  Text(fmtPrice(t['total_value']),
                    style: AppTextStyles.monoSm.copyWith(color: color)),
                ]),
              ),
            );
          },
        );
}
