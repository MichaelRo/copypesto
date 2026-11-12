# SPDX-License-Identifier: MIT
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shelf_report  # noqa: E402


class ShelfReportTests(unittest.TestCase):
    def write(self, lines):
        handle = tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False)
        handle.write("\n".join(lines) + "\n")
        handle.close()
        self.addCleanup(os.unlink, handle.name)
        return handle.name

    def test_whenIntervalsAreRecorded_thenPercentilesAreInMilliseconds(self):
        path = self.write([f"Shelf\tfocusMove\t0\t{ms * 1_000_000}" for ms in (4, 6, 8, 10, 40)])
        summary = shelf_report.summarise(*shelf_report.parse(path))
        row = summary["intervals"]["focusMove"]
        self.assertEqual((row["count"], row["p50"], row["max"]), (5, 8.0, 40.0))

    def test_whenRenderEventsAreRecorded_thenTheyAreAveragedPerInteraction(self):
        path = self.write([
            "Shelf\trenders(focusMove ClipboardCard=10 GridView=1)\t5\t5",
            "Shelf\trenders(focusMove ClipboardCard=20 GridView=1)\t6\t6",
        ])
        summary = shelf_report.summarise(*shelf_report.parse(path))
        card = summary["renders"]["focusMove"]["ClipboardCard"]
        self.assertEqual((card["mean"], card["max"], card["steps"]), (15.0, 20, 2))

    def test_whenScrollOffsetsAreRecorded_thenTravelIsTheirSpread(self):
        path = self.write(["Shelf\tshelfScroll(100)\t1\t1", "Shelf\tshelfScroll(-50)\t2\t2"])
        self.assertEqual(shelf_report.summarise(*shelf_report.parse(path))["scrollTravel"], 150)

    def test_whenVariantMarkersAreRecorded_thenIntervalsAreSplitPerVariant(self):
        path = self.write([
            "Shelf\tvariant(A)\t1\t1",
            f"Shelf\tcollectionSwitch\t0\t{40 * 1_000_000}",
            "Shelf\tvariant(B)\t2\t2",
            f"Shelf\tcollectionSwitch\t0\t{20 * 1_000_000}",
        ])
        intervals = shelf_report.summarise(*shelf_report.parse(path))["intervals"]
        self.assertEqual(intervals["collectionSwitch@A"]["p50"], 40.0)
        self.assertEqual(intervals["collectionSwitch@B"]["p50"], 20.0)

    def test_whenRunAsAScript_thenItPrintsATable(self):
        path = self.write([f"Shelf\tcollectionSwitch\t0\t{12 * 1_000_000}"])
        out = subprocess.run([sys.executable, os.path.join(HERE, "shelf_report.py"), path], capture_output=True, text=True)
        self.assertIn("collectionSwitch", out.stdout)


if __name__ == "__main__":
    unittest.main()
