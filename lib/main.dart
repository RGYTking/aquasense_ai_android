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
  name: 'Live Water Readings',
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

class AquaSenseAI extends StatelessWidget {
  const AquaSenseAI({super.key});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF087F8C);
    return MaterialApp(
      title: 'AquaSense AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: teal),
        scaffoldBackgroundColor: const Color(0xFFF2F7FA),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0.5,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
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
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
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
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [navy, teal],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 112, height: 112,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Image.asset(
                  'assets/images/aquasense_logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('AquaSense AI', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Smart Water Quality Monitoring', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 32),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
            const SizedBox(height: 14),
            const Text('Starting…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class DemoProfile {
  final String name;
  final double ph;
  final double tds;

  const DemoProfile({
    required this.name,
    required this.ph,
    required this.tds,
  });
}

const List<DemoProfile> demoProfiles = [
  DemoProfile(name: 'Clean Water', ph: 7.1, tds: 120.0),
  DemoProfile(name: 'Tap/Borewell Water', ph: 7.4, tds: 420.0),
  DemoProfile(name: 'Slightly Dirty Water', ph: 6.7, tds: 680.0),
  DemoProfile(name: 'Dirty Water', ph: 5.8, tds: 1200.0),
];

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  Timer? _connectionTimer;
  int selectedIndex = 0;
  double flowRate = 0;
  bool deviceConnected = false;
  bool refreshing = false;
  bool _connectionRequestInFlight = false;
  bool aiLoading = false;
  bool hasAnalysis = false;
  Map<String, dynamic>? aiResult;
  String? connectionMessage;
  final List<Map<String, dynamic>> capturedSamples = [];

  // Alternating test profile index: A (Clean) -> B (Tap/Borewell) -> C (Slightly Dirty) -> D (Dirty) -> A
  int _testProfileIndex = 0;

  DemoProfile get activeDemoProfile => demoProfiles[_testProfileIndex];
  double get activeTestPh => activeDemoProfile.ph;
  double get activeTestTds => activeDemoProfile.tds;
  String get activeTestLabel => activeDemoProfile.name;

  WaterProfile get profile => liveProfile;

  double get shownPh => deviceConnected ? activeTestPh : 0;
  double get shownTds => deviceConnected ? activeTestTds : 0;
  double get shownTurbidity => deviceConnected ? profile.turbidity : 0;
  double get shownFlow => deviceConnected ? flowRate : 0;

  @override
  void initState() {
    super.initState();
    _refreshConnection();
    // Recheck device freshness regularly so the UI does not remain connected
    // after the ESP8266 stops sending readings.
    _connectionTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!refreshing) _refreshConnection(showSpinner: false);
    });
  }

  @override
  void dispose() {
    _connectionTimer?.cancel();
    super.dispose();
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
    WaterProfile nextProfile = liveProfile;

    try {
      final response = await http
          .get(Uri.parse('$backendUrl/api/sensors'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          final data = decoded['data'];

          connected = decoded['status'] == 'connected' &&
              data is Map<String, dynamic> &&
              (decoded['device_online'] == null ||
                  decoded['device_online'] == true);

          if (connected) {
            final ph = data['ph'];
            final tds = data['tds'];
            final turbidity = data['turbidity'];
            final flow = data['flow_rate'];

            if (ph is! num ||
                tds is! num ||
                turbidity is! num ||
                flow is! num) {
              connected = false;
              message = 'Device disconnected. Incomplete sensor data.';
            } else {
              latestFlow = flow.toDouble();
              nextProfile = WaterProfile(
                name: activeTestLabel,
                ph: activeTestPh,
                tds: activeTestTds,
                turbidity: turbidity.toDouble(),
                recommendation:
                    'Run an analysis to receive a recommendation based on live readings.',
              );
              message = 'Connected';
            }
          } else if (decoded['status'] == 'stale' ||
              decoded['device_online'] == false) {
            message = 'Device disconnected. Latest sensor data is outdated.';
          } else if (decoded['status'] == 'no_data') {
            message = 'Device disconnected. No sensor data received yet.';
          } else {
            message = 'Device disconnected or backend status unavailable.';
          }
        }
      } else {
        message = 'Backend unavailable (HTTP ${response.statusCode}).';
      }
    } catch (_) {
      message = 'Unable to check device status. Check internet/backend.';
    } finally {
      _connectionRequestInFlight = false;
    }

    if (!mounted) return;

    setState(() {
      deviceConnected = connected;
      if (connected) liveProfile = nextProfile;
      flowRate = connected ? latestFlow : 0;
      connectionMessage = message;
      refreshing = false;

      if (!connected) {
        hasAnalysis = false;
        aiResult = null;
      }
    });
  }

  Future<void> _refreshProfile() async {
    if (refreshing || _connectionRequestInFlight) return;

    // Advance profile in sequence on manual refresh: A -> B -> C -> D -> A
    _testProfileIndex = (_testProfileIndex + 1) % demoProfiles.length;

    setState(() {
      hasAnalysis = false;
      aiResult = null;
      aiLoading = false;
    });

    await _refreshConnection();
  }

  Future<void> _analyzeWater() async {
    if (!deviceConnected || aiLoading) return;
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
          'ph': shownPh,
          'tds': shownTds,
          'turbidity': shownTurbidity,
          'flow_rate': shownFlow,
        }),
      )
          .timeout(const Duration(seconds: 12));
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
      aiLoading = false;
      hasAnalysis = true;
    });
  }

  void _captureSample() {
    if (!deviceConnected) {
      _showMessage('Connect the device before saving a sample.');
      return;
    }
    capturedSamples.insert(0, {
      'name': activeTestLabel,
      'ph': shownPh,
      'tds': shownTds,
      'turbidity': shownTurbidity,
      'flow': shownFlow,
      'assessment': hasAnalysis ? _assessmentLabel(aiResult) : 'NOT ANALYZED',
      'time': DateTime.now().toLocal().toString().substring(0, 16),
      'isTest': true,
    });
    setState(() {});
    _showMessage('Sample saved ($activeTestLabel).');
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
        aiResult: aiResult,
        onOpenAnalysis: () => setState(() => selectedIndex = 1),
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
  final bool connected, refreshing;
  final String connectionMessage;
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
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.42,
            children: [
              SensorTile(title: 'pH Level', value: connected ? ph.toStringAsFixed(1) : '--', unit: 'pH', icon: Icons.science, color: const Color(0xFF6C63FF)),
              SensorTile(title: 'TDS', value: connected ? (tds < 10 ? tds.toStringAsFixed(2) : tds.toStringAsFixed(0)) : '--', unit: 'ppm', icon: Icons.water_drop, color: teal),
              SensorTile(title: 'Turbidity (Hardware)', value: connected ? turbidity.toStringAsFixed(1) : '--', unit: 'NTU*', icon: Icons.blur_on, color: const Color(0xFF0088CC)),
              SensorTile(title: 'Flow Rate (Hardware)', value: connected ? flowRate.toStringAsFixed(2) : '--', unit: 'L/min*', icon: Icons.speed, color: const Color(0xFFEF8A17)),
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
            label: Text(refreshing ? 'Refreshing…' : 'Refresh Readings'),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 9)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 25),
        const Spacer(),
        Text(title, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 5),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(unit, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ),
          ],
        ),
      ],
    ),
  );
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
          _analysisMetric('pH level', ph.toStringAsFixed(1), 'Demo value', Icons.science_outlined, const Color(0xFF6C63FF), (ph / 14).clamp(0.0, 1.0)),
          _analysisMetric('Total dissolved solids', '${tds < 10 ? tds.toStringAsFixed(2) : tds.toStringAsFixed(0)} ppm', 'Demo value', Icons.water_drop_outlined, teal, (tds / 1500).clamp(0.0, 1.0)),
          _analysisMetric('Turbidity', '${turbidity.toStringAsFixed(1)} NTU*', 'Hardware reading', Icons.blur_on, const Color(0xFF2F80ED), (turbidity / 20).clamp(0.0, 1.0)),
          _analysisMetric('Flow rate', '${flowRate.toStringAsFixed(2)} L/min*', 'Hardware reading', Icons.speed, const Color(0xFFDD8A19), (flowRate / 10).clamp(0.0, 1.0)),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: safe == true ? const Color(0xFF9DDDBD) : safe == false ? const Color(0xFFF0AAAA) : const Color(0xFFDCE8EE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(safe == true ? Icons.check_circle : safe == false ? Icons.warning_rounded : Icons.help_outline,
                        color: safe == true ? Colors.green.shade700 : safe == false ? Colors.red.shade700 : Colors.blueGrey),
                    const SizedBox(width: 8),
                    Text(_assessmentLabel(aiResult),
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: safe == true ? Colors.green.shade800 : safe == false ? Colors.red.shade800 : Colors.blueGrey.shade800)),
                  ]),
                  const SizedBox(height: 12),
                  const Text('Purification recommendation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_recommendationText(aiResult, 'The analysis service did not provide a recommendation. Verify the sensor readings and backend analysis endpoint.'), style: const TextStyle(height: 1.5)),
                  if (aiResult == null) const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Backend analysis was unavailable. No safety classification can be confirmed.',
                        style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A result is only shown when the backend returns a recognizable classification. Sensor calibration and validated testing are required to confirm drinking-water safety.',
                    style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
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
    String title,
    String value,
    String note,
    IconData icon,
    Color color,
    double progress,
    ) =>
    Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFDCE8EE)),
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
                Text(title, style: const TextStyle(color: Color(0xFF526777))),
                const SizedBox(height: 3),
                Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF102A43))),
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
              backgroundColor: const Color(0xFFE8EFF3),
            ),
          ),
          const SizedBox(height: 6),
          Text(note, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );

