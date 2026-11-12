import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Einmalkauf "Pro" (schaltet eigene Feeds frei).
class ProService extends ChangeNotifier {
  bool _purchased = false;
  bool storeAvailable = false;
  ProductDetails? product;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  SharedPreferences? _prefs;

  bool get isPro => kUnlockPro || _purchased;
  String get priceLabel => product?.price ?? '';

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    _purchased = prefs.getBool('pro') ?? false;
    try {
      final iap = InAppPurchase.instance;
      storeAvailable = await iap.isAvailable();
      if (!storeAvailable) return;
      _sub = iap.purchaseStream.listen(_onPurchases, onError: (_) {});
      final response = await iap.queryProductDetails({kProProductId});
      if (response.productDetails.isNotEmpty) {
        product = response.productDetails.first;
      }
      await iap.restorePurchases();
    } catch (_) {
      storeAvailable = false;
    }
    notifyListeners();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID == kProProductId &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored)) {
        _purchased = true;
        await _prefs?.setBool('pro', true);
        notifyListeners();
      }
      if (p.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }
  }

  /// Startet den Kauf. `false`, wenn der Store oder das Produkt fehlt.
  Future<bool> buy() async {
    final prod = product;
    if (!storeAvailable || prod == null) return false;
    try {
      return await InAppPurchase.instance
          .buyNonConsumable(purchaseParam: PurchaseParam(productDetails: prod));
    } catch (_) {
      return false;
    }
  }

  Future<void> restore() async {
    if (!storeAvailable) return;
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
