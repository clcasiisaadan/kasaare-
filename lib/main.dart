import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print("Firebase initialization error: $e");
  }

  SharedPreferences prefs = await SharedPreferences.getInstance();
  
  bool isRegistered = prefs.getBool('isRegistered') ?? false;
  String type = prefs.getString('type') ?? 'ZAAD';
  
  Map<String, String> initialData = {
    'type': type,
    'phone': prefs.getString('phone') ?? '',
    'adminPin': prefs.getString('adminPin') ?? '',
    'zaadPin': prefs.getString('zaadPin') ?? '',
    'accountNumber': prefs.getString('accountNumber') ?? '',
    'registerPin': prefs.getString('registerPin') ?? '',
  };

  runApp(MyApp(isRegistered: isRegistered, initialData: initialData));
}

String sanitizeDeviceId(String input) {
  String cleaned = input.trim().toUpperCase();
  if (cleaned.contains("DEVICE ID:")) {
    cleaned = cleaned.split("DEVICE ID:").last.trim();
  }
  while (cleaned.endsWith('.')) {
    cleaned = cleaned.substring(0, cleaned.length - 1).trim();
  }
  return cleaned;
}

class MyApp extends StatelessWidget {
  final bool isRegistered;
  final Map<String, String> initialData;

  const MyApp({required this.isRegistered, required this.initialData});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      home: !isRegistered 
          ? RegistrationFormScreen(isFirstTime: true) 
          : LicenseCheckWrapper(child: ZaadHomeScreen(registrationData: initialData)),
    );
  }
}

class LicenseCheckWrapper extends StatefulWidget {
  final Widget child;
  const LicenseCheckWrapper({required this.child});

  @override
  _LicenseCheckWrapperState createState() => _LicenseCheckWrapperState();
}

class _LicenseCheckWrapperState extends State<LicenseCheckWrapper> {
  bool _isLoading = true;
  bool _isLicensed = false;
  String _deviceId = '';

  @override
  void initState() {
    super.initState();
    _checkLicenseFromFirebase();
  }

  Future<String> _getUniqueDeviceId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('app_device_id');
    
