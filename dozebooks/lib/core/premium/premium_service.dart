import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Simple premium gate. Wire your product ID in the store consoles.
class PremiumService extends ChangeNotifier {
  static const String kProductId = 'dozebooks_premium_unlock';
  bool _isPremium = false;
  bool get isPremium => _isPremium;

  Future<void> load() async {
    // TODO: persist purchase locally; for MVP, default false.
    // You can store a flag in shared_preferences once the purchase is verified.
    _isPremium = false;
    notifyListeners();
  }

  Future<void> buy() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) return;
    final response = await InAppPurchase.instance.queryProductDetails({kProductId});
    if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) return;
    final purchaseParam = PurchaseParam(productDetails: response.productDetails.first);
    InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);
  }

  void markPremium(bool value) {
    _isPremium = value;
    notifyListeners();
  }
}
