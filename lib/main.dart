import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String backendUrl = 'https://aquasense-ai-backend-gtle.onrender.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AquaSenseAI());
}

class WaterProfile {
  final String name;
  final double ph;
  final double tds;
  final double turbidity;
  final String recommendation;

  const WaterProfile({
    required this.name,
    required this.ph,
    required this.tds,
    required this.turbidity,
    required this.recommendation,
  });
}

// Live values are populated only from the backend response.
WaterProfile liveProfile = const WaterProfile(
  name: 'Water Profile',
  ph: 0,
  tds: 0,
  turbidity: 0,
  recommendation: 'Run an analysis to receive a recommendation.',
);


bool? _isResultSafe(Map<String, dynamic>? result) {
  if (result == null) return null;
  for (final key in ['assessment', 'status', 'safety', 'classification', 'result', 'prediction']) {
    final candidate = result[key];
    if (candidate is String) {
      final value = candidate.toLowerCase();
      if (value.contains('unsafe') || value.contains('not safe') || value == 'contaminated') return false;
      if (value == 'safe' || value.contains('safe to drink')) return true;
    }
  }
  for (final key in ['is_safe', 'safe', 'drinkable']) {
    if (result[key] is bool) return result[key] as bool;
  }
  return null;
}

String _assessmentLabel(Map<String, dynamic>? result) {
  final safe = _isResultSafe(result);
  if (safe == true) return 'SAFE';
  if (safe == false) return 'UNSAFE';
  return 'UNABLE TO DETERMINE';
}

class AquaSenseAI extends StatefulWidget {
  const AquaSenseAI({super.key});

  @override
  State<AquaSenseAI> createState() => _AquaSenseAIState();
}

class _AquaSenseAIState extends State<AquaSenseAI> {
  bool _isDarkMode = false;

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF087F8C);
    const navy = Color(0xFF102A43);
    const lightBg = Color(0xFFF2F7FA);
    const darkBg = Color(0xFF0A192F);
    const darkCard = Color(0xFF172A45);

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        brightness: Brightness.light,
        primary: teal,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: lightBg,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        brightness: Brightness.dark,
        primary: teal,
        surface: darkCard,
      ),
      scaffoldBackgroundColor: darkBg,
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 1.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
      ),
    );

    return MaterialApp(
      title: 'AquaSense AI',
      debugShowCheckedModeBanner: false,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: SplashScreen(
        isDarkMode: _isDarkMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const SplashScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainNavigationScreen(
            isDarkMode: widget.isDarkMode,
            onToggleTheme: widget.onToggleTheme,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF102A43);
    const teal = Color(0xFF087F8C);
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [navy, teal],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(32)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Image.asset(
                  'assets/images/aquasense_logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('AquaSense AI',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Smart Water Quality Monitoring',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 32),
            const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: Colors.white)),
            const SizedBox(height: 14),
            const Text('Starting…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const MainNavigationScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class DemoProfile {
  final String name;
  final double ph;
  final double tds;
  final double turbidity;

  const DemoProfile({
    required this.name,
    required this.ph,
    required this.tds,
    required this.turbidity,
  });
}

