import 'package:flutter/material.dart';
import 'package:shop/app_config.dart';
import 'package:shop/entry_point.dart';
import 'package:shop/entry_point2.dart';

import 'screen_export.dart';

Route<dynamic> generateRoute(RouteSettings settings) {
  switch (settings.name) {
    case onbordingScreenRoute:
      // Hide onboarding: route to SplashScreen instead
      return MaterialPageRoute(
        builder: (_) => const SplashScreen(),
      );
    case splashScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const SplashScreen(),
      );

    case LoginEmployeeScreenRoute:
      if (kAppRole.toLowerCase() != 'cashier' &&
          kAppRole.toLowerCase() != 'barber') {
        // Hide onboarding: show SplashScreen fallback
        return MaterialPageRoute(
          builder: (context) => const SplashScreen(),
        );
      }
      return MaterialPageRoute(
        builder: (context) => const LoginEmployeeScreen(),
      );
    case logInScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      );
    case signUpScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const SignUpScreen(),
      );
    case signUpEmployeeScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const SignUpEmployeeScreen(),
      );

    case passwordRecoveryScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const PasswordRecoveryScreen(),
      );

    case verifyCodeScreenRoute:
      final args = settings.arguments as Map<String, dynamic>;
      return MaterialPageRoute(
        builder: (_) => VerifyCodeScreen(
          email: args['email'],
          uid: args['uid'],
        ),
      );

    case employeeHomeScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const AttendanceScreen(),
      );
    case employeeQueueScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const QueueManagementPage(),
      );
    case cashierQueueScreenRoute:
      if (kAppRole.toLowerCase() != 'cashier') {
        return MaterialPageRoute(
          builder: (context) => const OnBordingScreen(),
        );
      }
      final branchId = settings.arguments as String;
      return MaterialPageRoute(
        builder: (context) => CashierQueueScreen(branchId: branchId),
      );
    case employeeNotificationScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const NotificationPage(),
      );
    case employeeProfileScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const ProfileSchedulePage(),
      );
    case employeeHistoryScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const ServiceLogPage(),
      );
    case queueMapTrackingRoute:
      final docId = settings.arguments as String;
      return MaterialPageRoute(
        builder: (context) => QueueMapTrackingScreen(
          queueDocId: docId,
          onQueueCancelled: () {
            // Handle cancellation navigation fallback if needed
            Navigator.of(context).pop(); // or any appropriate fallback
          },
        ),
      );

    case productDetailsScreenRoute:
      return MaterialPageRoute(
        builder: (context) {
          bool isProductAvailable = settings.arguments as bool? ?? true;
          return ProductDetailsScreen(isProductAvailable: isProductAvailable);
        },
      );
    case productReviewsScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const ProductReviewsScreen(),
      );

    case homeScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const HomeScreen(),
      );

    case discoverScreenRoute:
      return MaterialPageRoute(
        builder: (context) => DiscoverScreen(
          onQueueConfirmed: (String docId) {
            // optional: handle queue navigation or logic if needed here
          },
        ),
      );

    case onlinePaymentRoute:
      final docId = settings.arguments as String;
      return MaterialPageRoute(
        builder: (_) => OnlinePaymentScreen(queueDocId: docId),
      );

    case onSaleScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const OnSaleScreen(),
      );
    case kidsScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const KidsScreen(),
      );
    case searchScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const SearchScreen(),
      );

    case transactionHistoryScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const TransactionHistoryPage(),
      );
    case entryPointScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const EntryPoint(),
      );
    case entryPoint2ScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const EntryPoint2(),
      );
    case profileScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const ProfileScreen(),
      );

    case userInfoScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const UserInfoScreen(),
      );

    case notificationsScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const NotificationsScreen(),
      );
    case noNotificationScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const NoNotificationScreen(),
      );
    case enableNotificationScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const EnableNotificationScreen(),
      );
    case notificationOptionsScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const NotificationOptionsScreen(),
      );

    case addressesScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const AddressesScreen(),
      );

    case ordersScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const OrdersScreen(),
      );

    case preferencesScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const PreferencesScreen(),
      );

    case emptyWalletScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const EmptyWalletScreen(),
      );
    case walletScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const WalletScreen(),
      );
    case cartScreenRoute:
      return MaterialPageRoute(
        builder: (context) => const CartScreen(),
      );

    default:
      return MaterialPageRoute(
        // Fallback: hide onboarding, go to SplashScreen
        builder: (context) => const SplashScreen(),
      );
  }
}
