// models/rcs_message.dart
class RcsMessage {
  final String phone;
  final String brandName;
  final String title;
  final String description;
  final double? price;
  final String? validity;
  final List<RcsFeature> features;
  final List<RcsButton> buttons;
  final String? imageUrl;
  final bool showUnsubscribe;

  RcsMessage({
    required this.phone,
    required this.brandName,
    required this.title,
    required this.description,
    this.price,
    this.validity,
    this.features = const [],
    this.buttons = const [],
    this.imageUrl,
    this.showUnsubscribe = true,
  });
}

class RcsFeature {
  final String icon;
  final String text;

  RcsFeature(this.icon, this.text);
}

class RcsButton {
  final String icon;
  final String label;
  final String action; // 'url', 'call', 'sms', 'reply'
  final String value;

  RcsButton(this.icon, this.label, this.action, this.value);
}

// Common templates
class RcsTemplates {
  static RcsMessage jioRechargeTemplate(String phone) {
    return RcsMessage(
      phone: phone,
      brandName: "Your Business",
      title: "Special Recharge Offer",
      description: "Get best data and calling plans",
      price: 299.0,
      validity: "28 Days",
      features: [
        RcsFeature("⚡", "2 GB/Day High Speed Data"),
        RcsFeature("📶", "Unlimited 5G Data"),
        RcsFeature("📞", "Unlimited Calls"),
        RcsFeature("📺", "OTT Benefits"),
      ],
      buttons: [
        RcsButton("⚡", "View Plan", "url", "https://yourbusiness.com/plan1"),
        RcsButton(
          "💰",
          "Recharge Now",
          "url",
          "https://yourbusiness.com/recharge",
        ),
        RcsButton("📞", "Call Support", "call", "18001234567"),
      ],
      showUnsubscribe: true,
    );
  }

  static RcsMessage promotionalOffer(
    String phone,
    String product,
    double price,
  ) {
    return RcsMessage(
      phone: phone,
      brandName: "Your Store",
      title: "Limited Time Offer!",
      description: "Special discount on $product",
      price: price,
      validity: "Today Only",
      features: [
        RcsFeature("🔥", "Limited Stock"),
        RcsFeature("⏰", "24 Hours Only"),
        RcsFeature("🚚", "Free Delivery"),
        RcsFeature("🎁", "Extra Gift"),
      ],
      buttons: [
        RcsButton("🛒", "Buy Now", "url", "https://yourstore.com/buy"),
        RcsButton("📱", "View Details", "url", "https://yourstore.com/details"),
        RcsButton("📍", "Store Location", "url", "https://maps.google.com"),
      ],
    );
  }

  static RcsMessage appointmentReminder(
    String phone,
    DateTime date,
    String service,
  ) {
    return RcsMessage(
      phone: phone,
      brandName: "Service Provider",
      title: "Appointment Reminder",
      description: "Your $service appointment is scheduled",
      features: [
        RcsFeature("📅", "Date: ${date.day}/${date.month}/${date.year}"),
        RcsFeature(
          "⏰",
          "Time: ${date.hour}:${date.minute.toString().padLeft(2, '0')}",
        ),
        RcsFeature("📍", "Location: Our Main Branch"),
        RcsFeature("📞", "Contact: 18001234567"),
      ],
      buttons: [
        RcsButton("✅", "Confirm", "reply", "confirm"),
        RcsButton("🔄", "Reschedule", "url", "https://service.com/reschedule"),
        RcsButton("📞", "Call Us", "call", "18001234567"),
      ],
    );
  }
}