const List<DemoProfile> demoProfiles = [
  DemoProfile(name: 'Clean Water', ph: 7.2, tds: 110.0, turbidity: 2.0),
  DemoProfile(name: 'Normal Water', ph: 7.5, tds: 160.0, turbidity: 3.0),
  DemoProfile(name: 'High Turbidity', ph: 7.2, tds: 110.0, turbidity: 10.0),
  DemoProfile(name: 'Low pH', ph: 5.6, tds: 110.0, turbidity: 2.0),
  DemoProfile(name: 'High pH', ph: 9.0, tds: 110.0, turbidity: 2.0),
  DemoProfile(name: 'High TDS', ph: 7.2, tds: 650.0, turbidity: 2.0),
];

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  Timer? _connectionTimer;
  Timer? _animationTimer;
  int selectedIndex = 0;
  double flowRate = 0;
  bool deviceConnected = false;
  bool refreshing = false;
  bool _connectionRequestInFlight = false;
  bool aiLoading = false;
  bool hasAnalysis = false;
  bool hasRefreshedAtLeastOnce = false;
  Map<String, dynamic>? aiResult;
  String? connectionMessage;
  String refreshStageMessage = 'Connecting to water monitoring system...';
  final List<Map<String, dynamic>> capturedSamples = [];

  double animatedPh = 0.0;
  double animatedTds = 0.0;
  double animatedTurbidity = 0.0;

  int _testProfileIndex = -1;

  DemoProfile get activeDemoProfile =>
      demoProfiles[_testProfileIndex < 0 ? 0 : _testProfileIndex];
  double get activeTestPh => activeDemoProfile.ph;
  double get activeTestTds => activeDemoProfile.tds;
  double get activeTestTurbidity => activeDemoProfile.turbidity;
  String get activeTestLabel => activeDemoProfile.name;

  WaterProfile get profile => liveProfile;

  double get shownPh => (deviceConnected && hasRefreshedAtLeastOnce)
      ? (refreshing ? animatedPh : liveProfile.ph)
      : 0;

  double get shownTds => (deviceConnected && hasRefreshedAtLeastOnce)
      ? (refreshing ? animatedTds : liveProfile.tds)
      : 0;

  double get shownTurbidity => (deviceConnected && hasRefreshedAtLeastOnce)
      ? (refreshing ? animatedTurbidity : liveProfile.turbidity)
      : 0;

  double get shownFlow =>
      (deviceConnected && hasRefreshedAtLeastOnce) ? flowRate : 0;

  String get turbidityDisplayString =>
      (deviceConnected && hasRefreshedAtLeastOnce)
          ? '${shownTurbidity.toStringAsFixed(1)} NTU'
          : '--';

  String get flowDisplayString =>
      (deviceConnected && hasRefreshedAtLeastOnce)
          ? '${shownFlow.toStringAsFixed(2)} L/min'
          : '--';

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();

    _connectionTimer = Timer.periodic(
      const Duration(seconds: 5),
          (_) {
        if (!refreshing) {
          _refreshConnection(showSpinner: false);
        }
      },
    );
  }

  Future<void> _checkInitialConnection() async {
    await _refreshConnection(showSpinner: false);
  }

  @override
  void dispose() {
    _connectionTimer?.cancel();
    _animationTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _getBackendSensorStatus() async {
    final response = await http
        .get(Uri.parse('$backendUrl/api/sensors'))
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Sensor status HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid sensor status response');
    }
    return decoded;
  }

  WaterProfile? _profileFromBackendData(dynamic data) {
    if (data is! Map<String, dynamic>) return null;

    final ph = data['ph'];
    final tds = data['tds'];
    final turbidity = data['turbidity'];
    final flow = data['flow_rate'];

    if (ph is! num ||
        tds is! num ||
        turbidity is! num ||
        flow is! num ||
        !ph.toDouble().isFinite ||
        !tds.toDouble().isFinite ||
        !turbidity.toDouble().isFinite ||
        !flow.toDouble().isFinite ||
        ph < 0 ||
        ph > 14 ||
        tds < 0 ||
        turbidity < 0 ||
        flow < 0) {
      return null;
    }

    final name = data['profile_name'] is String
        ? data['profile_name'] as String
        : 'Water Profile';

    return WaterProfile(
      name: name,
      ph: ph.toDouble(),
      tds: tds.toDouble(),
      turbidity: turbidity.toDouble(),
      recommendation:
      'Run an analysis to receive a recommendation based on current readings.',
    );
  }

  Future<void> _refreshConnection({bool showSpinner = true}) async {
    if (_connectionRequestInFlight) return;
    _connectionRequestInFlight = true;

    if (mounted && showSpinner) {
      setState(() => refreshing = true);
    }

    bool connected = false;
    double latestFlow = 0;
    String message = 'Device disconnected. Waiting for fresh sensor data.';
    WaterProfile? backendProfile;

    try {
      final decoded = await _getBackendSensorStatus();
      final data = decoded?['data'];

      connected = decoded?['status'] == 'connected' &&
          decoded?['device_online'] == true;

      if (connected) {
        backendProfile = _profileFromBackendData(data);
        if (backendProfile == null) {
          connected = false;
          message = 'Device connected, but backend readings are invalid.';
        } else {
          latestFlow = backendProfile.ph == 0
              ? 0
              : ((data as Map<String, dynamic>)['flow_rate'] as num).toDouble();
          message = 'Connected';
        }
      } else if (decoded?['status'] == 'stale' ||
          decoded?['device_online'] == false) {
        message = 'Device disconnected. Latest sensor data is outdated.';
      } else if (decoded?['status'] == 'no_data') {
        message = 'Device disconnected. No sensor data received yet.';
      } else {
        message = 'Device disconnected or backend status unavailable.';
      }
    } catch (_) {
      message = 'Unable to check device status. Check internet/backend.';
    } finally {
      _connectionRequestInFlight = false;
    }

    if (!mounted) return;

    setState(() {
      deviceConnected = connected;
      if (connected && backendProfile != null) {
        liveProfile = backendProfile;
        flowRate = latestFlow;
        if (_testProfileIndex < 0) {
          final found = demoProfiles.indexWhere(
                  (p) => p.name == backendProfile!.name);
          if (found >= 0) _testProfileIndex = found;
        }
      } else {
        liveProfile = const WaterProfile(
          name: 'Offline Profile',
          ph: 0,
          tds: 0,
          turbidity: 0,
          recommendation: '',
        );
        flowRate = 0;
      }
      connectionMessage = message;
      if (showSpinner) refreshing = false;
    });
  }

  Future<void> _refreshProfile() async {
    if (refreshing || _connectionRequestInFlight) return;

    // A fresh physical ESP8266 heartbeat is required before selecting a profile.
    setState(() {
      refreshing = true;
      hasAnalysis = false;
      aiResult = null;
      refreshStageMessage = 'Checking device connection...';
    });

    Map<String, dynamic>? sensorStatus;
    try {
      sensorStatus = await _getBackendSensorStatus();
    } catch (_) {
      sensorStatus = null;
    }

    final isConnected = sensorStatus != null &&
        sensorStatus['status'] == 'connected' &&
        sensorStatus['device_online'] == true;

    if (!isConnected) {
      if (!mounted) return;
      setState(() {
        deviceConnected = false;
        refreshing = false;
        connectionMessage =
        'Device disconnected. Connect ESP8266 and send fresh sensor data first.';
      });
      _showMessage('Device is offline. Cannot select a profile.');
      return;
    }

    final nextIndex = (_testProfileIndex + 1) % demoProfiles.length;
    final targetProfile = demoProfiles[nextIndex];

    final previousPh = hasRefreshedAtLeastOnce ? liveProfile.ph : 0.0;
    final previousTds = hasRefreshedAtLeastOnce ? liveProfile.tds : 0.0;
    final previousTurbidity =
    hasRefreshedAtLeastOnce ? liveProfile.turbidity : 0.0;

    setState(() {
      deviceConnected = true;
      refreshing = true;
      animatedPh = previousPh;
      animatedTds = previousTds;
      animatedTurbidity = previousTurbidity;
      refreshStageMessage = 'Sending selected profile to backend...';
    });

    try {
      final selectResponse = await http
          .post(
        Uri.parse('$backendUrl/api/profile/select'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'profile_name': targetProfile.name}),
      )
          .timeout(const Duration(seconds: 20));

      if (selectResponse.statusCode != 200) {
        throw Exception(
            'Profile selection failed (HTTP ${selectResponse.statusCode}): ${selectResponse.body}');
      }

      final selectionDecoded = jsonDecode(selectResponse.body);
      if (selectionDecoded is! Map<String, dynamic> ||
          selectionDecoded['status'] != 'selected') {
        throw Exception('Backend did not confirm profile selection.');
      }

      final selectedData = selectionDecoded['profile'];
      final selectedProfile = _profileFromBackendData(selectedData);
      if (selectedProfile == null ||
          selectedProfile.name != targetProfile.name) {
        throw Exception('Backend returned an invalid selected profile.');
      }

      // Fetch the current profile endpoint too. This verifies the same payload
      // that the ESP8266 polls for the OLED.
      final currentResponse = await http
          .get(Uri.parse('$backendUrl/api/profile/current'))
          .timeout(const Duration(seconds: 20));

      if (currentResponse.statusCode != 200) {
        throw Exception(
            'Could not verify current profile (HTTP ${currentResponse.statusCode}).');
      }

      final currentDecoded = jsonDecode(currentResponse.body);
      final verifiedProfile = _profileFromBackendData(currentDecoded);
      if (verifiedProfile == null ||
          verifiedProfile.name != targetProfile.name) {
        throw Exception('Current backend profile did not match the selection.');
      }

      final startTime = DateTime.now();
      const totalDuration = Duration(seconds: 6);
      const animationStart = Duration(seconds: 2);

      _animationTimer?.cancel();
      _animationTimer =
          Timer.periodic(const Duration(milliseconds: 50), (timer) {
            if (!mounted) {
              timer.cancel();
              return;
            }

            final elapsed = DateTime.now().difference(startTime);

            if (elapsed < animationStart) {
              setState(() {
                refreshStageMessage = 'Processing water parameters...';
              });
            } else if (elapsed < totalDuration) {
              final progress = ((elapsed - animationStart).inMilliseconds /
                  4000.0)
                  .clamp(0.0, 1.0);

              setState(() {
                refreshStageMessage = 'Updating water readings...';
                animatedPh =
                    previousPh + (verifiedProfile.ph - previousPh) * progress;
                animatedTds =
                    previousTds + (verifiedProfile.tds - previousTds) * progress;
                animatedTurbidity = previousTurbidity +
                    (verifiedProfile.turbidity - previousTurbidity) * progress;
              });
            } else {
              timer.cancel();
              _testProfileIndex = nextIndex;
              hasRefreshedAtLeastOnce = true;

              setState(() {
                liveProfile = verifiedProfile;
                flowRate = (currentDecoded['flow_rate'] as num).toDouble();
                animatedPh = verifiedProfile.ph;
                animatedTds = verifiedProfile.tds;
                animatedTurbidity = verifiedProfile.turbidity;
                refreshStageMessage = 'Profile updated successfully.';
              });

              _analyzeWaterSilent().whenComplete(() {
                if (mounted) {
                  setState(() => refreshing = false);
                }
              });
            }
          });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        refreshing = false;
        connectionMessage = 'Profile update failed: $e';
      });
      _showMessage('Could not update the selected profile. Check backend deployment.');
    }
  }

  Future<void> _analyzeWaterSilent() async {
    if (!deviceConnected || !hasRefreshedAtLeastOnce) return;

    Map<String, dynamic>? result;

    try {
      final response = await http
          .post(
        Uri.parse('$backendUrl/api/analyze'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ph': liveProfile.ph,
          'tds': liveProfile.tds,
          'turbidity': liveProfile.turbidity,
          'flow_rate': flowRate,
        }),
      )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) result = decoded;
      }
    } catch (_) {
      result = null;
    }

    if (!mounted) return;
    setState(() {
      aiResult = result;
      hasAnalysis = true;
    });
  }

  Future<void> _analyzeWater() async {
    if (!deviceConnected || !hasRefreshedAtLeastOnce || aiLoading) return;

    setState(() {
      aiLoading = true;
      hasAnalysis = false;
      aiResult = null;
    });

    Map<String, dynamic>? result;

    try {
      final response = await http
          .post(
        Uri.parse('$backendUrl/api/analyze'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ph': liveProfile.ph,
          'tds': liveProfile.tds,
          'turbidity': liveProfile.turbidity,
          'flow_rate': flowRate,
        }),
      )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> &&
            (decoded['assessment'] == 'Safe' ||
                decoded['assessment'] == 'Unsafe' ||
                decoded['assessment'] == 'Unable to Determine')) {
          result = decoded;
        }
      }
    } catch (_) {
      result = null;
    }

    if (!mounted) return;
    setState(() {
      aiResult = result;
      aiLoading = false;
      hasAnalysis = true;
    });
  }

  void _captureSample() {
    if (!deviceConnected || !hasRefreshedAtLeastOnce) {
      _showMessage('Connect the device and refresh readings before saving.');
      return;
    }

    capturedSamples.insert(0, {
      'name': liveProfile.name,
      'ph': liveProfile.ph,
      'tds': liveProfile.tds,
      'turbidity': liveProfile.turbidity,
      'flow': flowRate,
      'assessment': hasAnalysis ? _assessmentLabel(aiResult) : 'NOT ANALYZED',
      'time': DateTime.now().toLocal().toString().substring(0, 16),
      'isTest': true,
    });

    setState(() {});
    _showMessage('Sample saved (${liveProfile.name}).');
  }

  Future<void> _deleteSample(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove sample?'),
        content: const Text('This sample will be removed from the current session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => capturedSamples.removeAt(index));
      _showMessage('Sample removed.');
    }
  }

  Future<void> _clearSamples() async {
    if (capturedSamples.isEmpty) {
      _showMessage('There are no saved samples to clear.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all samples?'),
        content: const Text('This will remove every saved sample from this session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => capturedSamples.clear());
      _showMessage('All samples cleared.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        profile: profile,
        ph: shownPh,
        tds: shownTds,
        turbidity: shownTurbidity,
        flowRate: shownFlow,
        connected: deviceConnected,
        connectionMessage: connectionMessage ?? 'Checking device connection…',
        refreshing: refreshing,
        refreshStageMessage: refreshStageMessage,
        hasRefreshedAtLeastOnce: hasRefreshedAtLeastOnce,
        sampleCount: capturedSamples.length,
        onRefresh: _refreshProfile,
        onCapture: _captureSample,
        onOpenAnalysis: () => setState(() => selectedIndex = 1),
      ),
      AnalysisPage(
        profile: profile,
        ph: shownPh,
        tds: shownTds,
        turbidity: shownTurbidity,
        flowRate: shownFlow,
        connected: deviceConnected,
        loading: aiLoading,
        hasAnalysis: hasAnalysis,
        aiResult: aiResult,
        onAnalyze: _analyzeWater,
      ),
      SolutionsPage(
        profile: profile,
        ph: shownPh,
        tds: shownTds,
        turbidity: shownTurbidity,
        flowRate: shownFlow,
        connected: deviceConnected,
        loading: aiLoading,
        hasAnalysis: hasAnalysis,
        refreshing: refreshing,
        hasRefreshedAtLeastOnce: hasRefreshedAtLeastOnce,
        aiResult: aiResult,
        onOpenAnalysis: () => setState(() => selectedIndex = 1),
        onRefresh: _refreshProfile,
      ),
      SamplesPage(
        samples: capturedSamples,
        onDelete: _deleteSample,
        onClearAll: _clearSamples,
      ),
      SettingsPage(
        connected: deviceConnected,
        connectionMessage: connectionMessage ?? 'Checking device connection…',
        refreshing: refreshing,
        onRefresh: _refreshConnection,
        isDarkMode: widget.isDarkMode,
        onToggleTheme: widget.onToggleTheme,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Analysis',
          ),
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outline),
            selectedIcon: Icon(Icons.lightbulb),
            label: 'Solutions',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows),
            selectedIcon: Icon(Icons.compare_arrows),
            label: 'Samples',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  final WaterProfile profile;
  final double ph, tds, turbidity, flowRate;
  final bool connected, refreshing, hasRefreshedAtLeastOnce;
  final String connectionMessage;
  final String refreshStageMessage;
  final int sampleCount;
  final VoidCallback onRefresh, onCapture, onOpenAnalysis;

  const DashboardPage({
    super.key,
    required this.profile,
    required this.ph,
    required this.tds,
    required this.turbidity,
    required this.flowRate,
    required this.connected,
    required this.connectionMessage,
    required this.refreshing,
    required this.refreshStageMessage,
    required this.hasRefreshedAtLeastOnce,
    required this.sampleCount,
    required this.onRefresh,
    required this.onCapture,
    required this.onOpenAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF102A43);
    const teal = Color(0xFF087F8C);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AquaSense AI'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [navy, teal]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Water Quality Monitor',
                    style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                _StatusPill(connected: connected),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (refreshing) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  vertical: 14, horizontal: 18),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: teal.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: teal),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: teal),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      refreshStageMessage,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.42,
            children: [
              SensorTile(title: 'pH Level', value: !connected ? '--' : !hasRefreshedAtLeastOnce ? '00' : ph.toStringAsFixed(1), unit: 'pH', icon: Icons.science, color: const Color(0xFF6C63FF)),
              SensorTile(title: 'TDS', value: !connected ? '--' : !hasRefreshedAtLeastOnce ? '00' : (tds < 10 ? tds.toStringAsFixed(2) : tds.toStringAsFixed(0)), unit: 'ppm', icon: Icons.water_drop, color: teal),
              SensorTile(title: 'Turbidity', value: !connected ? '--' : !hasRefreshedAtLeastOnce ? '00' : turbidity.toStringAsFixed(1), unit: 'NTU', icon: Icons.blur_on, color: const Color(0xFF0088CC)),
              SensorTile(title: 'Flow Rate', value: !connected ? '--' : !hasRefreshedAtLeastOnce ? '00' : flowRate.toStringAsFixed(2), unit: 'L/min', icon: Icons.speed, color: const Color(0xFFEF8A17)),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI Water Analysis', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(connected
                      ? 'Run an analysis to see the current safety assessment and recommendation.'
                      : 'Connect the device to receive readings and run analysis.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: connected ? onOpenAnalysis : null,
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('Open AI Analysis'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh),
            label: Text(refreshing ? 'Checking…' : 'Refresh Readings'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: connected ? onCapture : null,
            icon: const Icon(Icons.save_alt),
            label: Text('Save This Sample ($sampleCount saved)'),
          ),

        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool connected;
  const _StatusPill({required this.connected});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: connected ? const Color(0xFFB9F4E8) : const Color(0xFFFFD7D7),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(connected ? Icons.wifi : Icons.wifi_off,
            size: 18, color: connected ? const Color(0xFF075E55) : Colors.red.shade900),
        const SizedBox(width: 7),
        Text(
          connected ? 'DEVICE CONNECTED' : 'DEVICE DISCONNECTED',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: connected ? const Color(0xFF075E55) : Colors.red.shade900,
          ),
        ),
      ],
    ),
  );
}

