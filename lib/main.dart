import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'prayer_menu.dart' as pm;

import 'firebase_options.dart';

class PremiumPlan {
  static const String monthlyProductId = 'zikr_premium_monthly';
  static const String yearlyProductId = 'zikr_premium_yearly';
}

Future<void> initializeFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
}

Future<String?> _getPlatformTimeZone() async {
  const channel = MethodChannel('app.channel.timezone');
  try {
    final name = await channel.invokeMethod<String>('getTimeZoneName');
    return name;
  } on PlatformException catch (e) {
    debugPrint('Timezone platform channel error: $e');
    return null;
  }
}

final AudioPlayer _audioPlayer = AudioPlayer();

Future<void> playAzan() async {
  try {
    // Asset path is declared in pubspec: assets/audio/Adhan-Egypt.mp3
    await _audioPlayer.stop();
    await _audioPlayer.play(AssetSource('audio/Adhan-Egypt.mp3'));
  } catch (e) {
    debugPrint('playAzan failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();
  tz.initializeTimeZones();
  final iana = await _getPlatformTimeZone();
  if (iana != null) {
    try {
      tz.setLocalLocation(tz.getLocation(iana));
      debugPrint('tz.local set to $iana');
    } catch (e) {
      debugPrint('Failed to set tz.local from platform: $e');
    }
  }

  await NotificationService.initialize();
  runApp(const ZikrApp());
}

class ZikrApp extends StatefulWidget {
  const ZikrApp({super.key});

  @override
  State<ZikrApp> createState() => _ZikrAppState();
}

class MyApp extends ZikrApp {
  const MyApp({super.key});
}

class _ZikrAppState extends State<ZikrApp> {
  Locale _locale = const Locale('ru');

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _locale = Locale(prefs.getString('app_locale') ?? 'ru'));
  }

  Future<void> _saveLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_locale', locale.languageCode);
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zikr',
      locale: _locale,
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F3EE),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F67)),
      ),
      home: ZikrHomePage(
        locale: _locale,
        onLocaleChanged: _saveLocale,
      ),
    );
  }
}

class ZikrHomePage extends StatefulWidget {
  const ZikrHomePage({super.key, required this.locale, required this.onLocaleChanged});
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<ZikrHomePage> createState() => _ZikrHomePageState();
}

class HabitItem {
  HabitItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.done,
    this.minutes = 15,
    this.time = '08:00',
    this.frequency = 'Daily',
  });
  final String id;
  final String title;
  final String subtitle;
  bool done;
  int minutes;
  String time;
  String frequency;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'done': done,
        'minutes': minutes,
        'time': time,
        'frequency': frequency,
      };
  factory HabitItem.fromJson(Map<String, dynamic> map) => HabitItem(
        id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: map['title'] ?? 'Habit',
        subtitle: map['subtitle'] ?? '',
        done: map['done'] ?? false,
        minutes: map['minutes'] is num ? (map['minutes'] as num).toInt() : 15,
        time: map['time']?.toString() ?? '08:00',
        frequency: map['frequency']?.toString() ?? 'Daily',
      );
}

class TasbihCounter {
  TasbihCounter({required this.id, required this.name, required this.count, required this.target});
  final String id;
  final String name;
  int count;
  int target;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'count': count, 'target': target};
  factory TasbihCounter.fromJson(Map<String, dynamic> map) => TasbihCounter(
        id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: map['name'] ?? 'Tasbih',
        count: map['count'] ?? 0,
        target: map['target'] ?? 33,
      );
}

class PrayerData {
  PrayerData({required this.times, required this.location});
  final Map<String, String> times;
  final String location;

  static Future<PrayerData> load() async {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final url = Uri.parse('https://api.aladhan.com/v1/timingsByCity/$date?city=Tashkent&country=Uzbekistan&method=2');
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final timings = data['data']?['timings'];
        if (timings is Map) {
          return PrayerData(
            times: {
              'Fajr': timings['Fajr'] ?? '04:15',
              'Dhuhr': timings['Dhuhr'] ?? '12:35',
              'Asr': timings['Asr'] ?? '16:42',
              'Maghrib': timings['Maghrib'] ?? '19:25',
              'Isha': timings['Isha'] ?? '20:56',
            },
            location: 'Tashkent, Uzbekistan',
          );
        }
      }
    } catch (_) {}
    return fallback();
  }

  static PrayerData fallback() => PrayerData(
        times: {
          'Fajr': '04:15',
          'Dhuhr': '12:35',
          'Asr': '16:42',
          'Maghrib': '19:25',
          'Isha': '20:56',
        },
        location: 'Tashkent, Uzbekistan',
      );

  Map<String, String> effectiveTimes(Map<String, String>? customTimes) {
    final effective = Map<String, String>.from(times);
    if (customTimes != null) {
      for (final entry in customTimes.entries) {
        if (entry.key.isNotEmpty) {
          effective[entry.key] = entry.value;
        }
      }
    }
    return effective;
  }

  String getNextPrayerLabel({Map<String, String>? customTimes}) {
    final effective = effectiveTimes(customTimes);
    final now = DateTime.now();
    String? nextName;
    String? nextTime;
    for (final entry in effective.entries) {
      final parts = entry.value.split(':');
      final prayTime = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
      if (prayTime.isAfter(now)) {
        if (nextTime == null || prayTime.isBefore(DateTime(now.year, now.month, now.day, int.parse(nextTime.split(':')[0]), int.parse(nextTime.split(':')[1])))) {
          nextName = entry.key;
          nextTime = entry.value;
        }
      }
    }
    if (nextName == null || nextTime == null) {
      final first = effective.entries.first;
      return '${first.key} ${first.value}';
    }
    return '$nextName $nextTime';
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (Platform.isAndroid) {
      await androidPlugin?.requestNotificationsPermission();

      // If channels may exist from a previous install with different settings, delete them first to ensure
      // the new channel configuration (sound, importance) takes effect.
      try {
        await androidPlugin?.deleteNotificationChannel('zikr_azan');
        await androidPlugin?.deleteNotificationChannel('zikr_notifications');
        debugPrint('Deleted old notification channels (if any)');
      } catch (e) {
        // Not fatal; continue to (re)create channels
        debugPrint('deleteNotificationChannel warning: $e');
      }

      // Create dedicated channels: one for azan (with custom raw sound) and one default channel.
      final azanChannel = AndroidNotificationChannel(
        'zikr_azan',
        'Zikr Azan',
        description: 'Azan notifications with adhan sound',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('adhan'),
        playSound: true,
      );

      final defaultChannel = AndroidNotificationChannel(
        'zikr_notifications',
        'Zikr notifications',
        description: 'Daily prayer and routine reminders',
        importance: Importance.defaultImportance,
      );

      try {
        await androidPlugin?.createNotificationChannel(azanChannel);
        await androidPlugin?.createNotificationChannel(defaultChannel);
        debugPrint('Created notification channels: zikr_azan, zikr_notifications');
      } catch (e) {
        debugPrint('createNotificationChannel failed: $e');
      }
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings, onDidReceiveNotificationResponse: (response) async {
      final payload = response.payload;
      NotificationService._handlePayload(payload);
    });
  }

  static Future<void> _handlePayload(String? payload) async {
    if (payload == null) return;
    try {
      final Map m = jsonDecode(payload);
      if (m['azan'] == '1' || m['azan'] == 1) {
        await playAzan();
      }
    } catch (e) {
      // ignore
    }
  }


  static int _idFor(String title, String time) => title.hashCode + time.hashCode;

  static Future<void> scheduleDaily({required String title, required String body, required String time, Map<String, String>? payload}) async {
    final p = time.split(':');
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    final bool wantsAzan = payload != null && (payload['azan'] == '1' || payload['azan'] == 'true');
    final channelId = wantsAzan ? 'zikr_azan' : 'zikr_notifications';
    final channelName = wantsAzan ? 'Zikr Azan' : 'Zikr notifications';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Daily prayer and routine reminders',
      importance: Importance.max,
      priority: Priority.high,
      sound: wantsAzan ? RawResourceAndroidNotificationSound('adhan') : null,
      playSound: wantsAzan,
    );

    // Ensure previous schedule with same id is removed to avoid duplicates
    final id = _idFor(title, time);
    try {
      debugPrint('Notification schedule: id=$id title="$title" time=$time wantsAzan=$wantsAzan channel=$channelId scheduled=$scheduled');
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('cancel previous notification failed: $e');
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload != null ? jsonEncode(payload) : null,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    debugPrint('zonedSchedule requested for id=$id');
  }

  static Future<void> cancelScheduled(String title, String time) async {
    final id = _idFor(title, time);
    await _plugin.cancel(id);
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}

class _ZikrHomePageState extends State<ZikrHomePage> {
  int _selectedIndex = 0;
  int _zikrCount = 0;
  int _target = 33;
  bool _premiumUnlocked = false;
  bool _introShown = false;

