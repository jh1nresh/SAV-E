"""Tests for coordinate and address evidence in incremental Taipei shop recovery."""
import gzip
import hashlib
import json
from pathlib import Path
import runpy
from tempfile import TemporaryDirectory
import unittest

HERE = Path(__file__).resolve().parents[1]
code = runpy.run_path(str(HERE / "scripts/build-taipei-address-frontages.py"))


class SourceRules(unittest.TestCase):
    def test_separate_official_address_not_shop_label(self):
        valid = {"addr:city":"臺北市", "source":"臺北市政府", "addr:TW:dataset":"155472",
                 "addr:street":"興華路", "addr:district":"南港區", "addr:housenumber":"28號"}
        self.assertTrue(code["municipal_plate"](valid))
        for replacement in [{"shop":"cafe"}, {"source":"unknown"}, {"addr:city":"新北市"}, {"addr:district":""}]:
            self.assertFalse(code["municipal_plate"]({**valid, **replacement}))

    def test_customer_entrance_must_be_ground_and_public(self):
        tags = {"door":"sliding", "level":"0", "entrance":"shop", "access":"customers"}
        self.assertTrue(code["customer_entrance"](tags))
        for replacement in [{"entrance":"main"}, {"level":"1"}, {"access":"private"}, {"layer":"1"},
                            {"door":"emergency"}, {"indoor":"yes"}]:
            self.assertFalse(code["customer_entrance"]({**tags, **replacement}))

    def test_two_buildings_share_node(self):
        entrance = {"type":"node", "id":149, "lon":121.4, "lat":25.1, "tags":{"entrance":"shop"}}
        ways = [{"type":"way", "id":i, "tags":{"building":"yes"}, "nodes":[i,149,i]} for i in [12,14]]
        with TemporaryDirectory() as root:
            path = Path(root) / "extract.gz"
            raw = json.dumps({"elements":[*ways,entrance]}).encode()
            path.write_bytes(gzip.compress(raw))
            checksum = hashlib.sha256(raw).hexdigest()
            tags, plates, portals = code["raw_evidence"](path, {"way/12"}, checksum, lambda *args: None)
            self.assertEqual(set(tags), {"way/12"})
            self.assertEqual(dict(portals), {})
            with self.assertRaisesRegex(ValueError, "differs"):
                code["raw_evidence"](path, set(), "different", lambda *args: None)

    def test_real_accepted_rows(self):
        text = (HERE / "taipei-address-frontages.js").read_text()
        rows = {r["id"]:r for r in json.loads(text.split("=",1)[1].strip().removesuffix(";"))}
        cafe = rows["poi/node/8441425922"]
        self.assertEqual((cafe["addressNode"], cafe["addressDataset"], cafe["street"]),
                         ("node/10830149247","155472","興華路"))
        self.assertNotIn("entranceId", cafe)
        # Both storefront identities share 景隆街36巷2號. The real door's
        # tenant cannot be distinguished from the public source evidence.
        self.assertNotIn("poi/node/2866653852", rows)
        self.assertNotIn("poi/node/9965180059", rows)
        for r in rows.values():
            self.assertGreater(r["surveyTop"] - r["groundZ"], 2.29)
            self.assertIsNotNone(r["surveyBase"])
            self.assertRegex(r["pack"], r"^p\d+_\d+$")
            self.assertEqual(len(r["wall"]),2)
            self.assertTrue(r["groundEvidence"] in {"single-storey-footprint","tagged-ground"})


if __name__ == "__main__":
    unittest.main()
