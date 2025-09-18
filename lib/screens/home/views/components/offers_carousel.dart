import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shop/components/Banner/M/banner_m_style_1.dart';
import 'package:shop/components/Banner/M/banner_m_style_2.dart';
import 'package:shop/components/Banner/M/banner_m_style_3.dart';
import 'package:shop/components/Banner/M/banner_m_style_4.dart';
import 'package:shop/components/dot_indicators.dart';

import '../../../../constants.dart';

class OffersCarousel extends StatefulWidget {
  const OffersCarousel({
    super.key,
  });

  @override
  State<OffersCarousel> createState() => _OffersCarouselState();
}

class _OffersCarouselState extends State<OffersCarousel> {
  int _selectedIndex = 0;
  late PageController _pageController;
  late Timer _timer;

  void _goToNextPage() {
    if (_selectedIndex < offers.length - 1) {
      _selectedIndex++;
    } else {
      _selectedIndex = 0;
    }

    _pageController.animateToPage(
      _selectedIndex,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // Offers List
  late List<Widget> offers;

  @override
  void initState() {
    super.initState();

    _pageController = PageController(initialPage: 0);

    offers = [
      BannerMStyle1(
        text: "SUPREMO BARBER",
        press: _goToNextPage,
      ),
      BannerMStyle2(
        title: "SUPREMO BARBER",
        subtitle: "Your Style, Our Expertise.",
        press: _goToNextPage,
      ),
      BannerMStyle3(
        title: "SUPREMO BARBER",
        press: _goToNextPage,
      ),
      BannerMStyle4(
        title: "SUPREMO BARBER",
        subtitle: "Tradition Meets Trend.",
        press: _goToNextPage,
      ),
    ];

    // Auto-scroll the carousel every 6 seconds
    _timer = Timer.periodic(const Duration(seconds: 20), (Timer timer) {
      if (_selectedIndex < offers.length - 1) {
        _selectedIndex++;
      } else {
        _selectedIndex = 0;
      }

      _pageController.animateToPage(
        _selectedIndex,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.87,
      child: Stack(
        children: [
          // PageView builder
          PageView.builder(
            controller: _pageController,
            itemCount: offers.length,
            onPageChanged: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            itemBuilder: (context, index) => offers[index],
          ),

          // Bottom dot indicators
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(defaultPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  offers.length,
                  (index) {
                    return Padding(
                      padding: const EdgeInsets.only(left: defaultPadding / 4),
                      child: DotIndicator(
                        isActive: index == _selectedIndex,
                        activeColor: Colors.white70,
                        inActiveColor: Colors.white54,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