class SensorTile extends StatelessWidget {
  final String title, value, unit;
  final IconData icon;
  final Color color;

  const SensorTile({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withValues(alpha: .04),
            blurRadius: 9,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 25),
          const Spacer(),
          Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF102A43),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AnalysisPage extends StatelessWidget {
  final WaterProfile profile;
  final double ph, tds, turbidity, flowRate;
  final bool connected, loading, hasAnalysis;
  final Map<String, dynamic>? aiResult;
  final VoidCallback onAnalyze;

  const AnalysisPage({
    super.key,
    required this.profile,
    required this.ph,
    required this.tds,
    required this.turbidity,
    required this.flowRate,
    required this.connected,
    required this.loading,
    required this.hasAnalysis,
    required this.aiResult,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    final safe = _isResultSafe(aiResult);
    const navy = Color(0xFF102A43);
    const teal = Color(0xFF087F8C);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Water Analysis'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [navy, teal]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, color: Color(0xFF7DE3E0)),
                  SizedBox(width: 8),
                  Text('WATER QUALITY ASSESSMENT',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1)),
                ]),
                const SizedBox(height: 12),
                Text(
                  !connected ? 'Device disconnected' : hasAnalysis ? _assessmentLabel(aiResult) : 'Ready to analyze',
                  style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  !connected
                      ? 'Connect the device and refresh before running an analysis.'
                      : hasAnalysis
                      ? 'Analysis completed for the latest backend readings.'
                      : 'Tap Analyze Water to request the assessment and show recommendations.',
                  style: const TextStyle(color: Colors.white70, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _analysisMetric(context, 'pH level', ph.toStringAsFixed(1), 'Measured pH', Icons.science_outlined, const Color(0xFF6C63FF), (ph / 14).clamp(0.0, 1.0)),
          _analysisMetric(context, 'Total dissolved solids', '${tds < 10 ? tds.toStringAsFixed(2) : tds.toStringAsFixed(0)} ppm', 'Dissolved solids', Icons.water_drop_outlined, teal, (tds / 1500).clamp(0.0, 1.0)),
          _analysisMetric(context, 'Turbidity', connected ? '${turbidity.toStringAsFixed(1)} NTU' : '--', 'Water clarity', Icons.blur_on, const Color(0xFF2F80ED), (turbidity / 20).clamp(0.0, 1.0)),
          _analysisMetric(context, 'Flow rate', connected ? '${flowRate.toStringAsFixed(2)} L/min' : '--', 'Flow velocity', Icons.speed, const Color(0xFFDD8A19), (flowRate / 10).clamp(0.0, 1.0)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: connected && !loading ? onAnalyze : null,
            icon: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.psychology_alt_outlined),
            label: Text(loading ? 'Analyzing…' : 'Analyze Water'),
          ),
          if (hasAnalysis) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: safe == true ? const Color(0xFF9DDDBD) : safe == false ? const Color(0xFFF0AAAA) : (isDark ? const Color(0xFF233554) : const Color(0xFFDCE8EE))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(safe == true ? Icons.check_circle : safe == false ? Icons.warning_rounded : Icons.help_outline,
                        color: safe == true ? Colors.green.shade700 : safe == false ? Colors.red.shade700 : Colors.blueGrey),
                    const SizedBox(width: 8),
                    Text(_assessmentLabel(aiResult),
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: safe == true ? Colors.green.shade800 : safe == false ? Colors.red.shade800 : (isDark ? Colors.lightBlue.shade200 : Colors.blueGrey.shade800))),
                  ]),
                  const SizedBox(height: 12),
                  const Text('Purification recommendation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_recommendationText(aiResult, 'The analysis service did not provide a recommendation. Verify sensor readings and backend endpoint.'), style: const TextStyle(height: 1.5)),
                  if (aiResult == null) const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Backend analysis was unavailable.',
                        style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _recommendationText(Map<String, dynamic>? result, String fallback) {
  if (result == null) return fallback;
  final value = result['purification_recommendation'] ??
      result['recommendation'] ??
      result['message'];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  final findings = result['parameter_findings'];
  if (findings is List && findings.isNotEmpty) {
    return findings.join('\n');
  }
  return fallback;
}

Widget _analysisMetric(
    BuildContext context,
    String title,
    String value,
    String note,
    IconData icon,
    Color color,
    double progress,
    ) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cardColor = Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface;

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(
        color: isDark ? const Color(0xFF233554) : const Color(0xFFDCE8EE),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF526777))),
              const SizedBox(height: 3),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF102A43))),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            color: color,
            backgroundColor: isDark ? const Color(0xFF233554) : const Color(0xFFE8EFF3),
          ),
        ),
        const SizedBox(height: 6),
        Text(note, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
      ],
    ),
  );
}


