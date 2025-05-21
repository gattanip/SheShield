import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/contact.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'dart:async';
import '../services/location_service.dart';
import '../services/emergency_service.dart';

// (Assume you have a function to get the trusted contacts, for example, _loadContacts() returns a List<Contact>.)

Future<void> _sendSOSViaWhatsApp() async {
  // (1) Obtain trusted contacts (for example, from SharedPreferences or a model.)
  // (For demo, assume you have a list of trusted contacts.)
  List<Contact> trustedContacts = await _loadContacts();
  if (trustedContacts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No trusted contacts found."), backgroundColor: Colors.red),
    );
    return;
  }

  // (2) Obtain the current live location (using geolocator).
  // (Note: In a real app, you'd use a live location sharing service or a deep link to a live location link.)
  // (For demo, we'll use a static link (e.g., a Google Maps link) – replace with your live location link.)
  Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  String liveLocationLink = "https://maps.google.com/?q=${position.latitude},${position.longitude}";

  // (3) Compose the emergency message (for example, "SOS! I'm in danger. My live location is: ...")
  String emergencyMessage = "SOS! I'm in danger. My live location is: " + liveLocationLink;

  // (4) Iterate over trusted contacts and send a WhatsApp deep link (or open WhatsApp externally) for each.
  for (var contact in trustedContacts) {
    // (a) Clean the phone number (remove +, spaces, and add 91 if needed) – (you can use a helper function.)
    String phoneNumber = contact.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (phoneNumber.length == 10 && !phoneNumber.startsWith("91")) {
      phoneNumber = "91" + phoneNumber;
    }
    // (b) Compose a WhatsApp deep link (or use a package like url_launcher to open WhatsApp externally.)
    // (For demo, we'll use a deep link. In a real app, you'd use a package like url_launcher.)
    // (Note: The deep link below is a sketch – you may need to adjust it or use a package.)
    String whatsappDeepLink = "whatsapp://send?phone=" + phoneNumber + "&text=" + Uri.encodeComponent(emergencyMessage);
    // (c) Launch the deep link (or open WhatsApp externally) – (using url_launcher or a similar package.)
    // (For demo, we'll use a "launch" call – in a real app, you'd use a package like url_launcher.)
    // (Note: You'd typically use a package like url_launcher to open the deep link externally.)
    // (For example, you'd do: await launch(whatsappDeepLink);)
    // (For demo, we'll print the deep link – in a real app, you'd launch it.)
    if (await canLaunch(whatsappDeepLink)) {
      await launch(whatsappDeepLink);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open WhatsApp."), backgroundColor: Colors.red),
      );
    }
  }
  // (5) (Optional) Show a snackbar (or a dialog) to confirm that SOS was sent.
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("SOS sent via WhatsApp (with live location link)."), backgroundColor: Colors.green),
  );
}

Timer? _timer;

Future<void> _sendSOSViaSMS() async {
  // (1) Obtain trusted contacts (for example, from SharedPreferences or a model.)
  // (For demo, assume you have a list of trusted contacts.)
  List<Contact> trustedContacts = await _loadContacts();
  if (trustedContacts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No trusted contacts found."), backgroundColor: Colors.red),
    );
    return;
  }

  // (2) Obtain the current live location (using geolocator).
  // (Note: In a real app, you'd use a live location sharing service or a deep link to a live location link.)
  // (For demo, we'll use a static link (e.g., a Google Maps link) – replace with your live location link.)
  // (Replace the placeholder with the actual live location (using Geolocator).)
  Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  String liveLocationLink = "https://maps.google.com/?q=${position.latitude},${position.longitude}";

  // (3) Compose the emergency message (for example, "SOS! I'm in danger. My live location is: ...")
  String emergencyMessage = "SOS! I'm in danger. My live location is: " + liveLocationLink;

  // (4) Iterate over trusted contacts and send an SMS (using a deep link (or a package like url_launcher) to open the SMS app.)
  for (var contact in trustedContacts) {
    // (a) Clean the phone number (remove +, spaces, and add 91 if needed) – (you can use a helper function.)
    String phoneNumber = contact.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (phoneNumber.length == 10 && !phoneNumber.startsWith("91")) {
      phoneNumber = "91" + phoneNumber;
    }
    // (b) Compose an SMS deep link (or use a package like url_launcher to open the SMS app.)
    // (For demo, we'll use a deep link. In a real app, you'd use a package like url_launcher.)
    // (Note: The deep link below is a sketch – you may need to adjust it or use a package.)
    String smsDeepLink = "sms:" + phoneNumber + "?body=" + Uri.encodeComponent(emergencyMessage);
    // (c) Launch the deep link (or open the SMS app externally) – (using url_launcher or a similar package.)
    // (For demo, we'll use a "launch" call – in a real app, you'd use a package like url_launcher.)
    // (Note: You'd typically use a package like url_launcher to open the deep link externally.)
    // (For example, you'd do: await launch(smsDeepLink);)
    // (For demo, we'll print the deep link – in a real app, you'd launch it.)
    // (In a real app, you'd do: await launch(smsDeepLink);)
    if (await canLaunch(smsDeepLink)) {
      await launch(smsDeepLink);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open SMS app."), backgroundColor: Colors.red),
      );
    }
  }
  // (5) (Optional) Show a snackbar (or a dialog) to confirm that SOS was sent.
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("SOS sent via SMS (with live location link)."), backgroundColor: Colors.green),
  );
}

Future<void> _startSOS() async {
  // (Immediately send SOS (with live location) via WhatsApp and SMS.)
  await _sendSOSViaWhatsApp();
  await _sendSOSViaSMS();
  // (Start a timer (every 5 minutes) to send SOS (with live location) via WhatsApp and SMS.)
  _timer = Timer.periodic(const Duration(minutes: 5), (timer) async {
    await _sendSOSViaWhatsApp();
    await _sendSOSViaSMS();
  });
}

void _cancelSOS() {
  if (_timer != null) {
    _timer!.cancel();
    _timer = null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("SOS cancelled."), backgroundColor: Colors.green),
    );
  }
}

// (Assume you have a SOS button (or a trigger) that calls _startSOS.)

// (For example, in your SOS screen's build method, you might have a button like this:)
// ElevatedButton(
//   onPressed: () async { await _startSOS(); },
//   child: const Text("SOS (Send via WhatsApp & SMS)"),
// )

// (Assume you have a "Cancel SOS" button (or trigger) that calls _cancelSOS.)

// (For example, in your SOS screen's build method, you might have a button like this:)
// ElevatedButton(
//   onPressed: () { _cancelSOS(); },
//   child: const Text("Cancel SOS"),
// )

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _locationService = LocationService();
  final _emergencyService = EmergencyService();
  bool _isLoading = false;

  Future<void> _startSOS() async {
    setState(() => _isLoading = true);
    
    try {
      // Start location sharing
      await _locationService.startLocationSharing();
      
      // Get tracking URL and share via WhatsApp
      final trackingUrl = _locationService.getTrackingUrl();
      await _emergencyService.shareLocationViaWhatsApp(trackingUrl);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS activated! Location sharing started.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _stopSOS() async {
    setState(() => _isLoading = true);
    
    try {
      await _locationService.stopLocationSharing();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location sharing stopped.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSharing = _locationService.isSharing;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('SheShield SOS'),
        backgroundColor: Colors.red,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              const CircularProgressIndicator()
            else if (isSharing)
              Column(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Location Sharing Active',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _stopSOS,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Sharing'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  const Text(
                    'Press the SOS button to share your location',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _startSOS,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(32),
                    ),
                    child: const Text(
                      'SOS',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
} 