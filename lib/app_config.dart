// Global app configuration flags derived at compile time
// Use: flutter run --dart-define=APP_ROLE=cashier

const String kAppRole =
    String.fromEnvironment('APP_ROLE', defaultValue: 'customer');

// Hardwire cashier app to a specific branch when building cashier flavor
// Replace with your Firestore branch document id
const String kHardwiredBranchId = 'WQ5I5XIFOSwII4LnxB55';
