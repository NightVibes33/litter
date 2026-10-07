import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
IOS = ROOT / "apps/ios/Sources/Litter"

class StoreKitConfigurationTests(unittest.TestCase):
    def test_runtime_ids_match_local_products(self):
        config = json.loads((IOS / "Resources/TipJarProducts.storekit").read_text())
        products = {p["productID"]: p for p in config["products"]}
        runtime = (IOS / "Models/ProAccessStore.swift").read_text() + (IOS / "Models/TipJarStore.swift").read_text()
        ids = set(re.findall(r'"(com\.nightvibes\.alleycat\.(?:pro|tip\.\d+))"', runtime))
        self.assertEqual(ids, set(products))
        self.assertEqual(len(ids), 5)
        self.assertTrue(all(p["type"] == "NonConsumable" for p in products.values()))
        self.assertNotIn("com.sigkitten.litter", runtime)

    def test_store_lane_has_no_auto_unlock_stub(self):
        source = (IOS / "Models/ProAccessStore.swift").read_text()
        self.assertNotIn("#if LITTER_APP_STORE_SAFE", source)
        self.assertNotIn("#if !LITTER_APP_STORE_SAFE", source)
        self.assertIn("Transaction.currentEntitlements", source)
        self.assertIn("transaction.revocationDate == nil", source)
        self.assertIn("transaction.productType == .nonConsumable", source)
        self.assertIn("AppDistributionCapabilities.unlocksProForSideload", source)

    def test_unavailable_product_cannot_be_purchased(self):
        source = (IOS / "Views/ProPaywallView.swift").read_text()
        self.assertIn(".disabled(store.product == nil ||", source)
