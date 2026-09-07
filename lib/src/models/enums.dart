/// Role selected at registration. Mirrors `UserType` in the web API.
enum UserRole {
  customer,
  worker,
  admin;

  static UserRole from(String? v) {
    switch (v) {
      case 'worker':
        return UserRole.worker;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.customer;
    }
  }

  String get wire => name;
}

/// Verification state of a worker's identity/certificate docs.
enum VerificationStatus { pending, verified, rejected }

/// Subscription plans offered to contractors.
enum SubscriptionPlan { freeTrial, basic, pro, gold, perLead, commission }