class VideoItem {
  final String title;
  final String description;
  final String url;
  final String thumbnailUrl;
  final String duration;
  final String category;

  const VideoItem({
    required this.title,
    required this.description,
    required this.url,
    required this.thumbnailUrl,
    required this.duration,
    required this.category,
  });
}

const List<VideoItem> educationalVideos = [
  VideoItem(
    title: 'Understanding pH, TDS, and Turbidity in Water',
    description:
        'A clear educational breakdown of water-quality parameters, digital TDS meters, pH testing range, and turbidity measuring principles.',
    url: 'https://www.youtube.com/watch?v=3K0B3TCo-2M',
    thumbnailUrl: 'https://img.youtube.com/vi/3K0B3TCo-2M/hqdefault.jpg',
    duration: '8:45',
    category: 'General Safety',
  ),
  VideoItem(
    title: 'How Reverse Osmosis (RO) Water Purification Works',
    description:
        '3D animation showing how semi-permeable RO membranes remove dissolved salts, heavy metals, and high TDS from drinking water.',
    url: 'https://www.youtube.com/watch?v=aVdWqbpqv_U',
    thumbnailUrl: 'https://img.youtube.com/vi/aVdWqbpqv_U/hqdefault.jpg',
    duration: '5:20',
    category: 'High TDS',
  ),
  VideoItem(
    title: 'UV Water Purification & Disinfection System Guide',
    description:
        'Learn how 254nm Ultraviolet (UV-C) lamps neutralize 99.99% of bacteria, viruses, and pathogens without chemical additives.',
    url: 'https://www.youtube.com/watch?v=0k3P8L3XN6k',
    thumbnailUrl: 'https://img.youtube.com/vi/0k3P8L3XN6k/hqdefault.jpg',
    duration: '6:15',
    category: 'Microbial / UV',
  ),
  VideoItem(
    title: 'Water Filter Maintenance & Cartridge Replacement Guide',
    description:
        'Step-by-step instructions for replacing sediment filters, carbon blocks, quartz sleeves, and servicing home purifiers.',
    url: 'https://www.youtube.com/watch?v=gT-xO3PzT64',
    thumbnailUrl: 'https://img.youtube.com/vi/gT-xO3PzT64/hqdefault.jpg',
    duration: '7:30',
    category: 'Turbidity',
  ),
  VideoItem(
    title: 'Safe Drinking Water Practices & Household Storage Hygiene',
    description:
        'World health guidance on multi-barrier water treatment, storage container hygiene, and preventing secondary contamination.',
    url: 'https://www.youtube.com/watch?v=o0L8d2sM5Z8',
    thumbnailUrl: 'https://img.youtube.com/vi/o0L8d2sM5Z8/hqdefault.jpg',
    duration: '9:10',
    category: 'General Safety',
  ),
];

