"""Classification at the join of measured storefronts and frozen OSM tags."""

from pathlib import Path
import runpy
import unittest


chain = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/build-taipei-convenience-art.py"))["chain"]


class TaipeiConvenienceArt(unittest.TestCase):
    def test_brand_requires_both_explicit_tags_and_the_right_shop_use(self):
        matching = {"shop": "convenience", "brand": "7-Eleven", "brand:wikidata": "Q259340"}
        self.assertEqual(chain(matching, "7-Eleven"), "seven")
        self.assertIsNone(chain(matching | {"shop": "supermarket"}, "7-Eleven"))
        self.assertIsNone(chain(matching | {"brand": "全家便利商店"}, "7-Eleven"))
        self.assertIsNone(chain(matching | {"brand:wikidata": ""}, "7-Eleven"))
        self.assertIsNone(chain({"shop": "convenience", "name": "7-Eleven"}, "7-Eleven"))

    def test_exact_parcel_service_name_must_agree_and_cannot_override_tags(self):
        matching = {"shop": "convenience", "name": "蝦皮店到店"}
        self.assertEqual(chain(matching, "蝦皮店到店"), "shopee")
        self.assertIsNone(chain(matching, "蝦皮店到店附近商行"))
        self.assertIsNone(chain(matching | {"brand": "無關的便利商店"}, "蝦皮店到店"))
        self.assertIsNone(chain(matching | {"brand:wikidata": "Q259340"}, "蝦皮店到店"))
        self.assertIsNone(chain(matching | {"name": "蝦皮店到店附近商行"}, "蝦皮店到店"))


if __name__ == "__main__":
    unittest.main()
