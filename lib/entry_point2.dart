import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shop/constants.dart';
import 'package:shop/route/screen_export.dart';

class EntryPoint2 extends StatefulWidget {
  const EntryPoint2({super.key});

  @override
  State<EntryPoint2> createState() => _EntryPointState();
}

class _EntryPointState extends State<EntryPoint2> {
  final List _pages = const [
    CashierQueueScreen(
      branchId: '1',
    ),
    QueueManagementPage(),
    ServiceLogPage(),
    ProfileSchedulePage(),
  ];
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    SvgPicture svgIcon(String src, {Color? color}) {
      return SvgPicture.asset(
        src,
        height: 24,
        colorFilter: ColorFilter.mode(
            color ??
                Theme.of(context).iconTheme.color!.withOpacity(
                    Theme.of(context).brightness == Brightness.dark ? 0.3 : 1),
            BlendMode.srcIn),
      );
    }

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
      ),
      // body: _pages[_currentIndex],
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
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF101015),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            if (index != _currentIndex) {
              setState(() {
                _currentIndex = index;
              });
            }
          },
          backgroundColor: Theme.of(context).brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF101015),
          type: BottomNavigationBarType.fixed,
          // selectedLabelStyle: TextStyle(color: primaryColor),
          selectedFontSize: 12,
          selectedItemColor: const Color.fromARGB(255, 0, 0, 0),
          unselectedItemColor: Colors.transparent,
          items: [
            BottomNavigationBarItem(
              icon: svgIcon("assets/icons/attendance-svgrepo-com.svg"),
              activeIcon: svgIcon("assets/icons/attendance-svgrepo-com.svg",
                  color: const Color.fromARGB(255, 0, 0, 0)),
              label: "Attendance",
            ),
            BottomNavigationBarItem(
              icon:
                  svgIcon("assets/icons/queue-up-wait-line-up-svgrepo-com.svg"),
              activeIcon: svgIcon(
                  "assets/icons/queue-up-wait-line-up-svgrepo-com.svg",
                  color: const Color.fromARGB(255, 0, 0, 0)),
              label: "Queue",
            ),
            BottomNavigationBarItem(
              icon: svgIcon(
                  "assets/icons/history-log-manuscript-svgrepo-com.svg"),
              activeIcon: svgIcon(
                  "assets/icons/history-log-manuscript-svgrepo-com.svg",
                  color: const Color.fromARGB(255, 0, 0, 0)),
              label: "History",
            ),
            BottomNavigationBarItem(
              icon: svgIcon("assets/icons/Profile.svg"),
              activeIcon: svgIcon("assets/icons/Profile.svg",
                  color: const Color.fromARGB(255, 0, 0, 0)),
              label: "Profile",
            ),
          ],
        ),
      ),
    );
  }
}