class SolutionTopic {
  final String title;
  final String category;
  final IconData icon;
  final Color color;
  final String simpleMeaning;
  final String possibleCauses;
  final String healthConcerns;
  final String recommendedMethod;
  final List<String> stepByStepProcess;
  final String filterOptions;
  final String maintenanceInstructions;
  final String whenToContactLab;

  const SolutionTopic({
    required this.title,
    required this.category,
    required this.icon,
    required this.color,
    required this.simpleMeaning,
    required this.possibleCauses,
    required this.healthConcerns,
    required this.recommendedMethod,
    required this.stepByStepProcess,
    required this.filterOptions,
    required this.maintenanceInstructions,
    required this.whenToContactLab,
  });
}

const List<SolutionTopic> solutionTopics = [
  SolutionTopic(
    title: 'High Total Dissolved Solids (TDS)',
    category: 'High TDS',
    icon: Icons.water_drop_outlined,
    color: Color(0xFF087F8C),
    simpleMeaning:
        'TDS measures minerals, salts, and metals dissolved in water. Readings above 300–500 ppm indicate high mineral concentration.',
    possibleCauses:
        'Groundwater passing through mineral deposits (calcium, magnesium, chloride), agricultural runoff, urban stormwater, or hard water wells.',
    healthConcerns:
        'Salty or bitter taste, pipe scaling, appliance damage. Very high TDS (>1,000 ppm) may indicate heavy metals or elevated sodium levels causing kidney stress.',
    recommendedMethod:
        'Reverse Osmosis (RO) Filtration or Solar/Thermal Distillation.',
    stepByStepProcess: [
      'Pass water through a 5-micron sediment pre-filter to trap sand and silt.',
      'Route through an activated carbon filter to remove chlorine and volatile organic chemicals.',
      'Pass water under pressure through a semi-permeable RO membrane (0.0001 micron) to filter 95–99% of dissolved salts.',
      'Pass through a post-carbon polishing filter for fresh taste.',
      'Store in a food-grade sealed tank.',
    ],
    filterOptions:
        'Multi-stage Home RO Purifiers, Countertop Distillers, Deionization (DI) Resin Exchange Units.',
    maintenanceInstructions:
        'Replace sediment and carbon pre-filters every 6 months. Replace the RO membrane every 24–36 months depending on input TDS.',
    whenToContactLab:
        'Contact an accredited lab if TDS exceeds 1,000 ppm, if water leaves white/crusty residues, or if an unusual chemical smell is present.',
  ),
  SolutionTopic(
    title: 'pH Imbalance (Acidic or Alkaline Water)',
    category: 'pH Balance',
    icon: Icons.science_outlined,
    color: Color(0xFF6C63FF),
    simpleMeaning:
        'pH measures acidity or alkalinity on a scale of 0 to 14. Safe drinking water falls strictly between 6.5 and 8.5.',
    possibleCauses:
        'Acidic water (pH < 6.5) is caused by acid rain, organic matter, or dissolved carbon dioxide. Alkaline water (pH > 8.5) stems from carbonate minerals or alkaline runoff.',
    healthConcerns:
        'Acidic water corrodes copper/lead plumbing, leaching toxic metals into drinking water. Highly alkaline water feels slippery, tastes bitter, and causes pipe scaling.',
    recommendedMethod:
        'Calcite Neutralizing Media Filter (for low pH) or Chemical Neutralizer / Proportional Dosing (for high pH).',
    stepByStepProcess: [
      'Install an in-line Calcite / Magnesium Oxide neutralizing tank on the main water supply.',
      'As acidic water flows through calcite media, calcium carbonate dissolves naturally, raising pH toward 7.2.',
      'For alkaline water, install a citric acid or soda ash proportional injection pump.',
      'Install a post-filter to trap any dislodged mineral dust.',
    ],
    filterOptions:
        'Whole-House Calcite Tank Filters, Alkaline Remineralization Cartridges, Citric Acid Injection Systems.',
    maintenanceInstructions:
        'Top up calcite or neutralizing media once or twice a year depending on flow volume and water acidity.',
    whenToContactLab:
        'Contact a certified testing lab if green/blue stains appear on sinks/faucets (indicating copper pipe corrosion) or if plumbing contains lead solder.',
  ),
  SolutionTopic(
    title: 'High Turbidity (Cloudy or Hazy Water)',
    category: 'Turbidity',
    icon: Icons.blur_on,
    color: Color(0xFF2F80ED),
    simpleMeaning:
        'Turbidity measures water clarity. High turbidity (>1.0 NTU) means suspended silt, clay, rust, or organic particles make water cloudy.',
    possibleCauses:
        'Soil erosion, heavy rainfall runoff, well agitation, rusting iron pipes, or algae growth in open water sources.',
    healthConcerns:
        'Suspended particles shield pathogens (bacteria/viruses) from UV light and chlorine disinfection, significantly increasing biological infection risk.',
    recommendedMethod:
        'Multi-Stage Sediment Filtration followed by Sub-Micron Pleated/Spun Filtration.',
    stepByStepProcess: [
      'Pass water through a 20-micron coarse spun polypropylene filter to catch large sand and rust flakes.',
      'Pass through a 5-micron fine melt-blown sediment filter for silt and clay particles.',
      'Pass through a 1-micron or 0.5-micron ceramic/pleated cartridge for micro-turbidity.',
      'Proceed to secondary disinfection (UV or chlorination) now that water is crystal clear.',
    ],
    filterOptions:
        'Melt-Blown Polypropylene Cartridges, Washable Pleated Filters, Multi-Media Sand Bed Filters.',
    maintenanceInstructions:
        'Rinse or replace sediment cartridges every 1 to 3 months when water pressure drops across the filter housing.',
    whenToContactLab:
        'Contact a lab if water turns brown/muddy unexpectedly, or if cloudiness persists after sub-micron filtration.',
  ),
  SolutionTopic(
    title: 'Microbial & Biological Contamination',
    category: 'Microbial / UV',
    icon: Icons.bug_report_outlined,
    color: Color(0xFFE65100),
    simpleMeaning:
        'Microbial contamination refers to disease-causing organisms such as E. coli, Coliform bacteria, Giardia, or viruses.',
    possibleCauses:
        'Sewage leak, livestock runoff entering wells, flooded septic tanks, or unsealed overhead water tanks.',
    healthConcerns:
        'Acute gastrointestinal infections, severe diarrhea, vomiting, cholera, dysentery, typhoid, and hepatitis.',
    recommendedMethod:
        'Ultraviolet (UV-C) Disinfection, Rolling Boil (3+ mins), or Chlorination.',
    stepByStepProcess: [
      'Ensure water is pre-filtered below 1 NTU turbidity so microbes cannot hide in shadows.',
      'Pass water through a stainless steel UV chamber equipped with a 254nm germicidal UV lamp.',
      'UV-C radiation disrupts pathogen DNA, preventing replication and neutralizing 99.99% of bacteria and viruses.',
      'For emergency situations without power, bring water to a rolling boil for at least 3 full minutes.',
    ],
    filterOptions:
        '254nm Ultraviolet (UV-C) Sterilizers, Hollow-Fiber Ultrafiltration (UF) Membranes, Chlorine Tablets / Liquid Chlorination.',
    maintenanceInstructions:
        'Clean the quartz sleeve inside the UV chamber every 6 months. Replace the UV lamp annually (approx. 9,000 hours runtime).',
    whenToContactLab:
        'Immediately submit a sample to an accredited micro-biology lab if anyone in the household suffers waterborne illness or after flooding events.',
  ),
  SolutionTopic(
    title: 'General Drinking-Water Safety & System Care',
    category: 'General Safety',
    icon: Icons.shield_outlined,
    color: Color(0xFF102A43),
    simpleMeaning:
        'Overall household water hygiene, storage protection, and multi-barrier purification best practices.',
    possibleCauses:
        'Unwashed storage tanks, stagnant water in purifiers, biofilm buildup inside old tubing, open water containers.',
    healthConcerns:
        'Secondary bacterial growth in purified water storage tanks and unmaintained filter cartridges.',
    recommendedMethod:
        'Multi-Barrier Home Water Purifier & Hygienic Sealed Storage.',
    stepByStepProcess: [
      'Combine sediment pre-filtration + RO membrane + post-carbon + UV lamp for complete multi-barrier protection.',
      'Drain and sanitize household overhead tanks every 6 months using food-grade hydrogen peroxide or dilute chlorine solution.',
      'Keep purified drinking water in covered food-grade stainless steel or glass containers.',
      'Never allow dirty hands or unwashed cups to dip into clean drinking water storage.',
    ],
    filterOptions:
        'Complete 5-Stage Home RO + UV + UF Systems, Food-Grade Stainless Steel Storage Vessels.',
    maintenanceInstructions:
        'Sanitize purifier lines and storage tank yearly. Flush new filter cartridges for 10 minutes before first consumption.',
    whenToContactLab:
        'Perform a comprehensive accredited laboratory water test at least once a year for private well or municipal tap water sources.',
  ),
];

