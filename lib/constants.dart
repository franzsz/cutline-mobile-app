import 'package:flutter/material.dart';
import 'package:form_field_validator/form_field_validator.dart';

// Google Maps/Distance Matrix API key (set your key here)
const String googleMapsApiKey = '';

// OSM + OSRM (dev defaults; switch to a provider for production)
const String osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String osmAttribution = '© OpenStreetMap contributors';
const String osrmBaseUrl = 'https://router.project-osrm.org';

// Just for demo
const productDemoImg1 =
    "https://scontent.fmnl8-1.fna.fbcdn.net/v/t51.75761-15/489928180_18042244187615243_3566235424005464712_n.jpg?stp=dst-jpg_tt6&_nc_cat=106&ccb=1-7&_nc_sid=127cfc&_nc_ohc=QpisJXYZHZEQ7kNvwGTrLsN&_nc_oc=AdmYPmZ0nByPCAo7K4_tel3ZC0yVGbxB31pJc4xtkoybXe9wWM3PvLvgctmS-jT9VkY&_nc_zt=23&_nc_ht=scontent.fmnl8-1.fna&_nc_gid=EeUAPFGzV9EGhZcgKKeHEQ&oh=00_AfFoUlcv29mza3Mf35iPg79b5GI55uH5xQGmfEM7IR3TEA&oe=6816EE90";
const productDemoImg2 =
    "https://scontent.fmnl8-6.fna.fbcdn.net/v/t39.30808-6/471159498_122111343746683168_4568910750180715605_n.jpg?_nc_cat=104&ccb=1-7&_nc_sid=833d8c&_nc_ohc=4-Uq9dn1QjAQ7kNvwFGg310&_nc_oc=AdkTtMs30gp-lxFaMKXGBqQNnSWQHue6ATVehqvpcEQ5pg5coW9S3vgGFYHbIqouw58&_nc_zt=23&_nc_ht=scontent.fmnl8-6.fna&_nc_gid=K3ss6Eem1wXK5q7g3qjYmg&oh=00_AfFgsXe4FY6rLWOeE9uYQ6AHVgShtmyuHW85GkUaQ7nKxg&oe=6816F711";
const productDemoImg3 =
    "https://lh3.googleusercontent.com/p/AF1QipNvGkSn0QsGDH7n3qx35Kj5pyM5iw462aQuTfIP=s680-w680-h510-rw";
const productDemoImg4 =
    "https://lh3.googleusercontent.com/p/AF1QipNLrjy9l80g8kt3BvK2KW4L9yN_MLmXO95TV80u=s680-w680-h510-rw";
const productDemoImg5 =
    "https://lh3.googleusercontent.com/p/AF1QipPH960B4ImyG6hA1Id-THwOJuNu-fIzTjGY-i0j=s680-w680-h510-rw";
const productDemoImg6 =
    "https://lh3.googleusercontent.com/p/AF1QipONc1jBVx_oYXBdcocu6-5wjnaW4OU76jOFKG0L=s680-w680-h510-rw";

// End For demo

const grandisExtendedFont = "Grandis Extended";

// On color 80, 60.... those means opacity

const Color primaryColor = Color(0xFF7B61FF);

const MaterialColor primaryMaterialColor =
    MaterialColor(0xFF9581FF, <int, Color>{
  50: Color(0xFFEFECFF),
  100: Color(0xFFD7D0FF),
  200: Color(0xFFBDB0FF),
  300: Color(0xFFA390FF),
  400: Color(0xFF8F79FF),
  500: Color(0xFF7B61FF),
  600: Color(0xFF7359FF),
  700: Color(0xFF684FFF),
  800: Color(0xFF5E45FF),
  900: Color(0xFF6C56DD),
});

const Color blackColor = Color(0xFF16161E);
const Color blackColor80 = Color(0xFF45454B);
const Color blackColor60 = Color(0xFF737378);
const Color blackColor40 = Color(0xFFA2A2A5);
const Color blackColor20 = Color(0xFFD0D0D2);
const Color blackColor10 = Color(0xFFE8E8E9);
const Color blackColor5 = Color(0xFFF3F3F4);

const Color whiteColor = Colors.white;
const Color whileColor80 = Color(0xFFCCCCCC);
const Color whileColor60 = Color(0xFF999999);
const Color whileColor40 = Color(0xFF666666);
const Color whileColor20 = Color(0xFF333333);
const Color whileColor10 = Color(0xFF191919);
const Color whileColor5 = Color(0xFF0D0D0D);

const Color greyColor = Color(0xFFB8B5C3);
const Color lightGreyColor = Color(0xFFF8F8F9);
const Color darkGreyColor = Color(0xFF1C1C25);
// const Color greyColor80 = Color(0xFFC6C4CF);
// const Color greyColor60 = Color(0xFFD4D3DB);
// const Color greyColor40 = Color(0xFFE3E1E7);
// const Color greyColor20 = Color(0xFFF1F0F3);
// const Color greyColor10 = Color(0xFFF8F8F9);
// const Color greyColor5 = Color(0xFFFBFBFC);

const Color purpleColor = Color(0xFF7B61FF);
const Color successColor = Color(0xFF2ED573);
const Color warningColor = Color(0xFFFFBE21);
const Color errorColor = Color(0xFFEA5B5B);

const double defaultPadding = 16.0;
const double defaultBorderRadious = 12.0;
const Duration defaultDuration = Duration(milliseconds: 300);
final passwordValidator = MultiValidator([
  RequiredValidator(errorText: 'Password is required'),
  MinLengthValidator(8, errorText: 'password must be at least 8 digits long'),
  PatternValidator(r'(?=.*?[#?!@$%^&*-])',
      errorText: 'passwords must have at least one special character')
]);

final emaildValidator = MultiValidator([
  RequiredValidator(errorText: 'Email is required'),
  EmailValidator(errorText: "Enter a valid email address"),
]);

const pasNotMatchErrorText = "passwords do not match";
