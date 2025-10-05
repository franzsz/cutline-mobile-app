import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shop/components/theme_toggle.dart';
import 'package:shop/constants.dart';
import 'package:shop/route/screen_export.dart';

class EntryPoint extends StatefulWidget {
  const EntryPoint({super.key});

  @override
  State<EntryPoint> createState() => _EntryPointState();
}

class _EntryPointState extends State<EntryPoint> {
  int _currentIndex = 0;
  String? _queueDocId; // used to determine if user is queueing

  // Callback when queue is confirmed in DiscoverScreen
  void _enterQueue(String docId) {
    setState(() {
      _queueDocId = docId;
      _currentIndex = 1; // Switch to Queue tab
    });
  }

  // Callback when queue is cancelled in QueueMapTrackingScreen
  void _leaveQueue() {
    setState(() {
      _queueDocId = null;
      _currentIndex = 1; // Back to Discover tab
    });
  }

  List<Widget> get _pages => [
        const HomeScreen(),
        _queueDocId == null
            ? DiscoverScreen(onQueueConfirmed: _enterQueue)
            : QueueMapTrackingScreen(
                queueDocId: _queueDocId!,
                onQueueCancelled: _leaveQueue,
              ),
        const TransactionHistoryPage(),
        const ProfileScreen(),
      ];

  SvgPicture svgIcon(String src, {Color? color}) {
    return SvgPicture.asset(
      src,
      height: 24,
      colorFilter: ColorFilter.mode(
        color ?? Theme.of(context).iconTheme.color!,
        BlendMode.srcIn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: const SizedBox(),
        leadingWidth: 0,
        centerTitle: false,
        title: Image.asset(
          "assets/images/logo.jpg",
          height: 60,
          width: 100,
          fit: BoxFit.contain,
        ),
        actions: [
          const CompactThemeToggle(),
        ],
      ),
      body: PageTransitionSwitcher(
        duration: defaultDuration,
        transitionBuilder: (child, animation, secondAnimation) {
          return FadeThroughTransition(
            animation: animation,
            secondaryAnimation: secondAnimation,
            child: child,
          );
        },
        child: _pages[_currentIndex],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(top: defaultPadding / 2),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 12,
          selectedItemColor: Theme.of(context).brightness == Brightness.light
              ? const Color.fromARGB(255, 0, 0, 0)
              : const Color(0xFFD4AF37),
          unselectedItemColor: Theme.of(context).brightness == Brightness.light
              ? Colors.grey[600]
              : Colors.white60,
          items: [
            BottomNavigationBarItem(
              icon: svgIcon("assets/icons/home-2-svgrepo-com (2).svg"),
              activeIcon: svgIcon("assets/icons/home-2-svgrepo-com (2).svg",
                  color: Theme.of(context).brightness == Brightness.light
                      ? const Color.fromARGB(255, 0, 0, 0)
                      : const Color(0xFFD4AF37)),
              label: "Home",
            ),
            BottomNavigationBarItem(
              icon:
                  svgIcon("assets/icons/queue-up-wait-line-up-svgrepo-com.svg"),
              activeIcon: svgIcon(
                  "assets/icons/queue-up-wait-line-up-svgrepo-com.svg",
                  color: Theme.of(context).brightness == Brightness.light
                      ? const Color.fromARGB(255, 0, 0, 0)
                      : const Color(0xFFD4AF37)),
              label: "Queue",
            ),
            BottomNavigationBarItem(
              icon: svgIcon(
                  "assets/icons/history-log-manuscript-svgrepo-com.svg"),
              activeIcon: svgIcon(
                  "assets/icons/history-log-manuscript-svgrepo-com.svg",
                  color: Theme.of(context).brightness == Brightness.light
                      ? const Color.fromARGB(255, 0, 0, 0)
                      : const Color(0xFFD4AF37)),
              label: "Transaction History",
            ),
            BottomNavigationBarItem(
              icon: svgIcon("assets/icons/Profile.svg"),
              activeIcon: svgIcon("assets/icons/Profile.svg",
                  color: Theme.of(context).brightness == Brightness.light
                      ? const Color.fromARGB(255, 0, 0, 0)
                      : const Color(0xFFD4AF37)),
              label: "Profile",
            ),
          ],
        ),
      ),
    );
  }
}
