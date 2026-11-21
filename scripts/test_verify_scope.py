# SPDX-License-Identifier: MIT
import importlib.util
import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("verify_scope", os.path.join(HERE, "verify_scope.py"))
VERIFY_SCOPE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY_SCOPE)


class VerifyScopeTests(unittest.TestCase):
    def test_whenNoFilesChanged_thenRunsCoreAndSkipsMobile(self):
        plan = VERIFY_SCOPE.compute_scope([])
        self.assertTrue(plan["run_core"])
        self.assertIsNone(plan["core_filter"])
        self.assertFalse(plan["run_hosted"])
        self.assertFalse(plan["run_ui"])
        self.assertFalse(plan["run_snapshots"])
        self.assertFalse(plan["run_mobile"])
        self.assertEqual(plan["only_testing"], [])

    def test_whenCoreFilesChanged_thenRunsFilteredCoreAndSkipsMobile(self):
        plan = VERIFY_SCOPE.compute_scope([
            "Sources/Core/Storage/HistoryIndex.swift",
            "Tests/PestoCoreTests/HistoryIndexTests.swift",
        ])
        self.assertTrue(plan["run_core"])
        self.assertEqual(plan["core_filter"], "HistoryIndexTests")
        self.assertFalse(plan["run_hosted"])
        self.assertFalse(plan["run_ui"])
        self.assertFalse(plan["run_snapshots"])
        self.assertFalse(plan["run_mobile"])

    def test_whenMacFeaturesChanged_thenRunsMacHostedAndSkipsMobile(self):
        plan = VERIFY_SCOPE.compute_scope(["Sources/Features/Grid/ClipboardCard.swift"])
        self.assertFalse(plan["run_core"])
        self.assertTrue(plan["run_hosted"])
        self.assertTrue(plan["run_ui"])
        self.assertTrue(plan["run_snapshots"])
        self.assertFalse(plan["run_mobile"])
        self.assertIn("PestoUITests/OverlayFlowTests", plan["only_testing"])
        self.assertIn("PestoSnapshotTests", plan["only_testing"])

    def test_whenMobileFilesChanged_thenRunsMobileTests(self):
        for path in [
            "Sources/Mobile/PhoneLibraryView.swift",
            "Sources/MobileShare/ShareViewController.swift",
            "Sources/MobileAutoFill/AutoFillViewController.swift",
            "Sources/MobileKeyboard/KeyboardModel.swift",
            "Sources/MobileShared/CardFace.swift",
            "Sources/MobileWidget/CopyClipIntent.swift",
        ]:
            with self.subTest(path=path):
                plan = VERIFY_SCOPE.compute_scope([path])
                self.assertTrue(plan["run_mobile"], path)
                self.assertFalse(plan["run_core"], path)
                self.assertFalse(plan["run_hosted"], path)
                self.assertFalse(plan["run_ui"], path)
                self.assertFalse(plan["run_snapshots"], path)
                self.assertEqual(plan["only_testing"], [], path)

    def test_whenWidgetFilesChanged_thenRunsMobileTests(self):
        plan = VERIFY_SCOPE.compute_scope(["Sources/Widget/RecentClipsView.swift"])
        self.assertTrue(plan["run_mobile"])
        self.assertFalse(plan["run_core"])
        self.assertFalse(plan["run_hosted"])
        self.assertFalse(plan["run_ui"])
        self.assertFalse(plan["run_snapshots"])

    def test_whenMobileTestsChanged_thenRunsMobileTests(self):
        for path in [
            "Tests/PestoMobileTests/CardFaceTests.swift",
            "Tests/PestoMobileUITests/LibrarySmokeUITests.swift",
        ]:
            with self.subTest(path=path):
                plan = VERIFY_SCOPE.compute_scope([path])
                self.assertTrue(plan["run_mobile"], path)
                self.assertFalse(plan["run_core"], path)
                self.assertFalse(plan["run_hosted"], path)

    def test_whenSharedFilesChanged_thenRunsMacAndMobileTests(self):
        plan = VERIFY_SCOPE.compute_scope(["Sources/Shared/Extensions/Color+Hex.swift"])
        self.assertFalse(plan["run_core"])
        self.assertTrue(plan["run_hosted"])
        self.assertTrue(plan["run_ui"])
        self.assertTrue(plan["run_snapshots"])
        self.assertTrue(plan["run_mobile"])
        self.assertIn("PestoUITests/OverlayFlowTests", plan["only_testing"])

    def test_whenCoreAndMobileFilesChanged_thenRunsFilteredCoreAndMobileTests(self):
        plan = VERIFY_SCOPE.compute_scope([
            "Sources/Core/Sync/SyncKey.swift",
            "Sources/Mobile/SyncSettingsView.swift",
        ])
        self.assertTrue(plan["run_core"])
        self.assertEqual(plan["core_filter"], "SyncKeyTests")
        self.assertFalse(plan["run_hosted"])
        self.assertTrue(plan["run_mobile"])

    def test_whenBuildConfigChanged_thenRunsAllTiersIncludingMobile(self):
        for path in ["Pesto.yml", "Sources/MobileKeyboard/PestoKeyboard.entitlements"]:
            with self.subTest(path=path):
                plan = VERIFY_SCOPE.compute_scope([path])
                self.assertTrue(plan["run_core"])
                self.assertTrue(plan["run_hosted"])
                self.assertTrue(plan["run_ui"])
                self.assertTrue(plan["run_mobile"])

    def test_whenDocsOnlyChanged_thenFallsBackToCoreAndSkipsMobile(self):
        plan = VERIFY_SCOPE.compute_scope(["docs/architecture.md"])
        self.assertTrue(plan["run_core"])
        self.assertIsNone(plan["core_filter"])
        self.assertFalse(plan["run_hosted"])
        self.assertFalse(plan["run_mobile"])

    def test_whenInvokedAsCLI_thenPrintsRunMobileInJSON(self):
        proc = subprocess.run(
            [sys.executable, os.path.join(HERE, "verify_scope.py"), "--files", "Sources/Mobile/LibraryView.swift"],
            capture_output=True,
            text=True,
            check=True,
        )
        plan = json.loads(proc.stdout)
        self.assertTrue(plan["run_mobile"])
        self.assertFalse(plan["run_core"])

    def test_whenVerifyScriptChecked_thenValidSyntaxAndRoutesMobileToCITests(self):
        verify_sh = os.path.join(HERE, "verify.sh")
        subprocess.run(["bash", "-n", verify_sh], check=True)
        with open(verify_sh, encoding="utf-8") as f:
            text = f.read()
        self.assertIn('get("run_mobile")', text)
        self.assertIn("step_mobile --no-ui", text)
        self.assertIn('scheme="PestoMobileCITests"', text)


if __name__ == "__main__":
    unittest.main()