class SolutionVideo {
  final String title;
  final String description;
  final String videoUrl;
  final String thumbnailUrl;
  final String problemCategory;

  const SolutionVideo({
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.problemCategory,
  });
}

List<SolutionVideo> _getRelevantVideos(
    double ph, double tds, double turbidity, bool isTurbidityValid) {
  final List<SolutionVideo> videos = [];

  // 1. Turbidity Unsafe (above safe threshold of 5.0 NTU)
  if (isTurbidityValid && turbidity > 5.0) {
    videos.add(
      const SolutionVideo(
        title: 'Turbidity Water Treatment Solution',
        description:
        'How sediment pre-filtration and clarification remove suspended particles and reduce turbidity.',
        videoUrl: 'https://youtu.be/Bp07m5BEGok',
        thumbnailUrl: 'https://img.youtube.com/vi/Bp07m5BEGok/hqdefault.jpg',
        problemCategory: 'Turbidity Unsafe Solution',
      ),
    );
  }

  // 2. TDS Unsafe (above 500 mg/L)
  if (tds > 500) {
    videos.add(
      const SolutionVideo(
        title: 'High TDS Water Treatment Solution',
        description:
        'How Reverse Osmosis (RO) filtration systems reduce total dissolved solids in drinking water.',
        videoUrl: 'https://youtu.be/B7qB62Msems',
        thumbnailUrl: 'https://img.youtube.com/vi/B7qB62Msems/hqdefault.jpg',
        problemCategory: 'TDS Unsafe Solution',
      ),
    );
  }

  // 3. pH Unsafe (outside 6.5 to 8.5 range)
  if (ph < 6.5 || ph > 8.5) {
    videos.add(
      SolutionVideo(
        title: 'pH Adjustment & Neutralization Solution',
        description: ph < 6.5
            ? 'How calcite neutralizing filtration corrects acidic water pH to safe neutral levels.'
            : 'How pH neutralization systems treat highly alkaline water.',
        videoUrl: 'https://youtu.be/AyZjmOmI1Uo',
        thumbnailUrl: 'https://img.youtube.com/vi/AyZjmOmI1Uo/hqdefault.jpg',
        problemCategory: 'pH Unsafe Solution',
      ),
    );
  }

  return videos;
}

