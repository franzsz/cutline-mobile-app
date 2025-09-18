import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shop/theme/theme_provider.dart';

class ThemeToggle extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final bool showIcon;
  final bool showSubtitle;
  final EdgeInsetsGeometry? padding;

  const ThemeToggle({
    super.key,
    this.title,
    this.subtitle,
    this.showIcon = true,
    this.showSubtitle = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return ListTile(
          contentPadding: padding,
          leading: showIcon
              ? Icon(
                  themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  color: Theme.of(context).iconTheme.color,
                )
              : null,
          title: Text(
            title ?? "Dark Mode",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: showSubtitle
              ? Text(
                  subtitle ??
                      (themeProvider.isDarkMode
                          ? "Dark theme enabled"
                          : "Light theme enabled"),
                  style: TextStyle(
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.7),
                  ),
                )
              : null,
          trailing: Switch(
            value: themeProvider.isDarkMode,
            onChanged: (value) async {
              await themeProvider.setDarkMode(value);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value ? 'Dark mode enabled' : 'Light mode enabled',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            activeColor: Theme.of(context).primaryColor,
          ),
        );
      },
    );
  }
}

class CompactThemeToggle extends StatelessWidget {
  final double? size;
  final Color? activeColor;
  final Color? inactiveColor;

  const CompactThemeToggle({
    super.key,
    this.size = 24,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return IconButton(
          icon: Icon(
            themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            size: size,
            color: themeProvider.isDarkMode
                ? (activeColor ?? Theme.of(context).primaryColor)
                : (inactiveColor ?? Theme.of(context).iconTheme.color),
          ),
          onPressed: () async {
            await themeProvider.toggleTheme();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    themeProvider.isDarkMode
                        ? 'Dark mode enabled'
                        : 'Light mode enabled',
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          },
        );
      },
    );
  }
}