  String _userName = 'Muslim';
  String _userEmail = 'user@example.com';
  late SharedPreferences _prefs;
  Future<PrayerData>? _prayerFuture;

  List<HabitItem> _habits = [
    HabitItem(id: 'fajr', title: 'Fajr', subtitle: 'Daily prayer', done: true, minutes: 15, time: '05:30', frequency: 'Daily'),
    HabitItem(id: 'quran', title: 'Quran', subtitle: '10 min', done: false, minutes: 10, time: '20:00', frequency: 'Daily'),
    HabitItem(id: 'dhikr', title: 'Dhikr', subtitle: '33x', done: true, minutes: 8, time: '21:00', frequency: 'Daily'),
  ];

  List<TasbihCounter> _tasbihs = [
    TasbihCounter(id: '1', name: 'SubhanAllah', count: 0, target: 33),
    TasbihCounter(id: '2', name: 'Alhamdulillah', count: 0, target: 33),
    TasbihCounter(id: '3', name: 'Allahu Akbar', count: 0, target: 33),
    TasbihCounter(id: '4', name: 'Salawat', count: 0, target: 33),
    TasbihCounter(id: '5', name: 'Istighfar', count: 0, target: 33),
  ];
  String? _selectedTasbihId; // id of the tasbih shown at top (only one free visible by default)


  Map<String, int> _prayerHistory = {'Fajr': 3, 'Dhuhr': 4, 'Asr': 2, 'Maghrib': 5, 'Isha': 4};
  Map<String, int> _timeSpent = {'Fajr': 12, 'Dhuhr': 18, 'Asr': 14, 'Maghrib': 10, 'Isha': 15};

  // Per-day detailed prayer records: { '2026-08-26': { 'Fajr': {done:true, timeMinutes:8, reason:'Quick 5', timestamp:...}, ... }, ... }
  Map<String, Map<String, Map<String, dynamic>>> _prayerRecords = {}; // persisted as 'prayer_records'

  // Active timers: stores start timestamp millis for a prayer currently being timed
  Map<String, int?> _activeTimerStarts = {};

  // Analytics range in days for premium detailed view
  int _analyticsRangeDays = 7;

  // Per-prayer settings: notify and azan and custom times
  Map<String, bool> _notifyEnabled = {'Fajr': true, 'Dhuhr': true, 'Asr': true, 'Maghrib': true, 'Isha': true};
  Map<String, bool> _azanEnabled = {'Fajr': false, 'Dhuhr': false, 'Asr': false, 'Maghrib': false, 'Isha': false};
  Map<String, String> _customTimes = {}; // e.g. {'Fajr': '04:20'}
  // Planned minutes for today per prayer (date-agnostic simple store for today's plans)
  Map<String, int> _plannedToday = {}; // e.g. {'Fajr': 10}

