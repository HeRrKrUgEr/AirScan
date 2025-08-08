import 'package:flutter/material.dart';
import 'package:wifi_iot/wifi_iot.dart';

/// Entry point for the AirScan application.
///
/// This simple Flutter app serves as a starting point for a
/// cross‑platform Wi‑Fi analysis tool. It currently displays
/// a welcome message and sets up the theme and home page.
void main() {
  runApp(const AirScanApp());
}

/// Root widget of the application.
///
/// The [AirScanApp] uses a [MaterialApp] to provide
/// navigation, theming, and localization support. When the
/// application is further developed, additional routes can be
/// added here.
class AirScanApp extends StatelessWidget {
  const AirScanApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AirScan',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomePage(),
    );
  }
}

/// The initial screen shown when the app launches.
///
/// At this early stage of development the [HomePage] simply
/// displays a welcome message. Future iterations will include
/// real‑time Wi‑Fi statistics and navigation to more detailed
/// analysis pages.
/// Information about a nearby Wi‑Fi network.
///
/// This class encapsulates the key properties we care about
/// when scanning for access points: the network name (SSID),
/// BSSID, frequency, received signal strength (RSSI) and
/// computed channel number. Instances of this class are
/// constructed from the plugin‑specific `WifiNetwork` type.
class WifiAccessPoint {
  final String ssid;
  final String bssid;
  final int frequency;
  final int level;

  WifiAccessPoint({
    required this.ssid,
    required this.bssid,
    required this.frequency,
    required this.level,
  });

  /// Compute the wireless channel number from the carrier frequency.
  ///
  /// For 2.4 GHz bands we subtract 2407 MHz and divide by 5 MHz to get
  /// the channel index. For 5 GHz bands we subtract 5000 MHz and
  /// divide by 5 MHz. Values outside these ranges return 0.
  int get channel {
    if (frequency >= 2412 && frequency <= 2484) {
      return ((frequency - 2407) ~/ 5);
    }
    if (frequency >= 5000 && frequency <= 5900) {
      return ((frequency - 5000) ~/ 5);
    }
    return 0;
  }
}