Future<void> _launchVideo(BuildContext context, String url) async {
  final Uri uri = Uri.parse(url);
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open video URL: $url')),
        );
      }
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to launch video URL.')),
      );
    }
  }
}

class SolutionsPage extends StatelessWidget {
  final WaterProfile profile;
  final double ph, tds, turbidity, flowRate;
  final bool connected, loading, hasAnalysis;
  final Map<String, dynamic>? aiResult;
  final VoidCallback onOpenAnalysis;

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
    required this.aiResult,
    required this.onOpenAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF102A43);
    const teal = Color(0xFF087F8C);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purification Solutions & Guide'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [navy, teal]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.lightbulb_rounded, color: Color(0xFF7DE3E0)),
                  SizedBox(width: 8),
                  Text('WATER PURIFICATION SOLUTIONS',
                      style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                ]),
                SizedBox(height: 12),
                Text('Treatment & Parameter Guide',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text(
                  'Comprehensive guidance for water-quality issues, treatment processes, and educational videos.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Personalized AI Recommendation Card
          _buildPersonalizedAiCard(context),
          const SizedBox(height: 20),

          // Parameter Guides Header
          const Text('Detailed Water Quality Guides',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: navy)),
          const SizedBox(height: 10),

          ...solutionTopics.map((topic) => _buildTopicCard(topic)),

          const SizedBox(height: 24),

          // "Learn with Videos" Section
          Row(
            children: const [
              Icon(Icons.video_library_outlined, color: teal, size: 24),
              SizedBox(width: 8),
              Text('Learn with Videos',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: navy)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Educational video tutorials on water purification technologies and safe practices.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 12),

          ...educationalVideos.map((video) => _buildVideoCard(context, video)),

          const SizedBox(height: 24),

          // Laboratory Disclaimer Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_outlined,
                    color: Color(0xFFE65100), size: 26),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Accredited Laboratory Testing Disclaimer',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFFE65100)),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'AquaSense AI guides and parameter recommendations are provided for educational and monitoring guidance. Physical sensor values and AI predictions should not replace certified laboratory water testing. Always consult an accredited environmental testing laboratory when drinking-water safety is uncertain.',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF5D4037), height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPersonalizedAiCard(BuildContext context) {
    if (!connected) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Row(children: [
                Icon(Icons.wifi_off, color: Colors.orange),
                SizedBox(width: 10),
                Text('Educational Guidance Mode',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF102A43))),
              ]),
              SizedBox(height: 8),
              Text(
                'Device is currently disconnected. Browse the comprehensive parameter guides and video tutorials below for general water purification knowledge.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    final List<String> requiredTreatments = [];
    final List<String> reasoningList = [];

    if (tds > 300) {
      requiredTreatments.add('Reverse Osmosis (RO)');
      reasoningList.add(
          'Elevated TDS (${tds.toStringAsFixed(0)} ppm): RO membrane filtration is required to filter dissolved mineral salts and heavy metals.');
    }
    if (ph < 6.5) {
      requiredTreatments.add('Calcite Neutralizer');
      reasoningList.add(
          'Acidic water (pH ${ph.toStringAsFixed(1)}): Calcite neutralizer filter is recommended to raise pH and prevent pipe corrosion.');
    } else if (ph > 8.5) {
      requiredTreatments.add('pH Adjustment / Acid Dosing');
      reasoningList.add(
          'High pH (${ph.toStringAsFixed(1)}): Neutralizing treatment is recommended to prevent bitter taste and mineral scaling.');
    }
    if (turbidity > 1.0) {
      requiredTreatments.add('Multi-Stage Sediment Pre-Filter');
      reasoningList.add(
          'High Turbidity (${turbidity.toStringAsFixed(1)} NTU): Sediment pre-filtration (5μm -> 1μm) is needed to catch suspended silt and prevent membrane clogging.');
    }

    final safe = _isResultSafe(aiResult);
    if (safe == false ||
        (hasAnalysis && _assessmentLabel(aiResult) == 'UNSAFE')) {
      requiredTreatments.add('UV Disinfection / Boiling');
      reasoningList.add(
          'AI Assessment Unsafe: UV-C disinfection or boiling (3+ minutes) is required to neutralize microbial pathogens.');
    }

    if (requiredTreatments.isEmpty) {
      requiredTreatments.add('Multi-Barrier Maintenance Filter');
      reasoningList.add(
          'Active readings (pH ${ph.toStringAsFixed(1)}, TDS ${tds.toStringAsFixed(0)} ppm, Turbidity ${turbidity.toStringAsFixed(1)} NTU) are within normal baseline ranges. Maintain standard sediment and carbon post-filters.');
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: safe == true
              ? const Color(0xFF9DDDBD)
              : safe == false
                  ? const Color(0xFFF0AAAA)
                  : const Color(0xFF087F8C),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome, color: Color(0xFF087F8C)),
              SizedBox(width: 8),
              Text(
                'Personalized AI Treatment Guidance',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF102A43)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: requiredTreatments
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4F6F5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(t,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF087F8C))),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          const Text('Why these treatments are recommended:',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF102A43))),
          const SizedBox(height: 6),
          ...reasoningList.map((reason) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF087F8C))),
                    Expanded(
                        child: Text(reason,
                            style:
                                const TextStyle(fontSize: 13, height: 1.4))),
                  ],
                ),
              )),
          if (hasAnalysis && _recommendationText(aiResult, '').isNotEmpty) ...[
            const Divider(height: 20),
            const Text('Backend Model Notes:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(_recommendationText(aiResult, ''),
                style: const TextStyle(
                    fontSize: 12, color: Colors.black87, height: 1.4)),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onOpenAnalysis,
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('View Detailed AI Analysis'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicCard(SolutionTopic topic) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: topic.color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(topic.icon, color: topic.color),
        ),
        title: Text(
          topic.title,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF102A43)),
        ),
        subtitle: Text(
          topic.category,
          style: TextStyle(fontSize: 12, color: topic.color, fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          _detailSection('Simple Explanation', topic.simpleMeaning, Icons.info_outline),
          _detailSection('Possible Causes', topic.possibleCauses, Icons.search_outlined),
          _detailSection('Health & Usability Concerns', topic.healthConcerns, Icons.warning_amber_rounded),
          _detailSection('Recommended Purification Method', topic.recommendedMethod, Icons.build_outlined),

          const SizedBox(height: 8),
          const Text('Step-by-Step Purification Process:',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF102A43))),
          const SizedBox(height: 6),
          ...topic.stepByStepProcess.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: topic.color,
                      child: Text('${e.key + 1}',
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(e.value,
                            style: const TextStyle(fontSize: 13, height: 1.4))),
                  ],
                ),
              )),

          _detailSection('Suitable Filter Options', topic.filterOptions, Icons.filter_alt_outlined),
          _detailSection('Maintenance Instructions', topic.maintenanceInstructions, Icons.cleaning_services_outlined),
          _detailSection('When to Contact Certified Lab', topic.whenToContactLab, Icons.science_outlined),
        ],
      ),
    );
  }

  Widget _detailSection(String title, String content, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF087F8C)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF102A43)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(content,
              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildVideoCard(BuildContext context, VideoItem video) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _launchVideo(context, video.url),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 140,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF102A43), Color(0xFF087F8C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.play_circle_fill, color: Colors.red, size: 16),
                          const SizedBox(width: 5),
                          Text(video.category,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .20),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, size: 38, color: Colors.white),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .50),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        video.duration,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF102A43)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    video.description,
                    style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: const [
                      Icon(Icons.open_in_new, size: 14, color: Color(0xFF087F8C)),
                      SizedBox(width: 4),
                      Text(
                        'Watch on YouTube',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF087F8C)),
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
                    Text('pH ${sample['ph']} (Demo)  •  TDS ${sample['tds']} ppm (Demo)'),
                    Text('Turbidity ${sample['turbidity']} NTU (Hardware)  •  Flow ${flow.toStringAsFixed(2)} L/min (Hardware)'),
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
  final bool connected, refreshing;
  final String connectionMessage;
  final VoidCallback onRefresh;

  const SettingsPage({
    super.key,
    required this.connected,
    required this.refreshing,
    required this.connectionMessage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF102A43);
    const teal = Color(0xFF087F8C);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
        actions: [
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
          const Text('Device & Connection',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navy)),
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
          const Text('About',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navy)),
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
          const Center(
            child: Text(
              'Made by Tech in Air',
              style: TextStyle(color: navy, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}