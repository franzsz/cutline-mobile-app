import 'package:flutter/material.dart';
import 'package:shop/screens/auth/views/components/sign_up_cashier_form.dart';
import 'package:shop/route/route_constants.dart';

import '../../../constants.dart';

class SignUpEmployeeScreen extends StatefulWidget {
  const SignUpEmployeeScreen({super.key});

  @override
  State<SignUpEmployeeScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpEmployeeScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // Center vertically
            crossAxisAlignment:
                CrossAxisAlignment.center, // Center horizontally
            children: [
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
                      "Create a Employee Account",
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: defaultPadding / 2),
                    const Text(
                      "Please enter your valid data in order to create an account.",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: defaultPadding),
                    SignUpCashierForm(formKey: _formKey),
                    const SizedBox(height: defaultPadding * 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Do you have an account?"),
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(
                                context, LoginEmployeeScreenRoute);
                          },
                          child: const Text("Log in"),
                        )
                      ],
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
