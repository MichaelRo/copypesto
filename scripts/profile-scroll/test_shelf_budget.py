# SPDX-License-Identifier: MIT
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


budget = load("check_shelf_budget", "check-shelf-budget.py")
history = load("perf_history", "perf_history.py")


def summary(p95=15, cards=3, overlay=None):
    renders = {"focusMove": {"ClipboardCard": {"mean": cards, "max": cards, "steps": 20},
                             "GridView": {"mean": 1, "max": 1, "steps": 20}}}
    if overlay is not None:
        renders["focusMove"]["OverlayRootView"] = {"mean": overlay, "max": 1, "steps": 20}
    return {"intervals": {"focusMove": {"count": 20, "p50": 12, "p95": p95, "max": 20}}, "renders": renders}


class BudgetTests(unittest.TestCase):
    def test_whenTheShelfIsWithinBudget_thenNothingFails(self):
        self.assertEqual(budget.check("benchArrowSteps", summary())[1], [])

    def test_whenAFocusMoveRerunsTheOverlay_thenItFails(self):
        failures = budget.check("benchArrowSteps", summary(overlay=1.0))[1]
        self.assertTrue(any("OverlayRootView" in f for f in failures))

    def test_whenEveryCardRerunsOnAFocusMove_thenItFails(self):
        failures = budget.check("benchArrowSteps", summary(cards=30))[1]
        self.assertTrue(any("ClipboardCard" in f for f in failures))

    def test_whenAStepIsFarOverItsTimeLimit_thenItFails(self):
        self.assertTrue(budget.check("benchArrowSteps", summary(p95=80))[1])

    def test_whenAViewNeverRan_thenItCountsAsZeroNotMissing(self):
        self.assertEqual(budget.value(summary(), "render", "focusMove/OverlayRootView", "mean"), 0.0)

    def test_whenASignpostWasNeverRecorded_thenItFailsRatherThanPasses(self):
        failures = budget.check("benchArrowSteps", {"intervals": {}, "renders": {}})[1]
        self.assertTrue(any("not recorded" in f for f in failures))


def entry(value, machine="M", key="switch.p50"):
    return {"date": "2026-11-12T00:00Z", "machine": machine, "values": {key: value}}


class HistoryTests(unittest.TestCase):
    def test_whenARunIsMuchWorseThanRecentRuns_thenItIsDrift(self):
        entries = [entry(v) for v in (50, 52, 49, 51, 50)]
        latest = entry(70)
        self.assertTrue(history.drift(entries + [latest], latest))

    def test_whenARunIsWithinNoise_thenItIsNotDrift(self):
        entries = [entry(v) for v in (50, 52, 49, 51, 50)]
        latest = entry(55)
        self.assertEqual(history.drift(entries + [latest], latest), [])

    def test_whenOtherMachinesRanTheSameThing_thenTheyAreNotCompared(self):
        entries = [entry(v, machine="slow Mac") for v in (200, 210, 190, 205)]
        latest = entry(50)
        self.assertEqual(history.drift(entries + [latest], latest), [])

    def test_whenThereAreFewerThanThreeEarlierRuns_thenThereIsNoBaselineYet(self):
        entries = [entry(10), entry(10)]
        latest = entry(90)
        self.assertEqual(history.drift(entries + [latest], latest), [])

    def test_whenTrendIsPrinted_thenEachMetricShowsItsRecentValuesInOrder(self):
        lines = history.trend([entry(50), entry(48), entry(46)], last=2)
        self.assertIn("48  46", lines[0])


if __name__ == "__main__":
    unittest.main()