Future<void> _launchUrl(BuildContext context, String url) async {
  final Uri uri = Uri.parse(url);
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open video link: $url')),
        );
      }
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to launch video link.')),
      );
    }
  }
}

class SolutionsPage extends StatelessWidget {
  final WaterProfile profile;
  final double ph, tds, turbidity, flowRate;
  final bool connected,
      loading,
      hasAnalysis,
      refreshing,
      hasRefreshedAtLeastOnce;
  final Map<String, dynamic>? aiResult;
  final VoidCallback onOpenAnalysis;
  final VoidCallback onRefresh;

  const SolutionsPage({
    super.key,
    required this.profile,
    required this.ph,
    required this.tds,
    required this.turbidity,
    required this.flowRate,
    required this.connected,
    required this.loading,
    required this.hasAnalysis,
    required this.refreshing,
    required this.hasRefreshedAtLeastOnce,
    required this.aiResult,
    required this.onOpenAnalysis,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF102A43);
    const teal = Color(0xFF087F8C);

    final isTurbidityValid = connected &&
        (aiResult == null || aiResult!['turbidity'] != null) &&
        turbidity <= 50.0 &&
        turbidity >= 0.0;

    final relevantVideos =
    _getRelevantVideos(ph, tds, turbidity, isTurbidityValid);

    debugPrint('=== DEBUG SolutionsPage.build ===');
    debugPrint(
        'Connected: $connected, Refreshed: $hasRefreshedAtLeastOnce, HasAnalysis: $hasAnalysis');
    debugPrint(
        'Actual Values -> pH: $ph, TDS: $tds, Turbidity: $turbidity, Flow: $flowRate');
    debugPrint('isTurbidityValid: $isTurbidityValid');
    debugPrint('Relevant Videos Count: ${relevantVideos.length}');
    for (final v in relevantVideos) {
      debugPrint('   Video Title: "${v.title}" | URL: ${v.videoUrl}');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Water Safety & Solutions'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh water check',
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !connected || !hasRefreshedAtLeastOnce
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                  !connected
                      ? Icons.wifi_off
                      : Icons.analytics_outlined,
                  size: 54,
                  color: teal),
              const SizedBox(height: 14),
              Text(
                !connected
                    ? 'Device Disconnected'
                    : 'Connect the device and run water analysis',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: navy),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onOpenAnalysis,
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Open AI Analysis'),
              ),
            ],
          ),
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (refreshing) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  vertical: 14, horizontal: 18),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: teal.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: teal),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: teal),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Checking water quality…',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 1. Water Parameters
          const Text('Water Parameters',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: navy)),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.5,
            children: [
              _parameterCard(context, 'pH Level', ph.toStringAsFixed(1),
                  'pH', const Color(0xFF6C63FF), Icons.science),
              _parameterCard(
                  context,
                  'TDS',
                  tds < 10
                      ? tds.toStringAsFixed(2)
                      : tds.toStringAsFixed(0),
                  'ppm',
                  teal,
                  Icons.water_drop),
              _parameterCard(
                  context,
                  'Turbidity',
                  isTurbidityValid
                      ? turbidity.toStringAsFixed(1)
                      : '--',
                  'NTU',
                  const Color(0xFF0088CC),
                  Icons.blur_on),
              _parameterCard(
                  context,
                  'Flow Rate',
                  flowRate.toStringAsFixed(2),
                  'L/min',
                  const Color(0xFFEF8A17),
                  Icons.speed),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Individual Parameter Analysis
          const Text('Individual Parameter Analysis',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: navy)),
          const SizedBox(height: 10),

          // pH Analysis Card
          _buildAnalysisCard(
            context,
            title: 'pH Level (${ph.toStringAsFixed(1)})',
            icon: Icons.science_outlined,
            iconColor: const Color(0xFF6C63FF),
            finding: ph < 6.5
                ? 'Low pH detected (${ph.toStringAsFixed(1)}): Water is acidic (below safe 6.5–8.5 range).'
                : ph > 8.5
                ? 'High pH detected (${ph.toStringAsFixed(1)}): Water is alkaline (above safe 6.5–8.5 range).'
                : 'pH level (${ph.toStringAsFixed(1)}) is in optimal balance (6.5–8.5 range).',
            concern: ph < 6.5
                ? 'Acidic water can cause metal pipe corrosion and leaching.'
                : ph > 8.5
                ? 'Highly alkaline water may taste bitter and cause scale buildup.'
                : 'pH balance is optimal.',
            treatment: ph < 6.5
                ? 'Calcite neutralizer media filtration system recommended.'
                : ph > 8.5
                ? 'Select an appropriate pH correction system based on testing.'
                : 'No pH adjustment required.',
          ),
          const SizedBox(height: 10),

          // TDS Analysis Card
          _buildAnalysisCard(
            context,
            title:
            'Total Dissolved Solids (${tds.toStringAsFixed(0)} mg/L)',
            icon: Icons.water_drop_outlined,
            iconColor: teal,
            finding: tds > 500
                ? 'Elevated TDS detected (${tds.toStringAsFixed(0)} mg/L): Exceeds 500 mg/L threshold.'
                : 'TDS (${tds.toStringAsFixed(0)} mg/L) is within the safe 500 mg/L threshold.',
            concern: tds > 500
                ? 'High concentration of dissolved mineral salts and inorganic ions.'
                : 'Total Dissolved Solids level is normal.',
            treatment: tds > 500
                ? 'Reverse Osmosis (RO) purification system recommended.'
                : 'No TDS treatment required.',
          ),
          const SizedBox(height: 10),

          // Turbidity Analysis Card
          _buildAnalysisCard(
            context,
            title: isTurbidityValid
                ? 'Turbidity (${turbidity.toStringAsFixed(1)} NTU)'
                : 'Turbidity (Unavailable)',
            icon: Icons.blur_on,
            iconColor: const Color(0xFF0088CC),
            finding: !isTurbidityValid
                ? 'Turbidity sensor reading is unavailable or uncalibrated.'
                : turbidity > 5.0
                ? 'Elevated Turbidity detected (${turbidity.toStringAsFixed(1)} NTU): Exceeds 5.0 NTU threshold.'
                : 'Turbidity (${turbidity.toStringAsFixed(1)} NTU) is within the safe 5.0 NTU threshold.',
            concern: !isTurbidityValid
                ? 'Probe is uncalibrated or disconnected.'
                : turbidity > 5.0
                ? 'High count of suspended silt, clay, or organic particles.'
                : 'Water clarity is optimal.',
            treatment: !isTurbidityValid
                ? 'Submerge and calibrate the optical turbidity probe in water before evaluating.'
                : turbidity > 5.0
                ? 'Multi-stage sediment pre-filtration (spun/melt-blown cartridges).'
                : 'No sediment pre-filtration required.',
          ),
          const SizedBox(height: 16),

          // 3. Recommended Treatment
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: teal),
                      SizedBox(width: 8),
                      Text('Recommended Treatment',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: navy)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _recommendationText(
                        aiResult,
                        'All measured water parameters (pH, TDS, and Turbidity) are within configured safe operational limits. Maintain routine filter inspection and clean storage practices.'),
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 4. Treatment Solution Videos (Shown ONLY when relevant issue videos exist)
          if (relevantVideos.isNotEmpty) ...[
            const Text('Treatment Solution Videos',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: navy)),
            const SizedBox(height: 10),
            ...relevantVideos
                .map((video) => _buildVideoCard(context, video)),
            const SizedBox(height: 12),
          ],

          // 5. Working Refresh Check button
          FilledButton.icon(
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.refresh),
            label: Text(refreshing ? 'Checking…' : 'Refresh Check'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAnalysisCard(
      BuildContext context, {
        required String title,
        required IconData icon,
        required Color iconColor,
        required String finding,
        required String concern,
        required String treatment,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const navy = Color(0xFF102A43);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : navy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              finding,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Concern: $concern',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Action: $treatment',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFF64FFDA) : const Color(0xFF087F8C),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(BuildContext context, SolutionVideo video) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const teal = Color(0xFF087F8C);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _launchUrl(context, video.videoUrl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Image.network(
                  video.thumbnailUrl,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 140,
                    color: const Color(0xFF102A43),
                    child: const Center(
                      child: Icon(Icons.play_circle_fill,
                          size: 52, color: Colors.white70),
                    ),
                  ),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 36, color: Colors.white),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      video.problemCategory,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xFF102A43)),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    video.description,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.play_circle_fill, size: 16, color: teal),
                      const SizedBox(width: 6),
                      Text(
                        'Watch Solution Video',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: teal),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _parameterCard(
      BuildContext context, String title, String value, String unit, Color color, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF233554) : const Color(0xFFDCE8EE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.black54)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF102A43)),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 3),
              Text(unit,
                  style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white70 : Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }
}

