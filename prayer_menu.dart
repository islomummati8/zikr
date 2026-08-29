import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrayerSectionPage extends StatefulWidget {
  final String title;
  final List<String> submenus;
  final Locale locale;

  const PrayerSectionPage({super.key, required this.title, required this.submenus, required this.locale});

  @override
  State<PrayerSectionPage> createState() => _PrayerSectionPageState();
}

class _PrayerSectionPageState extends State<PrayerSectionPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F6F67),
        foregroundColor: Colors.white,
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: Text(widget.title),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.submenus.length,
        itemBuilder: (context, index) {
          final s = widget.submenus[index];
          final key = s.toLowerCase();
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE8F6F3),
                child: Icon(
                  key.contains('zikr') || key.contains('tasbih')
                      ? Icons.self_improvement_rounded
                      : key.contains('suggest') || key.contains('추천') || key.contains('предл')
                          ? Icons.lightbulb_rounded
                          : key.contains('edit') || key.contains('interval') || key.contains('ред')
                              ? Icons.schedule_rounded
                              : Icons.mosque_rounded,
                  color: const Color(0xFF1F6F67),
                ),
              ),
              title: Text(s, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                if (key.contains('24') || key.contains('24h') || key.contains('analytics') || key.contains('анали')) {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => TimeSpent24Page(locale: widget.locale)));
                } else if (key.contains('suggest') || key.contains('предл') || key.contains('рекоменд')) {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => TimeSpentSuggestionsPage(locale: widget.locale)));
                } else if (key.contains('edit') || key.contains('interval') || key.contains('ред') || key.contains('время')) {
                  final changed = await Navigator.push(context, MaterialPageRoute(builder: (_) => TimeSpentEditIntervalsPage(locale: widget.locale)));
                  if (changed == true && mounted) setState(() {});
                } else if (key.contains('zikr') || key.contains('tasbih') || key.contains('азкар') || key.contains('зикр')) {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => DhikrPage(locale: widget.locale)));
                } else {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => _PrayerSubPage(title: s, locale: widget.locale)));
                }
                if (mounted) setState(() {});
              },
            ),
          );
        },
      ),
    );
  }
}

class _PrayerSubPage extends StatelessWidget {
  final String title;
  final Locale locale;
  const _PrayerSubPage({required this.title, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => Navigator.pop(context)), title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            locale.languageCode == 'en' ? '$title (Coming soon)' : '$title (скоро)',
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}

class TimeSpent24Page extends StatefulWidget {
  final Locale locale;
  const TimeSpent24Page({super.key, required this.locale});

  @override
  State<TimeSpent24Page> createState() => _TimeSpent24PageState();
}

class _TimeSpent24PageState extends State<TimeSpent24Page> {
  Map<String, int> _minutesByPrayer = {};
  Map<String, int> _koshish = {};
  bool _loading = true;

  final List<String> _prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadLast24Hours(), _loadKoshish()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLast24Hours() async {
    final prefs = await SharedPreferences.getInstance();
    final rec = prefs.getString('prayer_records');
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    final Map<String, int> agg = {};

    if (rec != null) {
      try {
        final Map m = jsonDecode(rec);
        m.forEach((date, v) {
          try {
            final Map day = v as Map;
            day.forEach((pname, pentry) {
              try {
                final Map entry = pentry as Map;
                final ts = (entry['timestamp'] is num) ? (entry['timestamp'] as num).toInt() : null;
                final minutes = (entry['timeMinutes'] is num) ? (entry['timeMinutes'] as num).toInt() : (entry['time'] is int ? entry['time'] as int : 0);
                if (ts != null && ts >= cutoff) {
                  agg[pname] = (agg[pname] ?? 0) + minutes;
                }
              } catch (_) {}
            });
          } catch (_) {}
        });
      } catch (_) {}
    }

    _minutesByPrayer = agg;
  }

