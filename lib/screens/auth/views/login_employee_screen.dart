import 'package:flutter/material.dart';
import 'package:shop/constants.dart';
import 'package:shop/route/route_constants.dart';
import 'package:shop/screens/auth/views/components/login_form_barber.dart';

class LoginEmployeeScreen extends StatefulWidget {
  const LoginEmployeeScreen({super.key});

  @override
  State<LoginEmployeeScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginEmployeeScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    Navigator.pushNamed(context, onbordingScreenRoute);
                  },
                ),
              ),
              Image.asset(
                "assets/images/logo.jpg",
                fit: BoxFit.cover,
              ),
              Padding(
                padding: const EdgeInsets.all(defaultPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "Welcome, Cashier!",
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: defaultPadding),
                    LogInFormBarber(formKey: _formKey),
                    Align(
                      child: TextButton(
                        child: const Text("Forgot password"),
                        onPressed: () {
                          Navigator.pushNamed(
                              context, passwordRecoveryScreenRoute);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