class SamplesPage extends StatelessWidget {
  final List<Map<String, dynamic>> samples;
  final ValueChanged<int> onDelete;
  final VoidCallback onClearAll;

  const SamplesPage({
    super.key,
    required this.samples,
    required this.onDelete,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF087F8C);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sample Comparison'),
        backgroundColor: teal,
        foregroundColor: Colors.white,
        actions: [
          if (samples.isNotEmpty)
            IconButton(
              tooltip: 'Clear all samples',
              onPressed: onClearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: samples.isEmpty
          ? const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No samples saved yet. Connect the device, then save a sample from Dashboard.',
            textAlign: TextAlign.center,
          ),
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Saved Samples', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed: onClearAll,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear all'),
              ),
            ],
          ),
          const Text('Samples are stored for the current app session. Use the three-dot menu to remove one sample.'),
          const SizedBox(height: 10),
          ...samples.asMap().entries.map((entry) {
            final index = entry.key;
            final sample = entry.value;
            final flow = (sample['flow'] as num?)?.toDouble() ?? 0;
            final assessment = (sample['assessment'] as String?) ?? 'NOT ANALYZED';
            final isSafe = assessment == 'SAFE';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              sample['name'] != null
                                  ? 'Sample ${index + 1}: ${sample['name']}'
                                  : 'Sample ${index + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Sample options',
                          onSelected: (value) {
                            if (value == 'remove') onDelete(index);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'remove',
                              child: Row(children: [
                                Icon(Icons.delete_outline, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Remove'),
                              ]),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSafe ? const Color(0xFFE2F6EB) : assessment == 'UNSAFE' ? const Color(0xFFFFE8E8) : const Color(0xFFE8EFF3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(assessment,
                          style: TextStyle(fontWeight: FontWeight.bold, color: isSafe ? Colors.green.shade800 : assessment == 'UNSAFE' ? Colors.red.shade800 : Colors.blueGrey.shade800)),
                    ),
                    const SizedBox(height: 8),
                    Text('pH ${sample['ph']}  •  TDS ${sample['tds']} ppm'),
                    Text('Turbidity ${sample['turbidity']} NTU  •  Flow ${flow.toStringAsFixed(2)} L/min'),
                    if (sample['time'] is String)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(sample['time'] as String, style: const TextStyle(color: Colors.black54, fontSize: 12)),
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

class SettingsPage extends StatelessWidget {
  final bool connected, refreshing, isDarkMode;
  final String connectionMessage;
  final VoidCallback onRefresh;
  final VoidCallback onToggleTheme;

  const SettingsPage({
    super.key,
    required this.connected,
    required this.refreshing,
    required this.connectionMessage,
    required this.onRefresh,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF102A43);
    const teal = Color(0xFF087F8C);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: onToggleTheme,
            icon: Icon(isDarkMode ? Icons.wb_sunny_outlined : Icons.nightlight_round),
          ),
          IconButton(
            tooltip: 'Refresh connection',
            onPressed: refreshing ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [navy, teal]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.water_drop_rounded, color: Colors.white, size: 36),
                SizedBox(height: 12),
                Text('AquaSense AI',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                Text('IoT-Based Water Quality Monitoring', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Appearance',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : navy)),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: Icon(
                isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                color: teal,
              ),
              title: Text(isDarkMode ? 'Dark Mode' : 'Light Mode'),
              subtitle: Text(isDarkMode ? 'Theme set to Dark Mode' : 'Theme set to Light Mode'),
              trailing: IconButton(
                icon: Icon(
                  isDarkMode ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                  color: isDarkMode ? Colors.amber : navy,
                ),
                tooltip: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                onPressed: onToggleTheme,
              ),
              onTap: onToggleTheme,
            ),
          ),
          const SizedBox(height: 20),
          Text('Device & Connection',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : navy)),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: Icon(connected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: teal),
              title: Text(connected ? 'Device Connected' : 'Device Disconnected'),
              subtitle: Text(connectionMessage),
              trailing: Icon(connected ? Icons.check_circle : Icons.error_outline,
                  color: connected ? Colors.green : Colors.red),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh),
            label: Text(refreshing ? 'Refreshing…' : 'Refresh Connection'),
          ),
          const SizedBox(height: 22),
          Text('About',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : navy)),
          const SizedBox(height: 10),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.analytics_outlined, color: teal),
                  title: Text('AI Water Analysis'),
                  subtitle: Text('Analyze current backend readings'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.lightbulb_outline, color: teal),
                  title: Text('Purification Solutions'),
                  subtitle: Text('Recommendations shown after analysis'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.info_outline, color: teal),
                  title: Text('Project Information'),
                  subtitle: Text('AquaSense AI water quality monitoring project'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'Made by Tech in Air',
              style: TextStyle(
                  color: isDark ? Colors.white70 : navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