  // Auth and billing helpers
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: const ['email', 'profile']);
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  bool _billingAvailable = false;
  List<ProductDetails> _premiumProducts = const [];
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  @override
  void initState() {
    super.initState();
    _prayerFuture = PrayerData.load();
    _loadSavedState().then((_) => _initAuthAndBilling());
  }

  Future<void> _loadSavedState() async {
    _prefs = await SharedPreferences.getInstance();
    final premium = _prefs.getBool('premium_unlocked') ?? false;
    final target = _prefs.getInt('zikr_target') ?? 33;
    final count = _prefs.getInt('zikr_count') ?? 0;
    final name = _prefs.getString('account_name') ?? 'Muslim';
    final email = _prefs.getString('account_email') ?? 'user@example.com';
    final habitsJson = _prefs.getStringList('habits') ?? const [];
    final tasbihJson = _prefs.getStringList('tasbih') ?? const [];

    // load saved prayer analytics
    try {
      final hist = _prefs.getString('prayer_history');
      if (hist != null) {
        final Map m = jsonDecode(hist);
        _prayerHistory = m.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      }
    } catch (_) {}
    try {
      final t = _prefs.getString('time_spent');
      if (t != null) {
        final Map m = jsonDecode(t);
        _timeSpent = m.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      }
    } catch (_) {}

    // load detailed per-day prayer records (new feature)
    try {
      final rec = _prefs.getString('prayer_records');
      if (rec != null) {
        final Map m = jsonDecode(rec);
        _prayerRecords = m.map((date, v) {
          final sub = <String, Map<String, dynamic>>{};
          try {
            final Map vv = v as Map;
            vv.forEach((k2, v2) {
              sub[k2.toString()] = Map<String, dynamic>.from(v2 as Map);
            });
          } catch (_) {}
          return MapEntry(date.toString(), sub);
        });
      }
    } catch (_) {}

    // load active timers so they survive app restart
    try {
      final at = _prefs.getString('active_timers');
      if (at != null) {
        final Map m = jsonDecode(at);
        _activeTimerStarts = m.map((k, v) => MapEntry(k.toString(), v == null ? null : (v as num).toInt()));
      }
    } catch (_) {}

    // load per-prayer settings
    try {
      final n = _prefs.getString('notify_settings');
      if (n != null) {
        final Map m = jsonDecode(n);
        _notifyEnabled = m.map((k, v) => MapEntry(k.toString(), v == true));
      }
    } catch (_) {}
    try {
      final a = _prefs.getString('azan_settings');
      if (a != null) {
        final Map m = jsonDecode(a);
        _azanEnabled = m.map((k, v) => MapEntry(k.toString(), v == true));
      }
    } catch (_) {}
    try {
      final c = _prefs.getString('custom_times');
      if (c != null) {
        final Map m = jsonDecode(c);
        _customTimes = m.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    // load today's planned minutes (keyed by date to support per-day plans)
    try {
      final today = DateTime.now();
      final dateKey = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      final p = _prefs.getString('planned_$dateKey');
      if (p != null) {
        final Map m = jsonDecode(p);
        _plannedToday = m.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      }
    } catch (_) {}

    final loadedHabits = <HabitItem>[];
    for (final item in habitsJson) {
      try {
        loadedHabits.add(HabitItem.fromJson(jsonDecode(item)));
      } catch (_) {}
    }
    if (loadedHabits.isNotEmpty) _habits = loadedHabits;

    final loadedTasbih = <TasbihCounter>[];
    for (final item in tasbihJson) {
      try {
        loadedTasbih.add(TasbihCounter.fromJson(jsonDecode(item)));
      } catch (_) {}
    }
    if (loadedTasbih.isNotEmpty) _tasbihs = loadedTasbih;
    // restore previously selected tasbih if present
    final sel = _prefs.getString('selected_tasbih');
    if (sel != null && _tasbihs.any((t) => t.id == sel)) {
      _selectedTasbihId = sel;
    } else if (_tasbihs.isNotEmpty) {
      _selectedTasbihId ??= _tasbihs.first.id;
    }

    setState(() {
      _premiumUnlocked = premium;
      _target = target;
      _zikrCount = count;
      _userName = name;
      _userEmail = email;
    });

    if (!_introShown && !_premiumUnlocked) {
      _introShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPremiumDialog());
    }

    // After loading saved settings, reschedule notifications once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rescheduleAllPrayerNotifications();
    });
  }

  Map<String, String> _readCustomTimesFromPrefs() {
    final map = <String, String>{};
    try {
      final raw = _prefs.getString('custom_times');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) => map[key.toString()] = value.toString());
        }
      }
    } catch (_) {}
    return map;
  }

  Future<void> _saveState() async {
    await _prefs.setBool('premium_unlocked', _premiumUnlocked);
    await _prefs.setInt('zikr_target', _target);
    await _prefs.setInt('zikr_count', _zikrCount);
    await _prefs.setString('account_name', _userName);
    await _prefs.setString('account_email', _userEmail);
    await _prefs.setStringList('habits', _habits.map((e) => jsonEncode(e.toJson())).toList());
    await _prefs.setStringList('tasbih', _tasbihs.map((e) => jsonEncode(e.toJson())).toList());
    if (_selectedTasbihId != null) await _prefs.setString('selected_tasbih', _selectedTasbihId!);

    // save analytics and per-prayer settings
    await _prefs.setString('prayer_history', jsonEncode(_prayerHistory));
    await _prefs.setString('time_spent', jsonEncode(_timeSpent));
    await _prefs.setString('notify_settings', jsonEncode(_notifyEnabled));
    await _prefs.setString('azan_settings', jsonEncode(_azanEnabled));
    await _prefs.setString('custom_times', jsonEncode(_customTimes));

    // persist detailed records
    try {
      await _prefs.setString('prayer_records', jsonEncode(_prayerRecords));
    } catch (e) {
      debugPrint('Failed to save prayer_records: $e');
    }

    // persist active timers so they resume after restart
    try {
      await _prefs.setString('active_timers', jsonEncode(_activeTimerStarts));
    } catch (e) {
      debugPrint('Failed to save active_timers: $e');
    }

    // persist today's planned minutes (keyed by date)
    try {
      final today = DateTime.now();
      final dateKey = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      await _prefs.setString('planned_$dateKey', jsonEncode(_plannedToday));
    } catch (e) {
      debugPrint('Failed to save planned_today: $e');
    }
  }

  Future<void> _rescheduleAllPrayerNotifications() async {
    try {
      final engKeys = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
      // Capture localized labels before awaiting to avoid using BuildContext across async gaps
      final localizedMap = <String, String>{};
      for (final eng in engKeys) {
        localizedMap[eng] = AppStrings.text(context, eng.toLowerCase());
      }
      final nextPrayerLabel = AppStrings.text(context, 'next_prayer');

      final data = await (_prayerFuture ?? PrayerData.load());

      for (final eng in engKeys) {
        final localized = localizedMap[eng] ?? eng;
        final effectiveTime = _customTimes[eng] ?? _customTimes[localized] ?? (data.times[eng] ?? '00:00');
        final notifyOn = _notifyEnabled[eng] ?? _notifyEnabled[localized] ?? false;
        final azanOn = _azanEnabled[eng] ?? _azanEnabled[localized] ?? false;
        // Cancel any previous and schedule if needed
        await NotificationService.cancelScheduled(localized, effectiveTime);
        if (notifyOn) {
          await NotificationService.scheduleDaily(title: localized, body: '$nextPrayerLabel: $effectiveTime', time: effectiveTime, payload: {'azan': azanOn ? '1' : '0'});
        }
      }
    } catch (e) {
      debugPrint('rescheduleAllPrayerNotifications failed: $e');
    }
  }

  // --- Authentication and Billing ---
  Future<void> _initAuthAndBilling() async {
    // Listen for Firebase auth state changes
    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        setState(() {
          _userName = user.displayName ?? _userName;
          _userEmail = user.email ?? _userEmail;
        });
        await _saveState();
      }
    });

    // Try to silently restore previously signed-in Google account so the app
    // keeps the same Google user across restarts. This does not affect manual sign-in.
    try {
      final silent = await _googleSignIn.signInSilently();
      if (silent != null) {
        debugPrint('GoogleSignIn: restored silently for ${silent.email}');
        try {
          final auth = await silent.authentication;
          final credential = GoogleAuthProvider.credential(
            accessToken: auth.accessToken,
            idToken: auth.idToken,
          );
          await _auth.signInWithCredential(credential);
          // authStateChanges listener will save state when user is non-null
        } catch (e) {
          debugPrint('Silent sign-in to Firebase failed: $e');
        }
      }
    } catch (e) {
      debugPrint('GoogleSignIn.signInSilently() threw: $e');
    }

    // Initialize in-app purchases
    try {
      _billingAvailable = await _inAppPurchase.isAvailable();
      if (_billingAvailable) {
        const Set<String> ids = {PremiumPlan.monthlyProductId, PremiumPlan.yearlyProductId};
        final response = await _inAppPurchase.queryProductDetails(ids);
        if (response.error == null && response.productDetails.isNotEmpty) {
          setState(() => _premiumProducts = response.productDetails);
        }
        _purchaseSubscription = _inAppPurchase.purchaseStream.listen(_handlePurchaseUpdates, onError: (e) {});
      }
    } catch (e) {
      // ignore billing init errors — will surface in logs
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return; // user canceled
      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user != null) {
        setState(() {
          _userName = user.displayName ?? _userName;
          _userEmail = user.email ?? _userEmail;
        });
        await _saveState();
      }
    } on PlatformException catch (e) {
      // Detailed diagnostics for easier troubleshooting without changing existing behavior
      debugPrint('Google sign-in failed (PlatformException): $e');
      debugPrint('PlatformException.code: ${e.code}');
      debugPrint('PlatformException.message: ${e.message}');
      debugPrint('PlatformException.details: ${e.details}');

      // Show a dialog with the error code/message so the user can copy it for support
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Google Sign-In'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Error code: ${e.code ?? 'unknown'}'),
                  const SizedBox(height: 8),
                  Text('Message: ${e.message ?? e.toString()}'),
                  const SizedBox(height: 12),
                  const Text('Please ensure your app package name and SHA-1 are registered in the Firebase/Google Console and the correct google-services.json is included.'),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }

      // Keep showing a SnackBar for other UI feedback
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Google sign-in failed: ${e.message ?? e}')));
    } catch (e) {
      // fallback catch
      debugPrint('Google sign-in failed: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Google sign-in failed: $e')));
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
      setState(() {
        _userName = 'Muslim';
        _userEmail = 'user@example.com';
        _premiumUnlocked = _prefs.getBool('premium_unlocked') ?? false;
      });
      await _saveState();
    } catch (e) {
      debugPrint('Sign-out error: $e');
    }
  }

  void _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
        // For production, verify purchase.serverVerificationData with your backend / platform APIs
        setState(() {
          _premiumUnlocked = true;
        });
        await _saveState();
      }
      if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
      }
    }
  }

  Future<void> _buyProduct(String productId) async {
    final product = _premiumProducts.firstWhere((p) => p.id == productId, orElse: () => throw Exception('Product not available'));
    final purchaseParam = PurchaseParam(productDetails: product);
    await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  // --- end auth/billing ---

  Future<void> _showProfileDialog() async {
    final nameController = TextEditingController(text: _userName);
    final emailController = TextEditingController(text: _userEmail);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF8FBFB), Color(0xFFFDF9ED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppStrings.text(context, 'account'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFE9C56D), Color(0xFFB8842D)]),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('Premium', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE6F0EE)),
                  ),
                  child: Column(
                    children: [
                      TextField(controller: nameController, decoration: InputDecoration(labelText: AppStrings.text(context, 'name'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
                      const SizedBox(height: 12),
                      TextField(controller: emailController, decoration: InputDecoration(labelText: AppStrings.text(context, 'email'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_billingAvailable && _premiumProducts.isNotEmpty) ...[
                  Text(widget.locale.languageCode == 'en' ? 'Choose a plan' : 'Выберите план', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
                  const SizedBox(height: 10),
                  ..._premiumProducts.asMap().entries.map((entry) {
                    final index = entry.key;
                    final p = entry.value;
                    final isFeatured = index == 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isFeatured ? const Color(0xFF1F6F67) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: isFeatured ? Colors.transparent : const Color(0xFFE7EFEE)),
                        boxShadow: [
                          if (isFeatured)
                            const BoxShadow(color: Color(0x1A1F6F67), blurRadius: 16, offset: Offset(0, 8)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.title.isNotEmpty ? p.title : (widget.locale.languageCode == 'en' ? 'Premium' : 'Премиум'),
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isFeatured ? Colors.white : const Color(0xFF173B3F)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  p.description.isNotEmpty ? p.description : (widget.locale.languageCode == 'en' ? 'Full access to premium features' : 'Полный доступ к премиум-функциям'),
                                  style: TextStyle(fontSize: 12, color: isFeatured ? const Color(0xFFD9F5F2) : const Color(0xFF6D7D80)),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                p.price.isNotEmpty ? p.price : (widget.locale.languageCode == 'en' ? '₽ 199' : '199 ₽'),
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: isFeatured ? Colors.white : const Color(0xFF173B3F)),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: () async => await _buyProduct(p.id),
                                style: FilledButton.styleFrom(
                                  backgroundColor: isFeatured ? Colors.white : const Color(0xFF1F6F67),
                                  foregroundColor: isFeatured ? const Color(0xFF1F6F67) : Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(widget.locale.languageCode == 'en' ? 'Get access' : 'Подключить'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _inAppPurchase.restorePurchases(),
                      child: Text(widget.locale.languageCode == 'en' ? 'Restore purchases' : 'Восстановить покупки'),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (_auth.currentUser != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(widget.locale.languageCode == 'en' ? 'Sign out' : 'Выйти'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: const Color(0xFF173B3F),
                        side: const BorderSide(color: Color(0xFFCEE0DE)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.login_rounded),
                      label: Text(widget.locale.languageCode == 'en' ? 'Sign in with Google' : 'Войти через Google'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1F6F67),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(AppStrings.text(ctx, 'cancel')),
                      ),
                    ),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final dialogNavigator = Navigator.of(ctx);
                          setState(() {
                            _userName = nameController.text.trim().isEmpty ? 'Muslim' : nameController.text.trim();
                            _userEmail = emailController.text.trim().isEmpty ? 'user@example.com' : emailController.text.trim();
                          });
                          _saveState().then((_) {
                            if (mounted) dialogNavigator.pop(true);
                          });
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1F6F67),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(AppStrings.text(ctx, 'save')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == true) {
      await NotificationService.scheduleDaily(
        title: 'Zikr reminder',
        body: 'Read 1 page of Quran and continue your routine.',
        time: '07:00',
      );
    }
  }

  void _showPremiumDialog() {
    if (_premiumUnlocked) return; // don't show to already subscribed users
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.9;
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          child: SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFDF9ED), Color(0xFFF8FBFB)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: InkWell(
                          onTap: () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(99),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(99)),
                            child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF173B3F)),
                          ),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFE9C56D), Color(0xFFB8842D)]),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [BoxShadow(color: Color(0x33E9C56D), blurRadius: 20, offset: Offset(0, 8))],
                            ),
                            child: const Icon(Icons.workspace_premium_rounded, size: 30, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.locale.languageCode == 'en' ? 'Premium access' : 'Премиум-доступ',
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF173B3F)),
                                ),
                                const SizedBox(height: 6),
                                // Badge: 1 month free
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: const Color(0xFFFFF2D9), borderRadius: BorderRadius.circular(999)),
                                  child: Text(
                                    widget.locale.languageCode == 'en' ? '1 month free' : '1 месяц бесплатно',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF8A6A20)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.locale.languageCode == 'en'
                            ? 'Everything you need for a more consistent prayer routine and deeper progress tracking.'
                            : 'Всё, что нужно для более стабильной молитвенной рутины и глубокой аналитики прогресса.',
                        style: const TextStyle(color: Color(0xFF708383), height: 1.5),
                      ),
                      const SizedBox(height: 14),

                      // Page-like horizontal preview: PageView with dots indicator
                      SizedBox(
                        height: maxH - 300,
                        child: _PremiumPreviewPager(locale: widget.locale, premiumProducts: _premiumProducts, onBuy: _buyProduct, onProfile: _showProfileDialog),
                      ),

                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) => _showProfileDialog());
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1F6F67),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.workspace_premium_rounded),
                          label: Text(widget.locale.languageCode == 'en' ? 'Activate Premium' : 'Активировать Premium'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Small reusable pager widget used inside the dialog. Kept as a private StatelessWidget to keep this file tidy.
  // It presents a PageView with three preview pages and a dots indicator. It is self-contained and does not require
  // additional state from the parent beyond callbacks for purchase/profile actions.
  
  // Note: placing this widget inside the State class file scope (but outside the state) keeps access to the same imports
  // while keeping the _showPremiumDialog method concise.
  
  // The edit below injects the widget declaration into the file as part of the same edit operation.
  
  
  Widget _buildPagerPage({required IconData icon, required String title, required String subtitle, required Widget content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: Color(0xFF708383))),
        const SizedBox(height: 12),
        Expanded(child: content),
      ],
    );
  }

  // Inline pager widget used only by _showPremiumDialog. Implemented as a StatefulBuilder-friendly widget by using
  // PageView and ValueNotifier for the current page index.
  Widget _PremiumPreviewPager({required Locale locale, required List<ProductDetails> premiumProducts, required Future<void> Function(String) onBuy, required VoidCallback onProfile}) {
    final controller = PageController();
    final pageIndex = ValueNotifier<int>(0);

    controller.addListener(() {
      final p = (controller.page ?? 0).round();
      if (pageIndex.value != p) pageIndex.value = p;
    });

    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: controller,
            children: [
              // Page 1: Features overview
              _buildPagerPage(
                icon: Icons.auto_awesome_rounded,
                title: locale.languageCode == 'en' ? 'What you get' : 'Что входит',
                subtitle: locale.languageCode == 'en'
                    ? 'Unlimited routines, full analytics and rich reminders.'
                    : 'Безлимитные рутины, подробная аналитика и напоминания.',
                content: ListView(
                  children: [
                    _featureRow(icon: Icons.auto_awesome_rounded, text: locale.languageCode == 'en' ? 'Unlimited routines and habits' : 'Безлимитные рутины и привычки'),
                    _featureRow(icon: Icons.bar_chart_rounded, text: locale.languageCode == 'en' ? 'Advanced analytics' : 'Расширенная аналитика'),
                    _featureRow(icon: Icons.notifications_active_rounded, text: locale.languageCode == 'en' ? 'Smart reminders and azan' : 'Умные напоминания и азан'),
                    _featureRow(icon: Icons.self_improvement_rounded, text: locale.languageCode == 'en' ? 'Custom dhikr and tasbih' : 'Пользовательские zikr и тасбих'),
                  ],
                ),
              ),

              // Page 2: Analytics preview
              _buildPagerPage(
                icon: Icons.bar_chart_rounded,
                title: locale.languageCode == 'en' ? 'Analytics' : 'Аналитика',
                subtitle: locale.languageCode == 'en' ? 'See trends, time breakdowns and detailed history.' : 'Смотрите тренды, разбивку времени и подробную историю.',
                content: Center(child: SizedBox(width: double.infinity, child: Card(elevation: 0, child: SizedBox(height: 220, child: _analyticsPreviewMock())))),
              ),

              // Page 3: Reminders & Dhikr preview
              _buildPagerPage(
                icon: Icons.notifications_active_rounded,
                title: locale.languageCode == 'en' ? 'Reminders & Dhikr' : 'Напоминания и зикр',
                subtitle: locale.languageCode == 'en' ? 'Azan, scheduled reminders and extra tasbih slots.' : 'Азан, плановые напоминания и дополнительные слоты тасбиха.',
                content: ListView(
                  children: [
                    _premiumPreviewCard(icon: Icons.notifications_active_rounded, title: locale.languageCode == 'en' ? 'Reminders' : 'Напоминания', subtitle: locale.languageCode == 'en' ? 'Azan + alerts' : 'Азан + уведомления'),
                    const SizedBox(height: 8),
                    _premiumPreviewCard(icon: Icons.self_improvement_rounded, title: locale.languageCode == 'en' ? 'Dhikr' : 'Зикр', subtitle: locale.languageCode == 'en' ? 'Full counting' : 'Полный подсчёт'),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(locale.languageCode == 'en' ? 'Tap Activate to connect account and unlock.' : 'Нажмите Активировать, чтобы подключить аккаунт и открыть доступ.', style: const TextStyle(color: Color(0xFF708383))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Dots indicator
        ValueListenableBuilder<int>(
          valueListenable: pageIndex,
          builder: (ctx, idx, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == idx ? 10 : 8,
                  height: i == idx ? 10 : 8,
                  decoration: BoxDecoration(color: i == idx ? const Color(0xFF1F6F67) : const Color(0xFFCEE0DE), borderRadius: BorderRadius.circular(6)),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _analyticsPreviewMock() {
    final bars = [0.6, 0.9, 0.4, 0.7, 0.5];
    final colors = [Color(0xFF7FB7AE), Color(0xFFE8B36A), Color(0xFFB37DD4), Color(0xFF4FA1D9), Color(0xFFF1A45A)];
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(bars.length, (i) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: 140 * bars[i],
                    decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(8)),
                  ),
                  const SizedBox(height: 8),
                  Text(['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'][i], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  void _showUpgradeDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF9ED),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.workspace_premium_rounded, size: 42, color: Color(0xFFE9C56D)),
              const SizedBox(height: 12),
              Text(
                widget.locale.languageCode == 'en' ? 'Upgrade to Premium' : 'Обновить до Premium',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF173B3F)),
              ),
              const SizedBox(height: 10),
              Text(
                widget.locale.languageCode == 'en'
                    ? 'Unlock more than 5 routines, analytics and reminders.'
                    : 'Откройте более 5 привычек, аналитику и напоминания.',
                style: const TextStyle(color: Color(0xFF708383), height: 1.5),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  if (Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) => _showProfileDialog());
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1F6F67),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(widget.locale.languageCode == 'en' ? 'Upgrade' : 'Обновить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddTasbihDialog() {
    final nameCtl = TextEditingController();
    final targetCtl = TextEditingController(text: '33');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(widget.locale.languageCode == 'en' ? 'Add Tasbih' : 'Добавить тасбих'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtl, decoration: InputDecoration(labelText: widget.locale.languageCode == 'en' ? 'Name' : 'Название')),
            const SizedBox(height: 8),
            TextField(controller: targetCtl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: widget.locale.languageCode == 'en' ? 'Target' : 'Цель')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(widget.locale.languageCode == 'en' ? 'Cancel' : 'Отмена')),
          FilledButton(
            onPressed: () {
              final dialogNavigator = Navigator.of(ctx);
              final name = nameCtl.text.trim();
              final target = int.tryParse(targetCtl.text) ?? 33;
              if (name.isNotEmpty) {
                setState(() {
                  _tasbihs.add(TasbihCounter(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, count: 0, target: target));
                });
                _saveState().then((_) {
                  if (mounted) dialogNavigator.pop();
                });
              }
            },
            child: Text(widget.locale.languageCode == 'en' ? 'Add' : 'Добавить'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordPrayer(String name, int minutes, String reason) async {
    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
    setState(() {
      _prayerHistory[name] = (_prayerHistory[name] ?? 0) + 1;
      _timeSpent[name] = (_timeSpent[name] ?? 0) + minutes;
      final day = _prayerRecords[dateKey] ?? {};
      day[name] = {
        'done': true,
        'timeMinutes': minutes,
        'reason': reason,
        'timestamp': today.millisecondsSinceEpoch,
      };
      _prayerRecords[dateKey] = day;
    });
    await _saveState();
  }

  // ignore: unused_element
  void _startTimer(String name) {
    setState(() {
      _activeTimerStarts[name] = DateTime.now().millisecondsSinceEpoch;
    });
    // persist immediately so restart keeps timers
    _saveState();
  }

  // ignore: unused_element
  Future<void> _stopTimer(String name) async {
    final startMs = _activeTimerStarts[name];
    if (startMs == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final minutes = ((now - startMs) / 60000).round();
    setState(() => _activeTimerStarts.remove(name));
    // persist removal
    await _saveState();

    // Ask user to confirm reason / adjust minutes before saving
    int adjustMinutes = minutes.clamp(1, 999);
    String reason = 'Timer';
    if (!mounted) return;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final minutesCtl = TextEditingController(text: adjustMinutes.toString());
        String selReason = reason;
        return StatefulBuilder(builder: (ctx2, setState2) {
          return AlertDialog(
            title: Text('$name — ${AppStrings.text(ctx, 'save')}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Recorded approx: $minutes min'),
                const SizedBox(height: 8),
                TextField(controller: minutesCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                                  initialValue: selReason,
                  items: ['Timer', 'Quick 5', 'Reading Quran', 'In congregation', 'Other']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setState2(() => selReason = v ?? selReason),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx2, false), child: Text(AppStrings.text(ctx2, 'cancel'))),
              FilledButton(onPressed: () {
                adjustMinutes = int.tryParse(minutesCtl.text.trim()) ?? adjustMinutes;
                reason = selReason;
                Navigator.pop(ctx2, true);
              }, child: Text(AppStrings.text(ctx2, 'save'))),
            ],
          );
        });
      },
    );

    if (res == true) {
      await _recordPrayer(name, adjustMinutes, reason);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name: $adjustMinutes min')));
    }
  }


  Future<void> _showHabitEditorDialog({HabitItem? existing}) async {
    final max = _premiumUnlocked ? 100 : 5;
    if (existing == null && _habits.length >= max) {
      _showUpgradeDialog();
      return;
    }

    final titleController = TextEditingController(text: existing?.title ?? '');
    final minutesController = TextEditingController(text: (existing?.minutes ?? 15).toString());
    final timeController = TextEditingController(text: existing?.time ?? '08:00');
    String frequency = existing?.frequency ?? 'Daily';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? AppStrings.text(ctx, 'add_habit') : (widget.locale.languageCode == 'en' ? 'Edit habit' : 'Редактировать рутину')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: AppStrings.text(ctx, 'habit_name'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minutesController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: widget.locale.languageCode == 'en' ? 'Minutes' : 'Минут',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: timeController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: widget.locale.languageCode == 'en' ? 'Time' : 'Время',
                          suffixIcon: const Icon(Icons.access_time_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                              hour: int.tryParse(timeController.text.split(':')[0]) ?? 8,
                              minute: int.tryParse(timeController.text.split(':')[1]) ?? 0,
                            ),
                          );
                          if (picked != null) {
                            timeController.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: frequency,
                  decoration: InputDecoration(
                    labelText: widget.locale.languageCode == 'en' ? 'Schedule' : 'Расписание',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => frequency = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.text(ctx, 'cancel'))),
            FilledButton(
              onPressed: () {
                final dialogNavigator = Navigator.of(ctx);
                final text = titleController.text.trim();
                final minutes = int.tryParse(minutesController.text) ?? 15;
                final currentTime = timeController.text.trim().isEmpty ? '08:00' : timeController.text.trim();
                if (text.isNotEmpty) {
                  final item = HabitItem(
                    id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                    title: text,
                    subtitle: '$minutes min • ${frequency == 'Daily' ? (widget.locale.languageCode == 'en' ? 'Daily' : 'Ежедневно') : (widget.locale.languageCode == 'en' ? 'Weekly' : 'Еженедельно')}',
                    done: existing?.done ?? false,
                    minutes: minutes,
                    time: currentTime,
                    frequency: frequency,
                  );
                  setState(() {
                    if (existing == null) {
                      _habits.add(item);
                    } else {
                      final index = _habits.indexWhere((element) => element.id == existing.id);
                      if (index >= 0) _habits[index] = item;
                    }
                  });
                  _saveState().then((_) {
                    if (mounted) dialogNavigator.pop();
                  });
                } else {
                  dialogNavigator.pop();
                }
              },
              child: Text(AppStrings.text(ctx, 'save')),
            )
          ],
        ),
      ),
    );
  }

  void _showAddHabitDialog() => _showHabitEditorDialog();

  Future<void> _showLanguageDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Language / Язык'),
        children: [
          ListTile(
            title: const Text('Русский'),
            trailing: widget.locale.languageCode == 'ru' ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.pop(ctx, 'ru'),
          ),
          ListTile(
            title: const Text('English'),
            trailing: widget.locale.languageCode == 'en' ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.pop(ctx, 'en'),
          ),
        ],
      ),
    );
    if (selected != null && selected != widget.locale.languageCode) {
      widget.onLocaleChanged(Locale(selected));
    }
  }

  Widget _home() {
    return FutureBuilder<PrayerData>(
      future: _prayerFuture,
      builder: (context, snap) {
        final data = snap.data ?? PrayerData.fallback();
        final customTimes = _readCustomTimesFromPrefs();
        final progress = (_zikrCount / _target).clamp(0.0, 1.0).toDouble();
        final greeting = widget.locale.languageCode == 'en' ? 'Assalamu alaikum' : 'Ассаламу алейкум';
        final nextPrayerText = data.getNextPrayerLabel(customTimes: customTimes);
        final todayPrayerCount = _prayerHistory.values.fold<int>(0, (sum, value) => sum + value);
        final totalMinutes = _timeSpent.values.fold<int>(0, (sum, value) => sum + value);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            if (!_premiumUnlocked)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF0E6B8), Color(0xFFEFD97A)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Color(0x1AFFD97A), blurRadius: 18, offset: Offset(0, 8))],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: Color(0xFF8A6A20), size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.locale.languageCode == 'en'
                            ? 'Premium: unlock analytics, reminders and more routines.'
                            : 'Premium: откройте аналитику, напоминания и более 5 привычек.',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF4F3A00)),
                      ),
                    ),
                    TextButton(
                      onPressed: _showPremiumDialog,
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF4F3A00)),
                      child: Text(widget.locale.languageCode == 'en' ? 'Join' : 'Подключить'),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFDCEEEB),
                  child: Text(_userName.substring(0, 1).toUpperCase(), style: const TextStyle(color: Color(0xFF1F6F67), fontWeight: FontWeight.w900, fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(greeting, style: const TextStyle(color: Color(0xFF7A8D8F), fontSize: 13, letterSpacing: 0.2)),
                      Text(_userName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: _premiumUnlocked
                        ? const LinearGradient(colors: [Color(0xFFE9C56D), Color(0xFFB8842D)])
                        : const LinearGradient(colors: [Color(0xFFE8F3F2), Color(0xFFDCEEEB)]),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.workspace_premium_rounded, size: 14, color: _premiumUnlocked ? Colors.white : const Color(0xFF8A6A20)),
                      const SizedBox(width: 4),
                      Text(
                        _premiumUnlocked ? AppStrings.text(context, 'premium') : AppStrings.text(context, 'basic'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _premiumUnlocked ? Colors.white : const Color(0xFF8A6A20),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1F6F67), Color(0xFF2B7E7A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Color(0x1A1F6F67), blurRadius: 20, offset: Offset(0, 12))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.nightlight_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.locale.languageCode == 'en' ? 'Next prayer' : 'Следующий намаз',
                          style: const TextStyle(color: Color(0xFFD8F4F0), fontSize: 12, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          nextPrayerText,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _glassCard(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.locale.languageCode == 'en' ? 'Daily goal' : 'Ежедневная цель', style: const TextStyle(fontSize: 12, color: Color(0xFF708383))),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text('$_zikrCount', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
                            const SizedBox(width: 4),
                            Text('/ $_target', style: const TextStyle(fontSize: 14, color: Color(0xFF6D7D80))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: const Color(0xFFE8F1F0), color: const Color(0xFF1F6F67)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _glassCard(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.locale.languageCode == 'en' ? 'Prayers' : 'Намазы', style: const TextStyle(fontSize: 12, color: Color(0xFF708383))),
                        const SizedBox(height: 8),
                        Text('$todayPrayerCount', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
                        const SizedBox(height: 4),
                        Text(widget.locale.languageCode == 'en' ? 'counted today' : 'подсчитано сегодня', style: const TextStyle(fontSize: 11, color: Color(0xFF6D7D80))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _glassCard(
              color: const Color(0xFF1F6F67),
              child: Row(
                children: [
                  const Icon(Icons.timer_rounded, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.locale.languageCode == 'en' ? 'Time spent' : 'Потраченное время', style: const TextStyle(color: Color(0xFFD8F4F0), fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('$totalMinutes min', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(AppStrings.text(context, 'quick_actions'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _actionTile(icon: Icons.touch_app_rounded, label: AppStrings.text(context, 'tasbih'), onTap: () => setState(() => _selectedIndex = 1))),
                const SizedBox(width: 12),
                Expanded(child: _actionTile(icon: Icons.mosque_rounded, label: AppStrings.text(context, 'prayer_time'), onTap: () => setState(() => _selectedIndex = 2))),
              ],
            ),
            const SizedBox(height: 24),
            Text(AppStrings.text(context, 'today_habits'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
            const SizedBox(height: 12),
            ..._habits.take(_premiumUnlocked ? _habits.length : 5).map((habit) => _habitTile(
                  title: habit.title,
                  subtitle: habit.subtitle,
                  done: habit.done,
                  minutes: habit.minutes,
                  time: habit.time,
                  frequency: habit.frequency,
                  onTap: () {
                    setState(() => habit.done = !habit.done);
                    _saveState();
                  },
                  onEdit: () => _showHabitEditorDialog(existing: habit),
                )),
          ],
        );
      },
    );
  }

  Widget _tasbih() {
    final visible = _premiumUnlocked ? _tasbihs : (_tasbihs.isNotEmpty ? [_tasbihs.first] : <TasbihCounter>[]); // free users see only the first tasbih

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1F6F67), Color(0xFF2B7E7A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.text(context, 'dhikr_label'), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                // Show selected tasbih prominently (free users see only one)
                Builder(builder: (ctx) {
                  final selected = _tasbihs.firstWhere((t) => t.id == (_selectedTasbihId ?? (_tasbihs.isNotEmpty ? _tasbihs.first.id : '')), orElse: () => _tasbihs.isNotEmpty ? _tasbihs.first : TasbihCounter(id: '0', name: AppStrings.text(ctx, 'dhikr_label'), count: 0, target: 33));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.locale.languageCode == 'en' ? 'Selected' : 'Выбранный', style: const TextStyle(color: Color(0xFFD8F4F0), fontSize: 12)),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(selected.name, style: const TextStyle(color: Color(0xFFD8F4F0), fontSize: 16, fontWeight: FontWeight.w700)),
                          Text('${selected.count}', style: const TextStyle(color: Color(0xFFD8F4F0), fontSize: 28, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ...visible.map((counter) {
            final isSelected = counter.id == (_selectedTasbihId ?? (_tasbihs.isNotEmpty ? _tasbihs.first.id : null));
            final canInteract = _premiumUnlocked || isSelected;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE7EFEE)),
                boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 6))],
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          InkWell(
                            onTap: () {
                              if (_premiumUnlocked) {
                                setState(() {
                                  _selectedTasbihId = counter.id;
                                  _prefs.setString('selected_tasbih', counter.id);
                                });
                              } else {
                                if (isSelected) return; // already selected
                                _showPremiumDialog();
                              }
                            },
                            child: Text(counter.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF173B3F))),
                          ),
                          Text('${counter.count} / ${counter.target}', style: const TextStyle(color: Color(0xFF738A8C), fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: canInteract
                            ? () {
                                setState(() => counter.count++);
                                _zikrCount++;
                                _saveState();
                              }
                            : _showPremiumDialog,
                        child: Container(
                          width: double.infinity,
                          height: 112,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE9F7F4), Color(0xFFDDEFEA)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Center(child: Text(counter.count.toString(), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Color(0xFF1F6F67)))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: canInteract
                                ? () {
                                    setState(() => counter.count = 0);
                                    _saveState();
                                  }
                                : null,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(AppStrings.text(context, 'reset')),
                          ),
                          Expanded(
                            child: Slider(
                              activeColor: const Color(0xFF1F6F67),
                              inactiveColor: const Color(0xFFDCEEEB),
                              value: counter.target.toDouble(),
                              min: 10,
                              max: 100,
                              divisions: 18,
                              label: counter.target.toString(),
                              onChanged: canInteract ? (v) { setState(() => counter.target = v.round()); _saveState(); } : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (!canInteract)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                        child: Center(child: Icon(Icons.lock_rounded, color: Colors.white70, size: 36)),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _premiumUnlocked
                ? OutlinedButton.icon(
                    onPressed: _showAddTasbihDialog,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(widget.locale.languageCode == 'en' ? 'Add tasbih' : 'Добавить тасбих'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1F6F67),
                      side: const BorderSide(color: Color(0xFFCEE0DE)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: _showPremiumDialog,
                    icon: const Icon(Icons.workspace_premium_rounded),
                    label: Text(AppStrings.text(context, 'activate_premium')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1F6F67),
                      side: const BorderSide(color: Color(0xFFCEE0DE)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _prayerMenu() {
    return FutureBuilder<PrayerData>(
      future: _prayerFuture,
      builder: (context, snap) {
        final data = snap.data ?? PrayerData.fallback();
        final engOrder = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
        // build entries with english key, localized label and time; sort by 24h time
        final entries = engOrder.map((eng) {
          final localized = AppStrings.text(context, eng.toLowerCase());
          final t = _customTimes[eng] ?? data.times[eng] ?? '00:00';
          IconData icon;
          switch (eng) {
            case 'Fajr':
              icon = Icons.wb_twilight_rounded;
              break;
            case 'Dhuhr':
              icon = Icons.wb_sunny_rounded;
              break;
            case 'Asr':
              icon = Icons.wb_sunny_rounded;
              break;
            case 'Maghrib':
              icon = Icons.nightlight_rounded;
              break;
            default:
              icon = Icons.dark_mode_rounded;
          }
          return {'eng': eng, 'label': localized, 'time': t, 'icon': icon};
        }).toList();

        int parseMinutes(String hhmm) {
          try {
            final parts = hhmm.split(':');
            final h = int.parse(parts[0]);
            final m = int.parse(parts[1]);
            return h * 60 + m;
          } catch (_) {
            return 0;
          }
        }

        entries.sort((a, b) => parseMinutes(a['time'] as String).compareTo(parseMinutes(b['time'] as String)));

        final prayerSummary = Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1F6F67), Color(0xFF2B7E7A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.locale.languageCode == 'en' ? 'Today’s prayer schedule' : 'Расписание намаза на сегодня',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: entries.map((entry) {
                  final prayerName = entry['label'] as String;
                  final time = entry['time'] as String;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(entry['icon'] as IconData, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(prayerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Text(time, style: const TextStyle(color: Color(0xFFD9F5F2), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );

        // Prayer menu: show main cards which open nested section pages
        final sections = [
          {
            'title': widget.locale.languageCode == 'en' ? 'Prayer times' : 'Время намаза',
            'subs': [
              widget.locale.languageCode == 'en' ? "Today's schedule" : 'Расписание на сегодня',
              widget.locale.languageCode == 'en' ? 'Adjust times' : 'Настроить время',
              widget.locale.languageCode == 'en' ? 'Azan settings' : 'Настройки азана',
            ],
            'color': const Color(0xFF1F6F67),
            'icon': Icons.schedule_rounded,
          },
          {
            'title': widget.locale.languageCode == 'en' ? 'Time spent (24h)' : 'Время (24ч)',
            'subs': [
              widget.locale.languageCode == 'en' ? '24h breakdown' : 'Разбивка 24ч',
              widget.locale.languageCode == 'en' ? 'Suggestions' : 'Рекомендации',
              widget.locale.languageCode == 'en' ? 'Edit intervals' : 'Редактировать интервалы',
            ],
            'color': const Color(0xFF6DA6B5),
            'icon': Icons.timer_rounded,
          },
          {
            'title': widget.locale.languageCode == 'en' ? 'Qaza & Missed' : 'Каза и пропущенные',
            'subs': [
              widget.locale.languageCode == 'en' ? 'Manage missed prayers' : 'Управлять пропущенными',
              widget.locale.languageCode == 'en' ? 'Mark Qaza done' : 'Отметить каза',
              widget.locale.languageCode == 'en' ? 'Schedule makeups' : 'Планировать наверстывания',
            ],
            'color': const Color(0xFFB58B35),
            'icon': Icons.pending_actions_rounded,
          },
          {
            'title': widget.locale.languageCode == 'en' ? 'Records & Analytics' : 'Записи и аналитика',
            'subs': [
              widget.locale.languageCode == 'en' ? 'Daily records' : 'Ежедневные записи',
              widget.locale.languageCode == 'en' ? 'Weekly / Monthly' : 'Недельная / Месячная',
              widget.locale.languageCode == 'en' ? 'Export / Backup' : 'Экспорт / Резерв',
            ],
            'color': const Color(0xFF2E7D73),
            'icon': Icons.bar_chart_rounded,
          },
          {
            'title': widget.locale.languageCode == 'en' ? 'Dhikr & Tasbih' : 'Зикр и тасбих',
            'subs': [
              widget.locale.languageCode == 'en' ? 'Quick zikr' : 'Быстрый зикр',
              widget.locale.languageCode == 'en' ? 'Your tasbihs' : 'Ваши тасбихи',
              widget.locale.languageCode == 'en' ? 'Add new' : 'Добавить',
            ],
            'color': const Color(0xFF7A5AB7),
            'icon': Icons.self_improvement_rounded,
          }
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const SizedBox(height: 6),
            prayerSummary,
            const SizedBox(height: 12),
            for (final s in sections)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      (s['color'] as Color).withValues(alpha: 0.14),
                      Colors.white,
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE7EFEE)),
                  boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10, offset: Offset(0, 6))],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () async {
                    final title = s['title'] as String;
                    final subs = List<String>.from(s['subs'] as List);
                    final changed = await Navigator.push(context, MaterialPageRoute(builder: (_) => pm.PrayerSectionPage(title: title, submenus: subs, locale: widget.locale)));
                    // Always attempt to refresh custom times and reschedule after returning from the section page.
                    // Child pages (Edit intervals) return `true` when they intentionally changed times, but other
                    // interactions (Apply suggestions) may modify prefs without returning true — so refresh unconditionally.
                    try {
                      // reload any custom times saved by child pages
                      _customTimes = _readCustomTimesFromPrefs();

                      // reload analytics-related data from SharedPreferences so Charts/Records update
                      try {
                        final prefs = await SharedPreferences.getInstance();

                        // prayer_history -> Map<String,int>
                        try {
                          final hist = prefs.getString('prayer_history');
                          if (hist != null) {
                            final Map m = jsonDecode(hist);
                            _prayerHistory = m.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
                          }
                        } catch (_) {}

                        // time_spent -> Map<String,int>
                        try {
                          final t = prefs.getString('time_spent');
                          if (t != null) {
                            final Map m = jsonDecode(t);
                            _timeSpent = m.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
                          }
                        } catch (_) {}

                        // prayer_records -> Map<String, Map<String, Map<String,dynamic>>>
                        try {
                          final rec = prefs.getString('prayer_records');
                          if (rec != null) {
                            final Map m = jsonDecode(rec);
                            _prayerRecords = m.map((date, v) {
                              final sub = <String, Map<String, dynamic>>{};
                              try {
                                final Map vv = v as Map;
                                vv.forEach((k2, v2) {
                                  sub[k2.toString()] = Map<String, dynamic>.from(v2 as Map);
                                });
                              } catch (_) {}
                              return MapEntry(date.toString(), sub);
                            });
                          }
                        } catch (_) {}

                        // ensure prayer data is refreshed too
                        _prayerFuture = PrayerData.load();

                        if (mounted) setState(() {});
                      } catch (e) {
                        debugPrint('Failed to reload prefs after prayer section: $e');
                      }

                      await _rescheduleAllPrayerNotifications();
                    } catch (e) {
                      debugPrint('Failed to refresh after prayer section: $e');
                    }
                  },

                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: s['color'] as Color,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(s['icon'] as IconData, color: Colors.white, size: 25),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF173B3F))),
                            const SizedBox(height: 8),
                            Text((s['subs'] as List<String>).join(' • '), style: const TextStyle(color: Color(0xFF708383), fontSize: 12.5, height: 1.4)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF1F6F67), size: 28),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _habitsPage() {
    final visible = _premiumUnlocked ? _habits : _habits.take(5).toList();
    final doneCount = visible.where((habit) => habit.done).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
          ),
          child: Row(
            children: [
              const Icon(Icons.checklist_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.text(context, 'habit_title'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      widget.locale.languageCode == 'en' ? '$doneCount routines completed' : '$doneCount рутины выполнены',
                      style: const TextStyle(color: Color(0xFFD8F4F0), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...visible.map((habit) => _habitTile(
              title: habit.title,
              subtitle: habit.subtitle,
              done: habit.done,
              minutes: habit.minutes,
              time: habit.time,
              frequency: habit.frequency,
              onTap: () {
                setState(() => habit.done = !habit.done);
                _saveState();
              },
              onEdit: () => _showHabitEditorDialog(existing: habit),
            )),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _premiumUnlocked ? _showAddHabitDialog : _showUpgradeDialog,
            icon: const Icon(Icons.add_rounded),
            label: Text(AppStrings.text(context, 'add_habit')),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1F6F67),
              side: const BorderSide(color: Color(0xFFCEE0DE)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _analytics() {
    final totalPrayers = _prayerHistory.values.fold<int>(0, (s, v) => s + v);
    final totalMinutes = _timeSpent.values.fold<int>(0, (s, v) => s + v);

    // Show limited summary for all users; full detailed analytics are premium-only
    final summary = ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Text(AppStrings.text(context, 'analytics_title'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1F6F67), Color(0xFF2B7E7A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [BoxShadow(color: Color(0x1A1F6F67), blurRadius: 16, offset: Offset(0, 10))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppStrings.text(context, 'this_week'), style: const TextStyle(color: Color(0xFFD8F4F0), fontSize: 14)),
              const SizedBox(height: 8),
              Text('$totalPrayers ${widget.locale.languageCode == 'en' ? 'prayers' : 'намазов'}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _prayerHistory.entries.map((entry) {
                  final value = entry.value.clamp(0, 7).toDouble() * 10;
                  return Column(
                    children: [
                      Container(
                        width: 12,
                        height: value.clamp(18.0, 70.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9C56D),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(entry.key.substring(0, 2), style: const TextStyle(fontSize: 11, color: Color(0xFFD9F5F2))),
                    ],
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _statTile(title: AppStrings.text(context, 'avg_daily'), value: '${(totalMinutes / 7).round()} min', icon: Icons.access_time_rounded),
        const SizedBox(height: 12),
        _statTile(title: widget.locale.languageCode == 'en' ? 'Prayer count' : 'Количество намазов', value: totalPrayers.toString(), icon: Icons.mosque_rounded),
      ],
    );

    if (_premiumUnlocked) {
      final records = _getRecordsForRange(_analyticsRangeDays);
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppStrings.text(context, 'analytics_title'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F6F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ToggleButtons(
                  renderBorder: false,
                  fillColor: const Color(0xFF1F6F67),
                  selectedColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  color: const Color(0xFF1F6F67),
                  isSelected: [_analyticsRangeDays == 7, _analyticsRangeDays == 30, _analyticsRangeDays == 90],
                  onPressed: (i) => setState(() => _analyticsRangeDays = i == 0 ? 7 : i == 1 ? 30 : 90),
                  children: const [
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('7d')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('30d')),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('90d')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x0F1F6F67), blurRadius: 16, offset: Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.locale.languageCode == 'en' ? 'Prayer performance' : 'Эффективность намаза', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
                const SizedBox(height: 8),
                SizedBox(height: 220, child: _buildStackedPrayerChart(_analyticsRangeDays)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _statTile(title: AppStrings.text(context, 'avg_daily'), value: '${(totalMinutes / _analyticsRangeDays).round()} min', icon: Icons.access_time_rounded)),
                    const SizedBox(width: 10),
                    Expanded(child: _statTile(title: widget.locale.languageCode == 'en' ? 'Prayer count' : 'Количество намазов', value: totalPrayers.toString(), icon: Icons.mosque_rounded)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.locale.languageCode == 'en' ? 'Recent records' : 'Недавние записи', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
          const SizedBox(height: 8),
          ...records.entries.map((entry) {
            final date = entry.key;
            final dayMap = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE3EAE9)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
                  const SizedBox(height: 8),
                  ...dayMap.entries.map((e) {
                    final pName = e.key;
                    final data = e.value;
                    final mins = data['timeMinutes'] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text(pName, style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text('$mins min', style: const TextStyle(color: Color(0xFF1F6F67), fontWeight: FontWeight.w700)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      );
    }

    // Not premium: show summary plus locked details CTA
    return Column(
      children: [
        Expanded(child: summary),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, size: 36, color: Color(0xFF1F6F67)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.locale.languageCode == 'en' ? 'Premium analytics' : 'Премиум-аналитика', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(widget.locale.languageCode == 'en' ? 'Unlock detailed prayer history, time breakdowns and trends.' : 'Откройте подробную историю, разбивку времени и тренды.', style: const TextStyle(color: Color(0xFF708383))),
                    ],
                  ),
                ),
                FilledButton(onPressed: _showProfileDialog, child: Text(AppStrings.text(context, 'activate_premium'))),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildStackedPrayerChart(int days) {
    // build stacked bars for last `days` days (most recent first)
    final order = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    final colors = [Color(0xFF7FB7AE), Color(0xFF91D3C9), Color(0xFF6FA8A0), Color(0xFF4A8C86), Color(0xFF2F6F67)];

    final now = DateTime.now();
    final daysList = List.generate(days, (i) => now.subtract(Duration(days: i))).reversed.toList(); // oldest -> newest

    final groups = <BarChartGroupData>[];
    final bottomTitles = <String>[];
    double maxY = 1.0;

    for (var di = 0; di < daysList.length; di++) {
      final d = daysList[di];
      final key = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      bottomTitles.add('${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}');
      final dayMap = _prayerRecords[key] ?? {};
      // collect minutes per prayer in order
      final minutes = order.map((p) => (dayMap[p]?['timeMinutes'] as num?)?.toDouble() ?? 0.0).toList();
      double running = 0.0;
      final stackItems = <BarChartRodStackItem>[];
      for (var i = 0; i < minutes.length; i++) {
        final m = minutes[i];
        if (m <= 0) continue;
        stackItems.add(BarChartRodStackItem(running, running + m, colors[i]));
        running += m;
      }
      if (running > maxY) maxY = running;
      // if no stack items, add a tiny invisible bar to keep axis
      final rod = BarChartRodData(toY: running, rodStackItems: stackItems, width: 18);
      groups.add(BarChartGroupData(x: di, barRods: [rod]));
    }

    // adapt bottom labels to available width: show fewer labels on narrow screens
    final labelCount = bottomTitles.length;
    final width = MediaQuery.of(context).size.width;
    final approxLabelWidth = 56; // approx space per label in pixels
    final maxLabels = (width / approxLabelWidth).floor().clamp(3, labelCount == 0 ? 3 : labelCount);
    final step = maxLabels > 0 ? (labelCount / maxLabels).ceil() : 1;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxY + 5.0,
        barGroups: groups,
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: (maxY / 4).clamp(1.0, double.infinity))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) {
            final idx = v.toInt();
            if (idx < 0 || idx >= bottomTitles.length) return const SizedBox.shrink();
            // If too many labels, only show every `step`-th label
            if (labelCount > maxLabels && (idx % step != 0)) return const SizedBox.shrink();
            final label = bottomTitles[idx];
            return SideTitleWidget(
              meta: meta,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SizedBox(
                  height: 30,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ),
            );
          }, reservedSize: 44)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: (maxY / 4).clamp(1.0, double.infinity)),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  // Return a map of date -> dayMap for the last `days` days (descending)
  Map<String, Map<String, Map<String, dynamic>>> _getRecordsForRange(int days) {
    final out = <String, Map<String, Map<String, dynamic>>>{};
    final now = DateTime.now();
    for (int i = 0; i < days; i++) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      if (_prayerRecords.containsKey(key)) out[key] = _prayerRecords[key]!;
    }
    return out;
  }

  Widget _actionTile({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7EFEE)),
          boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 12, offset: Offset(0, 6))],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFE8F6F3), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, size: 28, color: const Color(0xFF1F6F67)),
            ),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF173B3F))),
          ],
        ),
      ),
    );
  }

  Widget _habitTile({
    required String title,
    required String subtitle,
    required bool done,
    required int minutes,
    required String time,
    required String frequency,
    required VoidCallback onTap,
    required VoidCallback onEdit,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EBEA)),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 6))],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFE9F7F4), Color(0xFFDDEFEA)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.checklist_rounded, color: Color(0xFF1F6F67), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF173B3F)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF738A8C), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _miniChip(label: '$minutes min'),
                      _miniChip(label: time),
                      _miniChip(label: frequency),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, color: Color(0xFF1F6F67)),
                splashRadius: 18,
              ),
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(999),
                child: Icon(
                  done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: done ? const Color(0xFF1F6F67) : const Color(0xFFB5C3C5),
                  size: 28,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniChip({required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F6F3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1F6F67))),
    );
  }

  Widget _featureRow({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1F6F67)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF4B5A5E), fontSize: 13))),
        ],
      ),
    );
  }

  Widget _premiumPreviewCard({required IconData icon, required String title, required String subtitle}) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E9E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE9F7F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF1F6F67), size: 22),
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF173B3F), fontSize: 13)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xFF708383), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _statTile({required String title, required String value, required IconData icon}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: const Color(0xFFDDEFEA), child: Icon(icon, color: const Color(0xFF1F6F67))),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF173B3F))),
      ),
    );
  }

  Widget _glassCard({required Color color, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x0F1F6F67), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: child,
    );
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      AppStrings.text(context, 'home'),
      AppStrings.text(context, 'tasbih'),
      AppStrings.text(context, 'prayer'),
      AppStrings.text(context, 'habits'),
      AppStrings.text(context, 'analytics'),
    ];
    final pages = [_home(), _tasbih(), _prayerMenu(), _habitsPage(), _analytics()];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F3EE),
        foregroundColor: const Color(0xFF173B3F),
        elevation: 0,
        title: Text(labels[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
        actions: [
          IconButton(onPressed: _showProfileDialog, icon: const Icon(Icons.account_circle_outlined)),
          IconButton(onPressed: _showLanguageDialog, icon: const Icon(Icons.language_rounded)),
        ],
      ),
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(26), topRight: Radius.circular(26)),
          boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, -4))],
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          height: 70,
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.touch_app_outlined), selectedIcon: Icon(Icons.touch_app_rounded), label: 'Tasbih'),
            NavigationDestination(icon: Icon(Icons.mosque_outlined), selectedIcon: Icon(Icons.mosque_rounded), label: 'Prayer'),
            NavigationDestination(icon: Icon(Icons.checklist_rounded), selectedIcon: Icon(Icons.checklist_rounded), label: 'Habits'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Analytics'),
          ],
        ),
      ),
    );
  }
}

