import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/helpline_screen.dart';
import 'screens/safety_tips_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/media_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SheShield',
      theme: ThemeData(
        primarySwatch: Colors.pink,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.pink,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.pink,
            foregroundColor: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      home: const MainTabController(),
    );
  }
}

class MainTabController extends StatefulWidget {
  const MainTabController({Key? key}) : super(key: key);

  @override
  State<MainTabController> createState() => _MainTabControllerState();
}

class _MainTabControllerState extends State<MainTabController> {
  int _currentIndex = 0;
  final List<Widget> _screens = const [
    HomeScreen(),
    ContactsScreen(),
    HelplineScreen(),
    SafetyTipsScreen(),
    MediaScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: Colors.pink,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              activeIcon: Icon(Icons.home_rounded, color: Colors.pink),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.contacts_rounded),
              activeIcon: Icon(Icons.contacts_rounded, color: Colors.pink),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.local_phone_rounded),
              activeIcon: Icon(Icons.local_phone_rounded, color: Colors.pink),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.tips_and_updates_rounded),
              activeIcon: Icon(Icons.tips_and_updates_rounded, color: Colors.pink),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.photo_library_rounded),
              activeIcon: Icon(Icons.photo_library_rounded, color: Colors.pink),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              activeIcon: Icon(Icons.settings_rounded, color: Colors.pink),
              label: '',
            ),
          ],
        ),
      ),
    );
  }
} 