/// The initial screen shown when the app launches.
///
/// At this stage of development the [HomePage] retrieves details
/// about the currently connected Wi‑Fi network, displays the
/// strongest neighbouring access points and offers basic
/// optimisation suggestions. From here users can navigate to a
/// separate page that visualises channel usage and potential
/// interference on a simple graph.
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _currentSsid = 'Unknown';
  String _currentBssid = '';
  int _currentFrequency = 0;
  int _currentRssi = 0;
  List<WifiAccessPoint> _networks = [];
  bool _loading = false;
  String _suggestion = '';

  @override
  void initState() {
    super.initState();
    _refreshCurrentConnection();
  }

  /// Query the plugin for details about the currently connected network.
  Future<void> _refreshCurrentConnection() async {
    try {
      // Import is intentionally deferred to avoid unused import warnings
      // when the app is built for web where the plugin isn’t supported.
      final wifi = await WiFiForIoTPlugin.getSSID();
      final bssid = await WiFiForIoTPlugin.getBSSID();
      final freq = await WiFiForIoTPlugin.getFrequency();
      final rssi = await WiFiForIoTPlugin.getCurrentSignalStrength();
      setState(() {
        _currentSsid = wifi ?? 'Unknown';
        _currentBssid = bssid ?? '';
        _currentFrequency = freq ?? 0;
        _currentRssi = rssi ?? 0;
      });
    } catch (e) {
      // If the plugin isn’t supported on this platform (e.g. web)
      // or another error occurs we keep the default values.
      debugPrint('Error retrieving current connection: $e');
    }
  }

  /// Initiate a scan for nearby Wi‑Fi networks. On platforms
  /// where scanning isn’t permitted (e.g. iOS) the plugin will
  /// throw and the list will remain empty.
  Future<void> _scanNetworks() async {
    setState(() {
      _loading = true;
      _networks = [];
      _suggestion = '';
    });
    try {
      final wifiList = await WiFiForIoTPlugin.loadWifiList();
      final results = wifiList
          .map((e) => WifiAccessPoint(
                ssid: e.ssid ?? '',
                bssid: e.bssid ?? '',
                frequency: e.frequency ?? 0,
                level: e.level ?? 0,
              ))
          .where((ap) => ap.ssid.isNotEmpty)
          .toList();
      results.sort((a, b) => b.level.compareTo(a.level));
      setState(() {
        _networks = results;
        _loading = false;
      });
      _generateSuggestion();
    } catch (e) {
      debugPrint('Error scanning networks: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  /// Analyse the scanned networks and provide a human friendly
  /// recommendation for improving the current connection. This
  /// considers congestion on the current channel and the
  /// availability of 5 GHz networks.
  void _generateSuggestion() {
    if (_currentFrequency == 0 || _networks.isEmpty) {
      setState(() {
        _suggestion = '';
      });
      return;
    }
    final currentChannel = WifiAccessPoint(
            ssid: '', bssid: '', frequency: _currentFrequency, level: 0)
        .channel;
    final channelCounts = <int, int>{};
    bool has5GHz = false;
    for (final ap in _networks) {
      channelCounts[ap.channel] = (channelCounts[ap.channel] ?? 0) + 1;
      if (ap.frequency >= 5000) has5GHz = true;
    }
    final congestedPeers = _networks.where((ap) => ap.channel == currentChannel);
    // Find the least congested channel among 2.4 GHz channels.
    int bestChannel = currentChannel;
    int bestCount = channelCounts[currentChannel] ?? 0;
    channelCounts.forEach((ch, count) {
      if (ch > 0 && count < bestCount) {
        bestChannel = ch;
        bestCount = count;
      }
    });
    String suggestion;
    if (congestedPeers.length > 3 && bestChannel != currentChannel) {
      suggestion =
          'Your current channel $currentChannel is congested by multiple nearby networks. '
          'Consider changing to channel $bestChannel for better performance.';
    } else {
      suggestion =
          'Your current channel $currentChannel looks relatively free. No immediate changes required.';
    }
    if (_currentFrequency < 5000 && has5GHz) {
      suggestion +=
          '\nThere are also 5 GHz networks available. Switching to a 5 GHz network can reduce interference if your router supports it.';
    }
    setState(() {
      _suggestion = suggestion;
    });
  }

  /// Navigate to the channel visualisation screen.
  void _openChannelMap() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChannelMapPage(networks: _networks)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AirScan')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Current Network',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: ListTile(
                title: Text(_currentSsid),
                subtitle: Text('BSSID: $_currentBssid'),
                trailing: Text(
                    '${(_currentRssi).toString()} dBm\n${_currentFrequency} MHz'),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loading ? null : _scanNetworks,
              icon: const Icon(Icons.wifi),
              label: Text(_loading ? 'Scanning...' : 'Scan for Networks'),
            ),
            const SizedBox(height: 16),
            if (_networks.isNotEmpty) ...[
              Text(
                'Nearby Networks',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: _networks.length,
                  itemBuilder: (context, index) {
                    final ap = _networks[index];
                    return ListTile(
                      title: Text(ap.ssid),
                      subtitle: Text('Channel ${ap.channel}, ${ap.frequency} MHz'),
                      trailing: Text('${ap.level} dBm'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_suggestion.isNotEmpty) ...[
              Text(
                'Suggestions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_suggestion),
              const SizedBox(height: 16),
            ],
            if (_networks.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _openChannelMap,
                icon: const Icon(Icons.map),
                label: const Text('Visualise Channels'),
              ),
          ],
        ),
      ),
    );
  }
}

/// A simple page that visualises wireless channel usage.
///
/// Rather than plotting geographic positions (which aren’t available
/// without additional hardware), this page displays a bar chart‑like
/// representation of the number of access points on each channel. It
/// helps users quickly identify which channels are congested.
class ChannelMapPage extends StatelessWidget {
  final List<WifiAccessPoint> networks;

  const ChannelMapPage({Key? key, required this.networks}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Compute counts per channel.
    final Map<int, int> counts = {};
    for (final ap in networks) {
      counts[ap.channel] = (counts[ap.channel] ?? 0) + 1;
    }
    final sortedChannels = counts.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Channel Usage')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Networks per Channel',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: sortedChannels.length,
                itemBuilder: (context, index) {
                  final ch = sortedChannels[index];
                  final count = counts[ch] ?? 0;
                  // Normalise bar length based on maximum count.
                  final maxCount = counts.values.isNotEmpty
                      ? counts.values.reduce((a, b) => a > b ? a : b)
                      : 1;
                  final ratio = count / maxCount;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text('Ch $ch'),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 10,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: AlwaysStoppedAnimation(
                                ratio > 0.5 ? Colors.red : Colors.green),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('$count'),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}