    if (storedId != null && storedId.isNotEmpty && storedId != "74EDF0753D14ADFE") {
      return sanitizeDeviceId(storedId);
    }

    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String newDeviceId = '';

    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        if (androidInfo.id.isNotEmpty) {
          newDeviceId = androidInfo.id.toUpperCase();
        } else {
          newDeviceId = "${androidInfo.model.toUpperCase()}_${DateTime.now().millisecondsSinceEpoch}";
        }
      } else {
        newDeviceId = DateTime.now().millisecondsSinceEpoch.toString();
      }
    } catch (e) {
      newDeviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    newDeviceId = sanitizeDeviceId(newDeviceId);
    await prefs.setString('app_device_id', newDeviceId);
    return newDeviceId;
  }

  Future<void> _checkLicenseFromFirebase() async {
    String deviceId = await _getUniqueDeviceId();
    SharedPreferences prefs = await SharedPreferences.getInstance();

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('licenses')
          .doc(deviceId)
          .get(const GetOptions(source: Source.serverAndCache));

      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;
        bool isApproved = data['isApproved'] ?? false;
        int expiryMillis = data['expiryMillis'] ?? 0;

        bool licensed = isApproved && (DateTime.now().millisecondsSinceEpoch < expiryMillis);

        await prefs.setBool('is_admin_approved', isApproved);
        await prefs.setInt('license_expiry_millis', expiryMillis);

        if (mounted) {
          setState(() {
            _deviceId = deviceId;
            _isLicensed = licensed;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      print("Firestore check error: $e");
    }

    bool isApproved = prefs.getBool('is_admin_approved') ?? false;
    int expiryMillis = prefs.getInt('license_expiry_millis') ?? 0;

    bool licensed = isApproved && expiryMillis > 0 && (DateTime.now().millisecondsSinceEpoch < expiryMillis);

    if (mounted) {
      setState(() {
        _deviceId = deviceId;
        _isLicensed = licensed;
        _isLoading = false;
      });
    }
  }

  void _sendWhatsAppRequest() async {
    String phoneNumber = "252634187078";
    String message = "Asc Admin, fadlan i siidaa app-ka.\n\nDevice ID:\n$_deviceId";
    
    Clipboard.setData(ClipboardData(text: _deviceId));

    final Uri whatsappAppUri = Uri.parse("whatsapp://send?phone=$phoneNumber&text=${Uri.encodeComponent(message)}");
    final Uri whatsappWebUri = Uri.parse("https://wa.me/$phoneNumber?text=${Uri.encodeComponent(message)}");

    try {
      if (await canLaunchUrl(whatsappAppUri)) {
        await launchUrl(whatsappAppUri);
      } else {
        await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Device ID waa la koobiyay!")),
      );
    }
  }

  void _verifyAdminAcceptance() async {
    setState(() => _isLoading = true);
    await _checkLicenseFromFirebase();
    
    if (_isLicensed) {
      if (mounted) {
        setState(() {});
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request-kii waa la xaqiijiyay! App-ku wuu kuu furmay."), backgroundColor: Colors.green),
      );
    } else {
      if (mounted) {
        setState(() {});
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Amniga: Admin-ku weli kuguma oggolaan ama mudadii ayaa dhacday!"), backgroundColor: Colors.red),
      );
    }
  }

  void _showAdminPasswordDialog() {
    final TextEditingController adminIdController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("Oggolaanshaha Admin-ka", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Geli Admin ID-ga iyo Password-ka:"),
              const SizedBox(height: 15),
              TextField(
                controller: adminIdController,
                decoration: InputDecoration(
                  labelText: "Admin ID",
                  prefixIcon: const Icon(Icons.person, color: Colors.teal),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: "Password-ka",
                  prefixIcon: const Icon(Icons.lock, color: Colors.teal),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Ka noqor"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () async {
                String expectedAdminId = "AP3A.240905.015.A2";
                String expectedAdminPassword = "9379";

                try {
                  DocumentSnapshot adminDoc = await FirebaseFirestore.instance.collection('settings').doc('admin_config').get();
                  if (adminDoc.exists) {
                    var data = adminDoc.data() as Map<String, dynamic>;
                    expectedAdminId = data['adminId'] ?? expectedAdminId;
                    expectedAdminPassword = data['adminPassword'] ?? expectedAdminPassword;
                  }
                } catch (e) {
                  print("Error fetching admin credentials: $e");
                }

                String inputId = adminIdController.text.trim();
                String inputPass = passwordController.text.trim();

                if (inputId == expectedAdminId && inputPass == expectedAdminPassword) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AdminRequestScreen()),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Admin ID ama Password waa khalad!"), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text("Gali", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.teal)));
    }

    if (!_isLicensed) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("App-ka Wuu Xidhan Yahay"),
          backgroundColor: Colors.teal,
          actions: [
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: _showAdminPasswordDialog,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_clock, size: 70, color: Colors.orange[800]),
              const SizedBox(height: 20),
              Text(
                "Fadlan Device ID-ga u dir Admin-ka (0634187078).",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red[700]),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(_deviceId, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold))),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.teal),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _deviceId));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Device ID waa la koobiyay!")));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _sendWhatsAppRequest,
                icon: const Icon(Icons.chat, color: Colors.white),
                label: const Text("WhatsApp-ka U Dir Admin-ka", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 15),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _verifyAdminAcceptance,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("Xaqiiji Oggolaansaha Firebase", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}

class AdminRequestScreen extends StatefulWidget {
  @override
  _AdminRequestScreenState createState() => _AdminRequestScreenState();
}

class _AdminRequestScreenState extends State<AdminRequestScreen> {
  final TextEditingController _adminDeviceIdController = TextEditingController();
  final TextEditingController _durationController = TextEditingController(text: "30");
  
  String _selectedDurationType = 'days';

  void _acceptCustomerRequest() async {
    String rawInput = _adminDeviceIdController.text;
    String targetDeviceId = sanitizeDeviceId(rawInput);

    int durationVal = int.tryParse(_durationController.text.trim()) ?? 30;

    if (targetDeviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fadlan geli Device ID-ga!"), backgroundColor: Colors.orange),
      );
      return;
    }

    DateTime baseDate = DateTime.now();

    int expiryMillis;
    if (_selectedDurationType == 'days') {
      expiryMillis = baseDate.add(Duration(days: durationVal)).millisecondsSinceEpoch;
    } else {
      expiryMillis = baseDate.add(Duration(minutes: durationVal)).millisecondsSinceEpoch;
    }
    