class AppStrings {
  static const Map<String, Map<String, String>> _data = {
    'ru': {
      'home': 'Главная',
      'tasbih': 'Тасбих',
      'prayer': 'Намаз',
      'habits': 'Рутины',
      'analytics': 'Аналитика',
      'premium': 'Премиум',
      'basic': 'Базовый',
      'daily_goal': 'Ежедневная цель',
      'quick_actions': 'Быстрые действия',
      'today_habits': 'Сегодняшние рутины',
      'dhikr_label': 'Субханаллах',
      'reset': 'Сброс',
      'target': 'Цель',
      'fajr': 'Фаджр',
      'dhuhr': 'Зухр',
      'asr': 'Аср',
      'maghrib': 'Магриб',
      'isha': 'Иша',
      'next_prayer': 'Следующий намаз',
      'prayer_schedule': 'Расписание намаза',
      'habit_title': 'Рутины',
            'add_habit': 'Добавить рутину',
            'habit_name': 'Название рутины',
      'analytics_title': 'Ваша активность',
      'this_week': 'Эта неделя',
      'avg_daily': 'Среднее за день',
      'activate_premium': 'Активировать Premium',
      'prayer_time': 'Время намаза',
      'account': 'Аккаунт',
      'name': 'Имя',
      'email': 'Email',
      'save': 'Сохранить',
      'cancel': 'Отмена',
    },
    'en': {
      'home': 'Home',
      'tasbih': 'Tasbih',
      'prayer': 'Prayer',
      'habits': 'Routines',
      'analytics': 'Analytics',
      'premium': 'Premium',
      'basic': 'Basic',
      'daily_goal': 'Daily goal',
      'quick_actions': 'Quick actions',
      'today_habits': 'Today’s routines',
      'dhikr_label': 'SubhanAllah',
      'reset': 'Reset',
      'target': 'Target',
      'fajr': 'Fajr',
      'dhuhr': 'Dhuhr',
      'asr': 'Asr',
      'maghrib': 'Maghrib',
      'isha': 'Isha',
      'next_prayer': 'Next prayer',
      'prayer_schedule': 'Prayer schedule',
      'habit_title': 'Routines',
            'add_habit': 'Add routine',
            'habit_name': 'Routine name',
      'analytics_title': 'Your activity',
      'this_week': 'This week',
      'avg_daily': 'Average per day',
      'activate_premium': 'Activate Premium',
      'prayer_time': 'Prayer time',
      'account': 'Account',
      'name': 'Name',
      'email': 'Email',
      'save': 'Save',
      'cancel': 'Cancel',
    },
  };

  static String text(BuildContext context, String key) {
    final locale = Localizations.localeOf(context).languageCode;
    return _data[locale]?[key] ?? _data['ru']?[key] ?? key;
  }
}

class PrayerSlot {
  const PrayerSlot({required this.name, required this.time, required this.icon});
  final String name;
  final String time;
  final IconData icon;
}
