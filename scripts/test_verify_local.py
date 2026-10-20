import json
import contextlib
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import verify_local
from verify_local import ROOT, check_contracts


class ContractRegressionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for name in ['copado', 'force-app', 'test-data']:
            shutil.copytree(ROOT / name, self.root / name, ignore=shutil.ignore_patterns('run.env', 'output.txt', '*.log'))

    def tearDown(self):
        self.tmp.cleanup()

    def test_valid(self):
        check_contracts(self.root)

    def test_stale_script_rejected(self):
        with (self.root / 'copado/functions/Run_CodeAnalyzer_QIF.sh').open('a') as f:
            f.write('\n# drift\n')
        with self.assertRaisesRegex(ValueError, 'script is stale'):
            check_contracts(self.root)

    def test_parameter_drift_rejected(self):
        for suffix in ['template', 'metadata']:
            p = self.root / f'copado/templates/Run SFDX Codeanalyzer QIF_1.{suffix}.json'
            x = json.loads(p.read_text())
            x['steps'][0]['config']['parameters'][0]['value'] = 'wrong'
            p.write_text(json.dumps(x))
        with self.assertRaisesRegex(ValueError, 'parameters mismatch'):
            check_contracts(self.root)

    def test_invalid_flow_rejected(self):
        p = self.root / 'test-data/force-app/main/default/flows/TestUserDataSharingViolationExact.flow-meta.xml'
        p.write_text(p.read_text().replace('<dataType>SObject</dataType>', '<dataType>Record</dataType>'))
        with self.assertRaisesRegex(ValueError, 'Invalid Flow'):
            check_contracts(self.root)

    def test_missing_scenario_rejected(self):
        p = self.root / 'test-data/assertions/scenarios.v1.json'
        x = json.loads(p.read_text()); x['scenarios'].pop(); p.write_text(json.dumps(x))
        with self.assertRaisesRegex(ValueError, 'catalog incomplete'):
            check_contracts(self.root)


class EvidenceOutcomeTests(unittest.TestCase):
    def run_verifier(self, args, run_effect=None, inspect_effect=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with patch.object(verify_local, 'ROOT', root), \
                    patch.object(verify_local, 'candidate_manifest', return_value={}), \
                    patch.object(verify_local, 'check_contracts', return_value='Valid'), \
                    patch.object(sys, 'argv', ['verify_local.py', *args]), \
                    patch.object(verify_local.subprocess, 'run', side_effect=run_effect,
                                 return_value=subprocess.CompletedProcess([], 0)) as commands, \
                    patch.object(verify_local.subprocess, 'check_output', side_effect=inspect_effect), \
                    contextlib.redirect_stdout(io.StringIO()):
                code = verify_local.main()
            evidence_path = next(root.rglob('evidence.json'))
            return (code, json.loads(evidence_path.read_text()),
                    evidence_path.with_name('summary.md').read_text(), commands.call_args_list)

    def test_image_inspection_failure_does_not_report_success(self):
        error = subprocess.CalledProcessError(1, ['docker', 'image', 'inspect'],
                                             output='synthetic-sensitive-output')
        code, evidence, summary, calls = self.run_verifier(
            ['--mode', 'container', '--skip-build'], inspect_effect=error)
        self.assertEqual(code, 1)
        self.assertEqual(evidence['status'], 'FAILED')
        self.assertIn('\n\nFAILED —', summary)
        self.assertNotIn('synthetic-sensitive-output', json.dumps(evidence) + summary)
        self.assertTrue(any(c['name'] == 'verification-run' and c['status'] == 'FAILED'
                            for c in evidence['checks']))
        self.assertFalse(any(c.args[0][:2] == ['docker', 'run'] for c in calls))

    def test_interruption_before_first_check_does_not_report_success(self):
        code, evidence, summary, calls = self.run_verifier([], run_effect=KeyboardInterrupt())
        self.assertEqual(code, 130)
        self.assertEqual(evidence['status'], 'INTERRUPTED')
        self.assertIn('\n\nINTERRUPTED —', summary)
        self.assertEqual(len(calls), 1)
        self.assertFalse(any(c['status'] == 'PASSED' for c in evidence['checks']))

    def test_completed_fast_run_passes_with_container_explicitly_skipped(self):
        code, evidence, summary, _ = self.run_verifier([])
        self.assertEqual(code, 0)
        self.assertEqual(evidence['status'], 'PASSED')
        self.assertIn('\n\nPASSED —', summary)
        self.assertIn({'name': 'container-tests', 'status': 'NOT_RUN',
                       'detail': 'Select --mode container or all'}, evidence['checks'])
