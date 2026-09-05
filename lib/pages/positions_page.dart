import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_position.dart';
import '../services/polymarket_positions_api.dart';

/// Shows Polymarket positions for a fixed wallet address.
class PositionsPage extends StatefulWidget {
  const PositionsPage({super.key});

  static const userId = PolymarketPositionsApi.defaultUserId;

  @override
  State<PositionsPage> createState() => _PositionsPageState();
}

class _PositionsPageState extends State<PositionsPage>
    with AutomaticKeepAliveClientMixin {
  final PolymarketPositionsApi _api = PolymarketPositionsApi();
  final NumberFormat _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final NumberFormat _shares = NumberFormat('#,##0.##');
  final NumberFormat _pct = NumberFormat('+0.00%;-0.00%');

  List<UserPosition> _positions = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  DateTime? _lastRefreshedAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent || _positions.isEmpty) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });

    try {
      final positions = await _api.fetchPositions();
      if (!mounted) return;
      setState(() {
        _positions = positions;
        _loading = false;
        _refreshing = false;
        _lastRefreshedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  double get _totalValue =>
      _positions.fold(0.0, (sum, p) => sum + p.currentValue);

  double get _totalPnl => _positions.fold(0.0, (sum, p) => sum + p.cashPnl);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wallet ${PositionsPage.userId}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!_loading && _error == null)
                      Text(
                        '${_positions.length} positions · '
                        '${_money.format(_totalValue)} · '
                        'PnL ${_money.format(_totalPnl)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _totalPnl >= 0
                              ? const Color(0xFF15803D)
                              : const Color(0xFFBE185D),
                        ),
                      ),
                  ],
                ),
              ),
              if (_refreshing || (_loading && _positions.isNotEmpty))
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_lastRefreshedAt != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    DateFormat.Hm().format(_lastRefreshedAt!),
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Open profile on Polymarket',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openUrl(
                  'https://polymarket.com/${PositionsPage.userId}',
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
              ),
              IconButton(
                tooltip: 'Refresh positions',
                visualDensity: VisualDensity.compact,
                onPressed: (_loading || _refreshing) ? null : () => _load(),
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(scheme)),
      ],
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading && _positions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _positions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_positions.isEmpty) {
      return const Center(child: Text('No open positions'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: _positions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final p = _positions[index];
        final pnlColor = p.cashPnl >= 0
            ? const Color(0xFF15803D)
            : const Color(0xFFBE185D);
        return Card(
          child: InkWell(
            onTap: () => _openUrl(p.polymarketEventUrl),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          p.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.open_in_new,
                        size: 14,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _chip(
                        p.outcome,
                        p.outcome.toLowerCase() == 'yes'
                            ? const Color(0xFF15803D)
                            : const Color(0xFFBE185D),
                      ),
                      if (p.redeemable)
                        _chip('Redeemable', const Color(0xFFB45309)),
                      if (p.endDate != null)
                        _chip(p.endDate!, const Color(0xFF7C3AED)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _stat(
                          'Shares',
                          _shares.format(p.size),
                        ),
                      ),
                      Expanded(
                        child: _stat(
                          'Avg',
                          '${(p.avgPrice * 100).toStringAsFixed(1)}¢',
                        ),
                      ),
                      Expanded(
                        child: _stat(
                          'Now',
                          '${(p.curPrice * 100).toStringAsFixed(1)}¢',
                        ),
                      ),
                      Expanded(
                        child: _stat(
                          'Value',
                          _money.format(p.currentValue),
                        ),
                      ),
                      Expanded(
                        child: _stat(
                          'PnL',
                          '${_money.format(p.cashPnl)}\n${_pct.format(p.percentPnl / 100)}',
                          color: pnlColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}
