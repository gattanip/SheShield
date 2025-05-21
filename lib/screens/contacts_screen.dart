import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sheshield/models/contact.dart';
import 'package:sheshield/services/emergency_service.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:telephony/telephony.dart';
import 'dart:convert';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final EmergencyService _emergencyService = EmergencyService();
  final Telephony telephony = Telephony.instance;
  List<EmergencyContact> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await _emergencyService.getContacts();
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading contacts: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  // Format phone number to E.164 format (e.g., +1234567890)
  String _formatPhoneNumber(String phoneNumber) {
    // Remove all non-digit characters
    String digits = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    
    // If number starts with 0, replace with country code (assuming India +91)
    if (digits.startsWith('0')) {
      digits = '91${digits.substring(1)}';
    }
    
    // If number doesn't start with country code, add +91 (India)
    if (!digits.startsWith('91')) {
      digits = '91$digits';
    }
    
    // Add + prefix
    return '+$digits';
  }

  // Send SMS to a contact
  Future<void> _sendSMS(EmergencyContact contact, String message) async {
    try {
      // Request SMS permission
      final bool? permissionGranted = await telephony.requestPhoneAndSmsPermissions;
      
      if (permissionGranted != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SMS permission denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Send SMS
      await telephony.sendSms(
        to: contact.phoneNumber,
        message: message,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS sent successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending SMS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickContact() async {
    try {
      // Request contact permission
      final permission = await FlutterContacts.requestPermission();
      if (!permission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contact permission denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Open contact picker
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;

      // Get full contact details
      final fullContact = await FlutterContacts.getContact(contact.id);
      if (fullContact == null) return;

      // Get the first phone number
      if (fullContact.phones.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected contact has no phone number'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Format phone number
      final formattedPhone = _formatPhoneNumber(fullContact.phones.first.number);

      // Show dialog to confirm adding the contact
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add Emergency Contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Name: ${fullContact.displayName}'),
              const SizedBox(height: 8),
              Text('Original Phone: ${fullContact.phones.first.number}'),
              Text('Formatted Phone: $formattedPhone'),
              if (fullContact.emails.isNotEmpty)
                Text('Email: ${fullContact.emails.first.address}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // Create emergency contact with formatted phone number
        final emergencyContact = EmergencyContact(
          name: fullContact.displayName,
          phoneNumber: formattedPhone,
          email: fullContact.emails.isNotEmpty ? fullContact.emails.first.address : null,
        );

        // Add to emergency contacts
        await _emergencyService.addContact(emergencyContact);
        await _loadContacts();

        // Send test SMS to verify contact
        await _sendSMS(
          emergencyContact,
          'Hello ${emergencyContact.name}, you have been added as an emergency contact in SheShield app. You will receive alerts in case of emergency.',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contact added and verified successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking contact: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addContact() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();

    final result = await showDialog<EmergencyContact>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Emergency Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Enter contact name',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: 'Enter phone number with country code',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email (Optional)',
                hintText: 'Enter email address',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isEmpty || phoneController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name and phone number are required')),
                );
                return;
              }
              Navigator.pop(
                context,
                EmergencyContact(
                  name: nameController.text,
                  phoneNumber: phoneController.text,
                  email: emailController.text.isEmpty ? null : emailController.text,
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await _emergencyService.addContact(result);
        await _loadContacts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contact added successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding contact: $e')),
          );
        }
      }
    }
  }

  Future<void> _removeContact(EmergencyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Contact'),
        content: Text('Are you sure you want to remove ${contact.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _emergencyService.removeContact(contact);
        await _loadContacts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contact removed successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error removing contact: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
      ),
      body: _contacts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No emergency contacts added yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickContact,
                    icon: const Icon(Icons.contacts),
                    label: const Text('Pick from Contacts'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'or',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _addContact,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Manually'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                return Dismissible(
                  key: Key(contact.phoneNumber),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _removeContact(contact),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(contact.name[0].toUpperCase()),
                    ),
                    title: Text(contact.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(contact.phoneNumber),
                        if (contact.email != null) Text(contact.email!),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.message),
                          onPressed: () => _sendSMS(
                            contact,
                            'Test message from SheShield app. This is to verify the emergency contact setup.',
                          ),
                          tooltip: 'Send Test SMS',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _removeContact(contact),
                          tooltip: 'Remove Contact',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'pickContact',
            onPressed: _pickContact,
            tooltip: 'Pick from Contacts',
            child: const Icon(Icons.contacts),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'addContact',
            onPressed: _addContact,
            tooltip: 'Add Contact',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
} 