    try {
      await FirebaseFirestore.instance.collection('licenses').doc(targetDeviceId).set({
        'isApproved': true,
        'expiryMillis': expiryMillis,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      String unitText = _selectedDurationType == 'days' ? "cisho" : "daqiiqadood";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Device ID ($targetDeviceId) waa la oggolaaday $durationVal $unitText!"), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Khalad ka dhacay Firebase: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Maamulka Requests (Admin)"), backgroundColor: Colors.teal),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _adminDeviceIdController,
                decoration: InputDecoration(
                  labelText: "Geli Device ID-ga Macmiilka", 
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste, color: Colors.teal),
                    onPressed: () async {
                      ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data != null && data.text != null) {
                        setState(() {
                          _adminDeviceIdController.text = sanitizeDeviceId(data.text!);
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              const Text("Dooro Nooca Mudada:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text("Days (Cisho)"),
                      value: 'days',
                      groupValue: _selectedDurationType,
                      activeColor: Colors.teal,
                      onChanged: (val) {
                        setState(() {
                          _selectedDurationType = val!;
                          if (_durationController.text == "1" || _durationController.text == "") {
                            _durationController.text = "30";
                          }
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text("Minutes (Daqiiqad)"),
                      value: 'minutes',
                      groupValue: _selectedDurationType,
                      activeColor: Colors.teal,
                      onChanged: (val) {
                        setState(() {
                          _selectedDurationType = val!;
                          if (_durationController.text == "30" || _durationController.text == "") {
                            _durationController.text = "1";
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _selectedDurationType == 'days' ? "Mudada (Cisho)" : "Mudada (Daqiiqad)",
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _acceptCustomerRequest,
                  child: const Text("Accept & Activate Device ID", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RegistrationFormScreen extends StatefulWidget {
  final bool isFirstTime;
  const RegistrationFormScreen({this.isFirstTime = false});

  @override
  _RegistrationFormScreenState createState() => _RegistrationFormScreenState();
}

class _RegistrationFormScreenState extends State<RegistrationFormScreen> {
  int selectedOption = 1;

  final TextEditingController recipientPhoneController = TextEditingController();
  final TextEditingController adminPinController = TextEditingController();
  final TextEditingController zaadPin1Controller = TextEditingController();

  final TextEditingController bankAccountNumberController = TextEditingController();
  final TextEditingController bankZaadPinController = TextEditingController();
  final TextEditingController registerPinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  void _loadExistingData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String type = prefs.getString('type') ?? 'ZAAD';
    setState(() {
      selectedOption = (type == 'ZAAD') ? 1 : 2;
      recipientPhoneController.text = prefs.getString('phone') ?? '';
      adminPinController.text = prefs.getString('adminPin') ?? '';
      zaadPin1Controller.text = prefs.getString('zaadPin') ?? '';
      bankAccountNumberController.text = prefs.getString('accountNumber') ?? '';
      bankZaadPinController.text = prefs.getString('zaadPin') ?? '';
      registerPinController.text = prefs.getString('registerPin') ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Diiwaangelinta Adeegyada", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        automaticallyImplyLeading: !widget.isFirstTime,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            const Text("Dooro Nooca Adeegga:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<int>(
                    title: const Text("ZAAD"),
                    value: 1,
                    groupValue: selectedOption,
                    activeColor: Colors.teal,
                    onChanged: (val) => setState(() => selectedOption = val!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<int>(
                    title: const Text("Salaam Bank"),
                    value: 2,
                    groupValue: selectedOption,
                    activeColor: Colors.teal,
                    onChanged: (val) => setState(() => selectedOption = val!),
                  ),
                ),
              ],
            ),
            const Divider(height: 30),

            if (selectedOption == 1) ...[
              const Text("Dirista Lacagta (ZAAD)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(height: 15),
              TextField(
                controller: recipientPhoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: "Numberka Loo Dirayo",
                  prefixIcon: const Icon(Icons.phone, color: Colors.teal),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: adminPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Admin PIN-ka (*806* lagu dhex darayo)",
                  prefixIcon: const Icon(Icons.security, color: Colors.teal),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: zaadPin1Controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Binka Zaad-ka (Pop-up-ka la gelinayo)",
                  prefixIcon: const Icon(Icons.lock, color: Colors.teal),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],

            if (selectedOption == 2) ...[
              const Text("Salaam Bank (*800# Deposit)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(height: 15),
              TextField(
                controller: bankAccountNumberController,
                decoration: InputDecoration(
                  labelText: "Account-ka Bank-ga",
                  prefixIcon: const Icon(Icons.account_balance, color: Colors.teal),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: bankZaadPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Binka Zaadka",
                  prefixIcon: const Icon(Icons.lock, color: Colors.teal),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: registerPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Register PIN-ka Account-ka",
                  prefixIcon: const Icon(Icons.pin, color: Colors.teal),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],

            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();

                if (selectedOption == 1) {
                  if (recipientPhoneController.text.isEmpty || zaadPin1Controller.text.isEmpty || adminPinController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Fadlan buuxi dhammaan meelaha banaan!")),
                    );
                    return;
                  }

                  await prefs.setString('type', 'ZAAD');
                  await prefs.setString('phone', recipientPhoneController.text);
                  await prefs.setString('adminPin', adminPinController.text);
                  await prefs.setString('zaadPin', zaadPin1Controller.text);
                } else {
                  if (bankAccountNumberController.text.isEmpty || 
                      bankZaadPinController.text.isEmpty || 
                      registerPinController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Fadlan buuxi dhammaan meelaha banaan!")),
                    );
                    return;
                  }

                  await prefs.setString('type', 'SALAAM BANK');
                  await prefs.setString('accountNumber', bankAccountNumberController.text);
                  await prefs.setString('zaadPin', bankZaadPinController.text);
                  await prefs.setString('registerPin', registerPinController.text);
                }

                await prefs.setBool('isRegistered', true);

                Map<String, String> regData = {
                  'type': prefs.getString('type') ?? 'ZAAD',
                  'phone': prefs.getString('phone') ?? '',
                  'adminPin': prefs.getString('adminPin') ?? '',
                  'zaadPin': prefs.getString('zaadPin') ?? '',
                  'accountNumber': prefs.getString('accountNumber') ?? '',
                  'registerPin': prefs.getString('registerPin') ?? '',
                };

                if (widget.isFirstTime) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LicenseCheckWrapper(
                        child: ZaadHomeScreen(registrationData: regData),
                      ),
                    ),
                  );
                } else {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ZaadHomeScreen(registrationData: regData),
                    ),
                  );
                }
              },
              child: const Text("Keydi oo Diiwaangeli", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class ZaadHomeScreen extends StatefulWidget {
  final Map<String, String> registrationData;
  const ZaadHomeScreen({required this.registrationData});

  @override
  _ZaadHomeScreenState createState() => _ZaadHomeScreenState();
}

class _ZaadHomeScreenState extends State<ZaadHomeScreen> {
  static const platform = MethodChannel('com.example.zaad_auto/ussd');
  
  bool _isDataVisible = false;
  
  bool _appActiveOn = false; 
  bool _checkBalanceOn = false;
  int _selectedIntervalVal = 20; 
  String _timeRemainingText = "0d 0h";
  String _deviceId = "Gudbinayaa...";

  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    
    _loadSettings();
    _calculateRemainingTime();
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateRemainingTime();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  void _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? devId = prefs.getString('app_device_id');
    setState(() {
      _appActiveOn = prefs.getBool('accessibility_access_on') ?? false;
      _checkBalanceOn = prefs.getBool('check_balance_on') ?? false;
      _selectedIntervalVal = prefs.getInt('flutter.check_balance_interval_val') ?? 20;
      if (devId != null && devId.isNotEmpty) {
        _deviceId = sanitizeDeviceId(devId);
      }
    });
  }

  void _sendWhatsAppDirectRequest() async {
    String phoneNumber = "252634187078";
    String message = "Asc Admin, fadlan i siidaa app-ka.\n\nDevice ID:\n$_deviceId";
    
    Clipboard.setData(ClipboardData(text: _deviceId));

    final Uri whatsappAppUri = Uri.parse("whatsapp://send?phone=$phoneNumber&text=${Uri.encodeComponent(message)}");
    final Uri whatsappWebUri = Uri.parse("https://wa.me/$phoneNumber?text=${Uri.encodeComponent(message)}");

    try {
      if (await canLaunchUrl(whatsappAppUri)) {
        await launchUrl(whatsappAppUri);
      } else {
        await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Device ID waa la koobiyay!")),
      );
    }
  }

  void _lockAppAutomatically() async {
    _countdownTimer?.cancel();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    await prefs.setBool('is_admin_approved', false);
    await prefs.remove('license_expiry_millis');

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => LicenseCheckWrapper(
            child: ZaadHomeScreen(registrationData: widget.registrationData),
          ),
        ),
        (route) => false,
      );
    }
  }

  void _refreshLicenseStatus() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Waa la hubinayaa xogtaada..."), duration: Duration(seconds: 1)),
    );

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? currentDeviceId = prefs.getString('app_device_id');

    if (currentDeviceId != null && currentDeviceId.isNotEmpty) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('licenses')
            .doc(sanitizeDeviceId(currentDeviceId))
            .get(const GetOptions(source: Source.serverAndCache));

        if (doc.exists) {
          var data = doc.data() as Map<String, dynamic>;
          int firestoreExpiry = data['expiryMillis'] ?? 0;
          bool isApproved = data['isApproved'] ?? false;

          await prefs.setInt('license_expiry_millis', firestoreExpiry);
          await prefs.setBool('is_admin_approved', isApproved);

          if (isApproved && DateTime.now().millisecondsSinceEpoch < firestoreExpiry) {
            _calculateRemainingTime();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Waqtigaaga waa la cusboonaysiiyay!"), backgroundColor: Colors.green),
            );
            return;
          }
        }
      } catch (e) {
        print("Refresh error: $e");
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Weli Admin-ku ma oggolaan ama internetka ayaa xidhan."), backgroundColor: Colors.orange),
    );
  }

  void _calculateRemainingTime() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int expiryMillis = prefs.getInt('license_expiry_millis') ?? 0;

    String? currentDeviceId = prefs.getString('app_device_id');
    
    if (currentDeviceId != null && currentDeviceId.isNotEmpty) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('licenses')
            .doc(sanitizeDeviceId(currentDeviceId))
            .get();

        if (doc.exists) {
          var data = doc.data() as Map<String, dynamic>;
          int firestoreExpiry = data['expiryMillis'] ?? expiryMillis;
          bool isApproved = data['isApproved'] ?? false;

          if (!isApproved) {
            _lockAppAutomatically();
            return;
          }

          expiryMillis = firestoreExpiry;
          await prefs.setInt('license_expiry_millis', expiryMillis);
          await prefs.setBool('is_admin_approved', true);
        }
      } catch (e) {
        print("Firebase time fetch error: $e");
      }
    }

    if (expiryMillis == 0) {
      _lockAppAutomatically();
      return;
    }

    try {
      DateTime expiryDate = DateTime.fromMillisecondsSinceEpoch(expiryMillis);
      Duration remaining = expiryDate.difference(DateTime.now());

      if (remaining.isNegative || remaining.inSeconds <= 0) {
        _lockAppAutomatically();
      } else {
        int days = remaining.inDays;
        int hours = remaining.inHours % 24;
        int minutes = remaining.inMinutes % 60;
        int seconds = remaining.inSeconds % 60;

        if (mounted) {
          setState(() {
            if (days > 0) {
              _timeRemainingText = "${days}d ${hours}h";
            } else if (hours > 0) {
              _timeRemainingText = "${hours}h ${minutes}m";
            } else if (minutes > 0) {
              _timeRemainingText = "${minutes}m ${seconds}s";
            } else {
              _timeRemainingText = "${seconds}s";
            }
          });
        }
      }
    } catch (e) {
      _lockAppAutomatically();
    }
  }

  void _updateAppActiveState(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    await prefs.setBool('accessibility_access_on', value);
    await prefs.setBool('flutter.accessibility_access_on', value);
    await prefs.setBool('auto_transfer_on', value);
    await prefs.setBool('flutter.auto_transfer_on', value);
    await prefs.setBool('flutter.auto_transfer', value);

    setState(() {
      _appActiveOn = value;
    });

    if (value) {
      try {
        await platform.invokeMethod('openAccessibilitySettings');
      } catch (e) {
        print("Khalad Settings Opening: $e");
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("App-ka iyo Lacag Diristu waa la joojiyay (OFF).")),
      );
    }
  }

  void _updateCheckBalance(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('check_balance_on', value);
    await prefs.setBool('flutter.check_balance_on', value);
    setState(() {
      _checkBalanceOn = value;
    });
  }

  void _updateCheckInterval(int secondsVal) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('flutter.check_balance_interval_val', secondsVal);
    setState(() {
      _selectedIntervalVal = secondsVal;
    });
  }

  void _triggerCheckBalance() async {
    if (!_appActiveOn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fadlan marka hore fure Shaqada App-ka!"), backgroundColor: Colors.orange),
      );
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flutter.manual_check', true);
    
    String type = widget.registrationData['type'] ?? 'ZAAD';
    String ussdCode = (type == 'SALAAM BANK') ? '*800#' : '*801#';

    try {
      await platform.invokeMethod('dialUssd', {'code': ussdCode});
    } catch (e) {
      print("Khalad USSD: $e");
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Waxaa la bilaabay Check Balance ($ussdCode)...")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.registrationData;
    String displayType = data['type'] ?? 'ZAAD';

    final Map<int, String> intervalOptions = {
      10: "10 Seconds",
      20: "20 Seconds",
      30: "30 Seconds",
      60: "1 Minute",
      120: "2 Minutes",
      180: "3 Minutes",
      240: "4 Minutes",
      300: "5 Minutes",
      360: "6 Minutes",
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zaad & Bank Home', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.app_registration, color: Colors.white),
            tooltip: "Beddel Diiwaangelinta",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RegistrationFormScreen(isFirstTime: false),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: "Refresh License",
            onPressed: _refreshLicenseStatus,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              color: Colors.teal.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      "SUBSCRIPTION STATUS",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal[800],
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Device ID",
                              style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  _deviceId,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal[900],
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: _deviceId));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Device ID waa la koobiyay!")),
                                    );
                                  },
                                  child: Icon(Icons.copy, size: 16, color: Colors.teal[700]),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Time Left",
                              style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _timeRemainingText,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal[900],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    "Xogtaadii Diiwaangelinta", 
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[800]),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "Kadalbo halkan mudo kordhinta",
                      style: TextStyle(
                        fontSize: 11, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.teal.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: _sendWhatsAppDirectRequest,
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green[600],
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2))
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              "WhatsApp", 
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              color: Colors.teal.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Nooca: $displayType", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal[900])),
                        const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                    Divider(color: Colors.teal.shade200, height: 20),

                    if (displayType == 'ZAAD') ...[
                      Row(
                        children: [
                          const Text("• Numberka Loo Dirayo: ", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                          Text(
                            _isDataVisible ? (data['phone'] ?? '') : '*****',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal[900]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text("• Admin PIN-ka: ", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                          Text(
                            _isDataVisible ? (data['adminPin'] ?? '') : '*****',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal[900]),
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          const Text("• Account-ka Bank-ga: ", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                          Text(
                            _isDataVisible ? (data['accountNumber'] ?? '') : '*****',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal[900]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text("• Register PIN-ka: ", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                          Text(
                            _isDataVisible ? (data['registerPin'] ?? '') : '*****',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal[900]),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text("• Binka Zaad-ka: ", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        Text(
                          _isDataVisible ? (data['zaadPin'] ?? '') : '****',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal[900]),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(_isDataVisible ? Icons.visibility : Icons.visibility_off, color: Colors.teal[800]),
                          onPressed: () => setState(() => _isDataVisible = !_isDataVisible),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.security_rounded, size: 45, color: Colors.teal),
                    const SizedBox(height: 8),
                    Text("Dejinta Oggolaanshaha App-ka", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                    const SizedBox(height: 10),
                    
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text("Shaqada App-ka (Auto Transfer)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey[800])),
                      subtitle: Text(_appActiveOn ? "Shaqadu waa ON (Lacagta wuu dirayaa)" : "Shaqadu waa OFF (App-ku ma shaqaynayo)", style: const TextStyle(fontSize: 12)),
                      value: _appActiveOn,
                      activeColor: Colors.teal,
                      onChanged: _updateAppActiveState,
                    ),
                    const Divider(height: 15),
                    
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
                        child: Text("BALANCE CHECKER", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFE91E63))),
                      ),
                    ),
                    
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text("Active Check Balance", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey[800])),
                      value: _checkBalanceOn,
                      activeColor: const Color(0xFFE91E63),
                      onChanged: _updateCheckBalance,
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Isku-Dhayaha (Interval):", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.pink.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE91E63), width: 1),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: intervalOptions.containsKey(_selectedIntervalVal) ? _selectedIntervalVal : 20,
                                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFE91E63)),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE91E63), fontSize: 14),
                                onChanged: (int? newValue) {
                                  if (newValue != null) {
                                    _updateCheckInterval(newValue);
                                  }
                                },
                                items: intervalOptions.entries.map<DropdownMenuItem<int>>((entry) {
                                  return DropdownMenuItem<int>(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 15),

                    ElevatedButton(
                      onPressed: _triggerCheckBalance,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE91E63),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Check Balance Now!', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}