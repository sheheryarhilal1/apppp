import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class QRCodeScanner extends StatefulWidget {
  @override
  _QRCodeScannerState createState() => _QRCodeScannerState();
}

class _QRCodeScannerState extends State<QRCodeScanner> {
  bool isScanning = true;
  bool isConnecting = false; // Indicates connection state
  MobileScannerController cameraController = MobileScannerController();
  String scannedData = "";

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.location.request();
  }

  void _parseQRCode(String code) {
    // Check if the QR code is a Wi-Fi configuration
    final wifiRegex = RegExp(r'WIFI:T:(?<type>[^;]*);S:(?<ssid>[^;]*);P:(?<password>[^;]*);H:(?<hidden>true|false);;');
    final wifiMatch = wifiRegex.firstMatch(code);

    if (wifiMatch != null) {
      final String ssid = wifiMatch.namedGroup('ssid')!;
      final String password = wifiMatch.namedGroup('password')!;
      final String encryptionType = wifiMatch.namedGroup('type')!;
      final bool isHidden = wifiMatch.namedGroup('hidden') == 'true';

      _connectToWiFi(ssid, password, isHidden, encryptionType);

      setState(() {
        scannedData = "SSID: $ssid\nPassword: $password\nEncryption: $encryptionType\nHidden: $isHidden";
      });
    }
    // Check if the QR code is a URL
    else if (Uri.tryParse(code)?.hasAbsolutePath ?? false) {
      setState(() {
        scannedData = "URL detected:\n$code";
      });
      _showConnectionResult("Detected a URL:\n$code");
    }
    // Treat as plain text
    else {
      setState(() {
        scannedData = "Text detected:\n$code";
      });
      _showConnectionResult("Detected plain text:\n$code");
    }
  }

  Future<void> _connectToWiFi(String ssid, String password, bool hidden, String encryptionType) async {
    setState(() {
      isConnecting = true; // Start connecting
    });

    final bool result = await WiFiForIoTPlugin.connect(
      ssid,
      password: password,
      security: encryptionType == 'WPA' ? NetworkSecurity.WPA : NetworkSecurity.WEP,
      isHidden: hidden,
    );

    if (result) {
      _showConnectionResult('Connected to Wi-Fi: $ssid');
      await _pingAPI();
    } else {
      _showConnectionResult('Failed to connect to Wi-Fi');
    }

    setState(() {
      isConnecting = false; // End connection state
    });
  }

  Future<void> _pingAPI() async {
    final String apiUrl = 'http://192.168.4.1/deviceinfo';

    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        _showConnectionResult('API Response: ${response.body}');
      } else {
        _showConnectionResult('API Call Failed with status: ${response.statusCode}');
      }
    } catch (e) {
      _showConnectionResult('API Error: $e');
    }
  }

  void _showConnectionResult(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Connection Result'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (capture.barcodes.isNotEmpty && isScanning) {
      final String? code = capture.barcodes.first.rawValue;
      if (code != null) {
        setState(() {
          isScanning = false;
          cameraController.stop();
        });

        _parseQRCode(code);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('QR Code Scanner'),
        actions: [
          IconButton(
            icon: Icon(Icons.flip_camera_ios),
            onPressed: () => cameraController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: EdgeInsets.all(16),
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: isScanning
                ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MobileScanner(
                controller: cameraController,
                onDetect: _onDetect,
              ),
            )
                : Center(child: Text('Scanning stopped')),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              scannedData.isNotEmpty ? scannedData : 'Point your camera at a QR code.',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          if (isConnecting) // Display loading indicator during connection
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  isScanning = true;
                  cameraController.start();
                });
              },
              child: Text('Start Scanning Again'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}