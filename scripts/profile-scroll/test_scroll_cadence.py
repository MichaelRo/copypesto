# SPDX-License-Identifier: MIT
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("scroll_cadence", os.path.join(HERE, "scroll_cadence.py"))
cadence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cadence)


class CadenceTests(unittest.TestCase):
    def tsv(self, millis):
        handle = tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False)
        for ms in millis:
            handle.write(f"Shelf\tscrollFrame()\t{int(ms * 1e6)}\t{int(ms * 1e6)}\n")
        handle.close()
        self.addCleanup(os.unlink, handle.name)
        return handle.name

    def test_whenFramesComeEvenly_thenNoGapIsLate(self):
        values, frames = cadence.gaps(self.tsv([i * 8 for i in range(50)]))
        row = cadence.summarise(values, frames)
        self.assertEqual((row["frames"], row["over17"], row["over33"]), (50, 0.0, 0.0))

    def test_whenAFrameIsLate_thenItCountsOver33(self):
        values, frames = cadence.gaps(self.tsv([0, 8, 16, 24, 74, 82]))
        self.assertGreater(cadence.summarise(values, frames)["over33"], 0)

    def test_whenSweepsArePausedBetween_thenThePauseIsNotAGap(self):
        values, _ = cadence.gaps(self.tsv([0, 8, 16, 2_000, 2_008]))
        self.assertEqual(sorted(values), [8.0, 8.0, 8.0])


if __name__ == "__main__":
    unittest.main()