  Future<void> _loadKoshish() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('koshish_attempts');
    final Map<String, int> m = {};
    if (s != null) {
      try {
        final Map mm = jsonDecode(s);
        mm.forEach((k, v) => m[k.toString()] = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0);
      } catch (_) {}
    }
    _koshish = m;
  }

  Future<void> _saveKoshish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('koshish_attempts', jsonEncode(_koshish));
  }

  void _incAttempt(String prayer) {
    _koshish[prayer] = (_koshish[prayer] ?? 0) + 1;
    _saveKoshish();
    if (mounted) setState(() {});
  }

  void _resetAttempt(String prayer) {
    _koshish[prayer] = 0;
    _saveKoshish();
    if (mounted) setState(() {});
  }

  List<BarChartGroupData> _buildBarGroups() {
    return _prayers.asMap().entries.map((entry) {
      final prayer = entry.value;
      final index = entry.key;
      final mins = (_minutesByPrayer[prayer] ?? 0).toDouble();
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: mins,
            gradient: const LinearGradient(
              colors: [Color(0xFF1F6F67), Color(0xFF7FB7AE)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 18,
            borderRadius: BorderRadius.circular(8),
          ),
        ],
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final total = _minutesByPrayer.values.fold<int>(0, (s, v) => s + v);
    final avg = _prayers.isEmpty ? 0 : (total / _prayers.length).round();
    final topPrayer = _prayers.fold<String>('Fajr', (best, prayer) {
      final current = _minutesByPrayer[prayer] ?? 0;
      final bestValue = _minutesByPrayer[best] ?? 0;
      return current > bestValue ? prayer : best;
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F6F67),
        foregroundColor: Colors.white,
        title: Text(widget.locale.languageCode == 'en' ? '24h analytics' : 'Аналитика 24ч'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1F6F67), Color(0xFF7FB7AE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.show_chart_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.locale.languageCode == 'en' ? 'Last 24 hours' : 'Последние 24 часа',
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$total min',
                                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: widget.locale.languageCode == 'en' ? 'Average' : 'Среднее',
                          value: '$avg min',
                          color: const Color(0xFF7FB7AE),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatTile(
                          label: widget.locale.languageCode == 'en' ? 'Focus' : 'Акцент',
                          value: topPrayer,
                          color: const Color(0xFFE8B36A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.locale.languageCode == 'en' ? 'Prayer time distribution' : 'Распределение времени',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 220,
                            child: BarChart(
                              BarChartData(
                                maxY: [_minutesByPrayer.values.fold<int>(0, (p, c) => p > c ? p : c).toDouble(), 30.0].reduce((a, b) => a > b ? a : b),
                                borderData: FlBorderData(show: false),
                                gridData: FlGridData(show: false),
                                barGroups: _buildBarGroups(),
                                alignment: BarChartAlignment.spaceAround,
                                titlesData: FlTitlesData(
                                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                     reservedSize: 30,
                                      getTitlesWidget: (value, meta) {
                                        final index = value.toInt();
                                        if (index < 0 || index >= _prayers.length) return const SizedBox();
                                        final prayer = _prayers[index];
                                        // Use FittedBox to avoid vertical stacking on narrow screens and ellipsize if needed
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: SizedBox(
                                            height: 28,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                prayer,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._prayers.map((prayer) {
                    final mins = _minutesByPrayer[prayer] ?? 0;
                    final percent = (mins / (total == 0 ? 1 : total)).clamp(0.0, 1.0);
                    final attempts = _koshish[prayer] ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFFE8F6F3),
                                  child: const Icon(Icons.access_time, color: Color(0xFF1F6F67), size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(prayer, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                                Text('$mins min', style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: percent,
                                minHeight: 10,
                                backgroundColor: const Color(0xFFF1F5F4),
                                color: const Color(0xFF7FB7AE),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  widget.locale.languageCode == 'en' ? 'Attempts' : 'Кошиш',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                Row(
                                  children: [
                                    IconButton(onPressed: () => _resetAttempt(prayer), icon: const Icon(Icons.restart_alt_rounded, size: 18)),
                                    Text('$attempts', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: () => _incAttempt(prayer),
                                      icon: const Icon(Icons.add),
                                      label: Text(widget.locale.languageCode == 'en' ? 'Try' : 'Кошиш'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1F6F67),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87)),
        ],
      ),
    );
  }
}

class TimeSpentSuggestionsPage extends StatefulWidget {
  final Locale locale;
  const TimeSpentSuggestionsPage({super.key, required this.locale});

  @override
  State<TimeSpentSuggestionsPage> createState() => _TimeSpentSuggestionsPageState();
}

class _TimeSpentSuggestionsPageState extends State<TimeSpentSuggestionsPage> {
  Map<String, int> _timeSpent = {};
  Map<String, int> _koshish = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadTotals(), _loadKoshish()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadTotals() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString('time_spent');
    final Map<String, int> totals = {};
    if (t != null) {
      try {
        final Map m = jsonDecode(t);
        m.forEach((k, v) { totals[k.toString()] = (v is num) ? v.toInt() : 0; });
      } catch (_) {}
    }
    _timeSpent = totals;
  }

  Future<void> _loadKoshish() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('koshish_attempts');
    final Map<String, int> m = {};
    if (s != null) {
      try {
        final Map mm = jsonDecode(s);
        mm.forEach((k, v) => m[k.toString()] = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0);
      } catch (_) {}
    }
    _koshish = m;
  }

  Future<void> _applyQuickSuggestion(String prayer) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
    final p = prefs.getString('planned_$dateKey');
    Map<String, dynamic> planned = {};
    if (p != null) {
      try { planned = jsonDecode(p) as Map<String, dynamic>; } catch (_) {}
    }
    planned[prayer] = (planned[prayer] ?? 0) + 5;
    await prefs.setString('planned_$dateKey', jsonEncode(planned));
    _koshish[prayer] = (_koshish[prayer] ?? 0) + 1;
    await prefs.setString('koshish_attempts', jsonEncode(_koshish));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.locale.languageCode == 'en' ? 'Planned 5 min for $prayer' : 'Запланировано 5 минут для $prayer')));
  }

  @override
  Widget build(BuildContext context) {
    final low = _timeSpent.entries.where((e) => e.value < 30).toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F6F67),
        foregroundColor: Colors.white,
        title: Text(widget.locale.languageCode == 'en' ? 'Suggestions' : 'Рекомендации'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.locale.languageCode == 'en'
                      ? 'Suggestions to improve time allocation'
                      : 'Рекомендации для улучшения распределения времени',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (_timeSpent.isEmpty)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(widget.locale.languageCode == 'en' ? 'No aggregated data yet.' : 'Пока нет собранных данных.'),
                    ),
                  ),
                if (low.isEmpty && _timeSpent.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.locale.languageCode == 'en'
                            ? 'Good job — you have consistent time allocation.'
                            : 'Отлично — у вас стабильное распределение времени.',
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                ...low.map((e) {
                  final prayer = e.key;
                  final mins = e.value;
                  final attempts = _koshish[prayer] ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE3EAE9)),
                        boxShadow: const [BoxShadow(color: Color(0x0F1F6F67), blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFFE8F6F3),
                            child: const Icon(Icons.self_improvement, color: Color(0xFF1F6F67)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(prayer, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(height: 6),
                                Text(
                                  '${widget.locale.languageCode == 'en' ? 'Total' : 'Итого'}: $mins min',
                                  style: const TextStyle(color: Color(0xFF677E7F), fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.locale.languageCode == 'en'
                                      ? 'Try a quick session (5–10 min) after prayer time to build a habit.'
                                      : 'Попробуйте короткую сессию (5–10 минут) после времени намаза, чтобы закрепить привычку.',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF4E5E60)),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    ElevatedButton(
                                      onPressed: () => _applyQuickSuggestion(prayer),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1F6F67),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: Text(widget.locale.languageCode == 'en' ? 'Apply' : 'Применить'),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${widget.locale.languageCode == 'en' ? 'Attempts' : 'Попытки'}: $attempts',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF708383)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
    );
  }
}

class TimeSpentEditIntervalsPage extends StatefulWidget {
  final Locale locale;
  const TimeSpentEditIntervalsPage({super.key, required this.locale});

  @override
  State<TimeSpentEditIntervalsPage> createState() => _TimeSpentEditIntervalsPageState();
}

class _TimeSpentEditIntervalsPageState extends State<TimeSpentEditIntervalsPage> {
  Map<String, String> _customTimes = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomTimes();
  }

  Future<void> _loadCustomTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final c = prefs.getString('custom_times');
    final Map<String, String> m = {};
    if (c != null) {
      try {
        final Map mm = jsonDecode(c);
        mm.forEach((k, v) => m[k.toString()] = v.toString());
      } catch (_) {}
    }
    _customTimes = m;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickTime(String prayer) async {
    final parts = (_customTimes[prayer] ?? '12:00').split(':');
    final initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final newTime = '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}';
      // update local map only; persist when user taps Save
      _customTimes[prayer] = newTime;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.locale.languageCode == 'en' ? 'Set $prayer to $newTime (tap Save to apply)' : 'Установлено $prayer = $newTime (нажмите Сохранить для применения)')));
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F6F67),
        foregroundColor: Colors.white,
        title: Text(widget.locale.languageCode == 'en' ? 'Edit intervals' : 'Редактировать интервалы'),
        actions: [
          TextButton(
            onPressed: _loading
                ? null
                : () async {
                    // Save and return true so parent can reload and reschedule
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('custom_times', jsonEncode(_customTimes));
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.locale.languageCode == 'en' ? 'Custom times saved' : 'Пользовательские времена сохранены')));
                    if (mounted) Navigator.pop(context, true);
                  },
            child: Text(widget.locale.languageCode == 'en' ? 'Save' : 'Сохранить', style: const TextStyle(color: Colors.white)),
          ),
          IconButton(
            tooltip: 'Reset',
            onPressed: _loading
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(widget.locale.languageCode == 'en' ? 'Reset to defaults' : 'Сбросить по умолчанию'),
                        content: Text(widget.locale.languageCode == 'en' ? 'Clear custom times and use defaults?' : 'Очистить пользовательские времена и использовать стандартные?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(widget.locale.languageCode == 'en' ? 'Cancel' : 'Отмена')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(widget.locale.languageCode == 'en' ? 'Reset' : 'Сбросить')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      _customTimes.clear();
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('custom_times');
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.locale.languageCode == 'en' ? 'Reset done' : 'Сброс выполнен')));
                      if (mounted) setState(() {});
                    }
                  },
            icon: const Icon(Icons.refresh, color: Colors.white),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: prayers.map((p) {
                final t = _customTimes[p] ?? '';
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    title: Text(p),
                    subtitle: Text(t.isEmpty ? (widget.locale.languageCode == 'en' ? 'Using default' : 'Используется стандартное время') : t),
                    trailing: TextButton(onPressed: () => _pickTime(p), child: Text(widget.locale.languageCode == 'en' ? 'Edit' : 'Изменить')),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class DhikrPage extends StatefulWidget {
  final Locale locale;
  const DhikrPage({super.key, required this.locale});

  @override
  State<DhikrPage> createState() => _DhikrPageState();
}

class _DhikrPageState extends State<DhikrPage> {
  final List<Map<String, String>> _builtInZikr = [
    {
      'id': 'subhanallah',
      'arabic': 'سُبْحَانَ ٱللّٰهِ',
      'latin': 'SubhanAllah',
      'uz_cyr': 'Субҳаналлоҳ',
      'en': 'Glory be to Allah',
      'ru': 'СубханАллах',
    },
    {
      'id': 'alhamdulillah',
      'arabic': 'الْحَمْدُ لِلّٰهِ',
      'latin': 'Alhamdulillah',
      'uz_cyr': 'Алҳамдулиллоҳ',
      'en': 'Praise be to Allah',
      'ru': 'Альхамдулиллах',
    },
    {
      'id': 'allahuakbar',
      'arabic': 'اللّٰهُ أَكْبَرُ',
      'latin': 'Allahu Akbar',
      'uz_cyr': 'Аллоҳу акбар',
      'en': 'Allah is the Greatest',
      'ru': 'Аллаху Акбар',
    },
  ];

  List<Map<String, String>> _zikrList = [];
  Map<String, int> _attempts = {};
  Map<String, int> _targets = {};
  bool _loading = true;
  bool _premiumUnlocked = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _saveZikrList() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = _zikrList.skip(_builtInZikr.length).toList();
    await prefs.setString('zikr_list', jsonEncode(custom));
    await prefs.setString('zikr_attempts', jsonEncode(_attempts));
    await prefs.setString('zikr_targets', jsonEncode(_targets));
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('zikr_attempts');
    final t = prefs.getString('zikr_targets');
    final l = prefs.getString('zikr_list');
    final Map<String, int> att = {};
    final Map<String, int> tar = {};
    final List<Map<String, String>> userList = [];

    // read premium flag so non-premium users have limited access to extra zikr
    try {
      _premiumUnlocked = prefs.getBool('premium_unlocked') ?? false;
    } catch (_) {
      _premiumUnlocked = false;
    }

    if (s != null) {
      try {
        final Map mm = jsonDecode(s);
        mm.forEach((k, v) => att[k.toString()] = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0);
      } catch (_) {}
    }
    if (t != null) {
      try {
        final Map mm = jsonDecode(t);
        mm.forEach((k, v) => tar[k.toString()] = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 33);
      } catch (_) {}
    }
    if (l != null) {
      try {
        final List ll = jsonDecode(l);
        for (final item in ll) {
          final Map map = Map<String, dynamic>.from(item as Map);
          userList.add(map.map((k, v) => MapEntry(k.toString(), v.toString())));
        }
      } catch (_) {}
    }

    _zikrList = [..._builtInZikr, ...userList];
    for (final z in _zikrList) {
      final id = z['id'];
      if (id == null || id.isEmpty) continue;
      att.putIfAbsent(id, () => 0);
      tar.putIfAbsent(id, () => 33);
    }

    _attempts = att;
    _targets = tar;
    _loading = false;
    if (mounted) setState(() {});
  }

  void _inc(String id) {
    final idx = _zikrList.indexWhere((element) => element['id'] == id);
    if (!_premiumUnlocked && idx > 0) {
      _showUpgradePrompt();
      return;
    }
    _attempts[id] = (_attempts[id] ?? 0) + 1;
    _saveZikrList();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.locale.languageCode == 'en' ? 'Added' : 'Добавлено')));
    }
  }

  void _dec(String id) {
    final idx = _zikrList.indexWhere((element) => element['id'] == id);
    if (!_premiumUnlocked && idx > 0) {
      _showUpgradePrompt();
      return;
    }
    _attempts[id] = ((_attempts[id] ?? 0) - 1).clamp(0, 99999);
    _saveZikrList();
    if (mounted) setState(() {});
  }

  void _setTarget(String id, int v) {
    final idx = _zikrList.indexWhere((element) => element['id'] == id);
    if (!_premiumUnlocked && idx > 0) {
      _showUpgradePrompt();
      return;
    }
    _targets[id] = v;
    _saveZikrList();
    if (mounted) setState(() {});
  }

  void _showUpgradePrompt() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.locale.languageCode == 'en' ? 'Premium required' : 'Требуется премиум'),
        content: Text(widget.locale.languageCode == 'en'
            ? 'This feature is available for Premium users only. Open Profile to upgrade.'
            : 'Эта функция доступна только для премиум-пользователей. Откройте профиль для обновления.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(widget.locale.languageCode == 'en' ? 'Cancel' : 'Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(widget.locale.languageCode == 'en' ? 'OK' : 'ОК')),
        ],
      ),
    );
  }

  Future<void> _showAddZikrDialog({Map<String, String>? item}) async {
    final arabicCtl = TextEditingController(text: item?['arabic'] ?? '');
    final latinCtl = TextEditingController(text: item?['latin'] ?? '');
    final uzCtl = TextEditingController(text: item?['uz_cyr'] ?? '');
    final enCtl = TextEditingController(text: item?['en'] ?? '');
    final ruCtl = TextEditingController(text: item?['ru'] ?? '');
    final targetCtl = TextEditingController(text: (item == null ? '33' : (_targets[item['id']] ?? 33).toString()));
    final isEditing = item != null;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            isEditing
                ? (widget.locale.languageCode == 'en' ? 'Edit zikr' : 'Редактировать зикр')
                : (widget.locale.languageCode == 'en' ? 'Add new zikr' : 'Добавить зикр'),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: arabicCtl, decoration: InputDecoration(labelText: widget.locale.languageCode == 'en' ? 'Arabic' : 'Арабский')),
                  const SizedBox(height: 8),
                  TextField(controller: latinCtl, decoration: InputDecoration(labelText: widget.locale.languageCode == 'en' ? 'Transliteration' : 'Транслитерация')),
                  const SizedBox(height: 8),
                  TextField(controller: uzCtl, decoration: InputDecoration(labelText: widget.locale.languageCode == 'en' ? 'Uzbek (Cyrillic)' : 'Узбек (Кирилл)')),
                  const SizedBox(height: 8),
                  TextField(controller: enCtl, decoration: const InputDecoration(labelText: 'EN')),
                  const SizedBox(height: 8),
                  TextField(controller: ruCtl, decoration: const InputDecoration(labelText: 'RU')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: targetCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: widget.locale.languageCode == 'en' ? 'Target' : 'Цель'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(widget.locale.languageCode == 'en' ? 'Cancel' : 'Отмена')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(widget.locale.languageCode == 'en' ? (isEditing ? 'Save' : 'Add') : (isEditing ? 'Сохранить' : 'Добавить')),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    final arabic = arabicCtl.text.trim();
    final latin = latinCtl.text.trim();
    final uz = uzCtl.text.trim();
    final en = enCtl.text.trim();
    final ru = ruCtl.text.trim();
    final target = int.tryParse(targetCtl.text.trim()) ?? 33;

    if ((arabic.isEmpty && latin.isEmpty) || (en.isEmpty && ru.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.locale.languageCode == 'en'
                  ? 'Please fill in the zikr name and at least one translation.'
                  : 'Заполните название зикра и хотя бы один перевод.',
            ),
          ),
        );
      }
      return;
    }

    final base = (latin.isNotEmpty ? latin : arabic);
    final generatedId = (base.isNotEmpty ? base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_') : DateTime.now().millisecondsSinceEpoch.toString())
        .replaceAll(RegExp(r'^_|_$'), '');
    final id = item?['id'] ?? generatedId;
    final map = {
      'id': id,
      'arabic': arabic,
      'latin': latin,
      'uz_cyr': uz,
      'en': en,
      'ru': ru,
    };

    setState(() {
      if (isEditing) {
        final index = _zikrList.indexWhere((element) => element['id'] == id);
        if (index >= 0) _zikrList[index] = map;
      } else {
        _zikrList.add(map);
      }
      _attempts[id] = _attempts[id] ?? 0;
      _targets[id] = target;
    });

    await _saveZikrList();
  }

  Future<void> _deleteZikr(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.locale.languageCode == 'en' ? 'Delete zikr?' : 'Удалить зикр?'),
        content: Text(widget.locale.languageCode == 'en' ? 'This custom zikr will be removed from your list.' : 'Этот пользовательский зикр будет удалён из вашего списка.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(widget.locale.languageCode == 'en' ? 'Cancel' : 'Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(widget.locale.languageCode == 'en' ? 'Delete' : 'Удалить')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _zikrList.removeWhere((item) => item['id'] == id && !_builtInZikr.any((element) => element['id'] == id));
      _attempts.remove(id);
      _targets.remove(id);
    });

    await _saveZikrList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F6F67),
        foregroundColor: Colors.white,
        title: Text(widget.locale.languageCode == 'en' ? 'Dhikr & Tasbih' : 'Зикр и тасбих'),
        actions: [
          IconButton(
            onPressed: () => _showAddZikrDialog(),
            icon: const Icon(Icons.add),
            tooltip: widget.locale.languageCode == 'en' ? 'Add zikr' : 'Добавить зикр',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1F6F67), Color(0xFF2B7E7A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Color(0x1A1F6F67), blurRadius: 14, offset: Offset(0, 8))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.locale.languageCode == 'en' ? 'Dhikr total' : 'Всего зикров',
                              style: const TextStyle(color: Color(0xFFD8F4F0), fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_zikrList.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          widget.locale.languageCode == 'en' ? 'Custom: ${_zikrList.length - _builtInZikr.length}' : 'Свои: ${_zikrList.length - _builtInZikr.length}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ...List.generate(_zikrList.length, (index) {
                  final z = _zikrList[index];
                  final id = z['id'] ?? 'zikr_$index';
                  final arabic = z['arabic'] ?? '';
                  final latin = z['latin'] ?? '';
                  final uzCyr = z['uz_cyr'] ?? '';
                  final en = z['en'] ?? '';
                  final ru = z['ru'] ?? '';
                  final attempts = _attempts[id] ?? 0;
                  final target = _targets[id] ?? 33;
                  final progress = (attempts / (target == 0 ? 1 : target)).clamp(0.0, 1.0);
                  final isCustom = !_builtInZikr.any((item) => item['id'] == id);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8F6FF),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFFE6E0FF)),
                                  ),
                                  child: Center(
                                    child: Text(
                                      arabic.isEmpty ? (latin.isEmpty ? 'Zikr' : latin) : arabic,
                                      style: const TextStyle(fontSize: 24, fontFamily: 'NotoNaskh', fontWeight: FontWeight.w700),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              if (isCustom)
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _showAddZikrDialog(item: z);
                                    } else if (value == 'delete') {
                                      _deleteZikr(id);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(value: 'edit', child: Text(widget.locale.languageCode == 'en' ? 'Edit' : 'Изменить')),
                                    PopupMenuItem(value: 'delete', child: Text(widget.locale.languageCode == 'en' ? 'Delete' : 'Удалить')),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  latin.isEmpty ? (widget.locale.languageCode == 'en' ? 'Custom zikr' : 'Пользовательский зикр') : latin,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: latin.isNotEmpty ? latin : arabic));
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(widget.locale.languageCode == 'en' ? 'Copied' : 'Скопировано')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy_rounded, size: 18),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (uzCyr.isNotEmpty) Text(uzCyr, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                          if (uzCyr.isNotEmpty) const SizedBox(height: 6),
                          Text(widget.locale.languageCode == 'ru' ? ru : en, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 10,
                                        backgroundColor: const Color(0xFFF1F5F4),
                                        color: const Color(0xFF7FB7AE),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text('$attempts / $target', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      IconButton(onPressed: () => _dec(id), icon: const Icon(Icons.remove_circle_outline_rounded)),
                                      IconButton(onPressed: () => _inc(id), icon: const Icon(Icons.add_circle_outline_rounded)),
                                    ],
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final value = await showDialog<int?>(
                                        context: context,
                                        builder: (ctx) {
                                          final ctl = TextEditingController(text: target.toString());
                                          return AlertDialog(
                                            title: Text(widget.locale.languageCode == 'en' ? 'Set target' : 'Установить цель'),
                                            content: TextField(controller: ctl, keyboardType: TextInputType.number),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text(widget.locale.languageCode == 'en' ? 'Cancel' : 'Отмена')),
                                              FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text.trim())), child: Text(widget.locale.languageCode == 'en' ? 'Save' : 'Сохранить')),
                                            ],
                                          );
                                        },
                                      );
                                      if (value != null && value > 0) _setTarget(id, value);
                                    },
                                    child: Text(widget.locale.languageCode == 'en' ? 'Set target' : 'Установить цель'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
