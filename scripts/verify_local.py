#!/usr/bin/env python3
"""Credential-free local verification. No org operations or package promotion."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
NS = {'m': 'http://soap.sforce.com/2006/04/metadata'}


def read_json(path):
    return json.loads(path.read_text())


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_contracts(root):
    function = read_json(root / 'copado/functions/Run_CodeAnalyzer_QIF.metadata.json')
    template_path = root / 'copado/templates/Run SFDX Codeanalyzer QIF_1.template.json'
    template = read_json(template_path)
    require(template == read_json(template_path.with_name('Run SFDX Codeanalyzer QIF_1.metadata.json')), 'Template copies differ')
    bundles = read_json(root / 'force-app/main/default/staticresources/CopadoSFDXAnalyzer.json')['RecordSetBundles']
    records = {}
    for bundle in bundles:
        require(len(bundle['Records']) == 1, 'Expected one record per packaged type')
        records[bundle['ObjectType']] = bundle['Records'][0]
    fun = records['copado__Function__c']
    step = records['copado__JobStep__c']
    tmpl = records['copado__JobTemplate__c']
    require(fun['copado__Script__c'] == (root / 'copado/functions/Run_CodeAnalyzer_QIF.sh').read_text(), 'Embedded function script is stale')
    require(fun['copado__Image_Name__c'] == function['imagename'], 'Image mismatch')
    require(json.loads(fun['copado__Parameters__c']) == function['parameters'], 'Function parameter mismatch')
    require(template['apiname'] == tmpl['copado__ApiName__c'] == 'Run SFDX Codeanalyzer QIF_1', 'Template identity changed')
    require(template['steps'][0]['apiname'] == step['copado__ApiName__c'] == 'Run SFDX Codeanalyzer QIF_1_Run SFDX Code Analyzer_1', 'Step identity changed')
    require(step['copado__JobTemplate__c'] == tmpl['Id'], 'Packaged step parent mismatch')
    require(template['steps'][0]['config'] == json.loads(step['copado__ConfigJson__c']), 'Step parameters mismatch')
    require(template['steps'][0]['resultViewerComponent'] == step['copado__Result_Viewer_Component__c'] == 'copado_labs:resultTable', 'Viewer mismatch')
    manifest = read_json(root / 'copado/extension_manifest.json')
    require(manifest['templates'] == [template['apiname']] and manifest['functions'] == [function['apiname']], 'Extension manifest mismatch')
    tool = ET.parse(root / 'force-app/main/default/customMetadata/copado__TestTool.sfdx_scanner.md-meta.xml')
    refs = {v.find('m:field', NS).text: v.find('m:value', NS).text for v in tool.findall('m:values', NS)}
    require(refs['copado__JobTemplate__c'] == template['apiname'], 'Custom metadata reference mismatch')
    params = {p['name']: p for p in template['steps'][0]['config']['parameters']}
    require(params['apexGuruSessionId'].get('sensitive') is True and params['apexGuruSessionId']['value'] == '{$Source.Credential.SessionId}', 'Sensitive source credential contract changed')
    catalog = read_json(root / 'test-data/assertions/scenarios.v1.json')
    require({s['id'] for s in catalog['scenarios']} == {f'TC{i}' for i in range(1, 15)} | {'3a', '3b', '3c'}, 'Scenario catalog incomplete')
    require(len(catalog['scenarios']) == 17, 'Duplicate scenario IDs')
    for scenario in catalog['scenarios']:
        require(scenario['lifecycle'] in ['after-commit', 'after-promotion', 'before-deployment', 'direct-function', 'ui'], 'Unknown lifecycle')
        require(scenario['fixtureSet'] in catalog['fixtureSets'], 'Unknown fixture set')
        if scenario['config']:
            require((root / 'test-data/configs' / scenario['config']).is_file(), 'Missing scenario config')
    for paths in catalog['fixtureSets'].values():
        for path in paths:
            require((root / 'test-data' / path).exists(), 'Missing fixture: ' + path)
    dockerfile = (root / 'copado/images/Dockerfile').read_text()
    for name, version in catalog['localEnginePins'].items():
        require(name + '@v' + version in dockerfile, 'Catalog pin differs from Dockerfile: ' + name)
    for path in (root / 'test-data').rglob('*.xml'):
        tree = ET.parse(path)
        require(not any(e.text == 'Record' for e in tree.findall('.//m:dataType', NS)), 'Invalid Flow Record data type')
        if tree.getroot().tag.endswith('Flow'):
            names = {e.text for e in tree.findall('./*/m:name', NS)}
            require(all(e.text in names for e in tree.findall('.//m:targetReference', NS)), 'Dangling Flow connector')
    for path in list((root / 'copado').rglob('*.json')) + list((root / 'test-data').rglob('*.json')):
        read_json(path)
    return 'Source/package identities, parameters, script, viewer, fixture XML and scenario catalog agree'


def candidate_manifest(root):
    # Hash only source inputs, never environment/auth/config or generated reports.
    paths = ['copado/functions/Run_CodeAnalyzer_QIF.sh', 'copado/functions/Run_CodeAnalyzer_QIF.metadata.json',
             'copado/templates/Run SFDX Codeanalyzer QIF_1.template.json', 'copado/images/Dockerfile',
             'force-app/main/default/staticresources/CopadoSFDXAnalyzer.json']
    paths += [str(p.relative_to(root)) for base in ['scripts', 'test-data', 'copado/local']
              for p in (root / base).rglob('*') if p.is_file() and p.suffix in ['.py', '.sh', '.json', '.xml', '.cls', '.trigger', '.component', '.js', '.cjs', '.html', '.yaml', '.yml']]
    return {'schemaVersion': 1, 'kind': 'local-source-snapshot-not-package-provenance',
            'gitCommitSha': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
            'gitTreeClean': not bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip()),
            'imageName': read_json(root / 'copado/functions/Run_CodeAnalyzer_QIF.metadata.json')['imagename'],
            'sha256': {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sorted(set(paths))}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['fast', 'container', 'all'], default='fast')
    parser.add_argument('--image', default='copadodocker')
    parser.add_argument('--skip-build', action='store_true', help='Use an existing local image (pins still checked)')
    args = parser.parse_args()
    run_id = time.strftime('local-%Y%m%dT%H%M%SZ-', time.gmtime()) + uuid.uuid4().hex[:8]
    out = ROOT / '.agentia/runs' / run_id
    out.mkdir(parents=True)
    manifest = candidate_manifest(ROOT)
    (out / 'candidate-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    evidence = {'schemaVersion': 1, 'runId': run_id, 'tier': 'local', 'mode': args.mode,
                'checks': [], 'liveOrgVerification': 'NOT_RUN', 'packageVerification': 'NOT_RUN'}

    def check(name, action):
        start = time.monotonic()
        try:
            detail = action()
            status = 'PASSED'
        except Exception as exc:
            # Do not persist subprocess output: CLI tools can include environment data.
            detail = str(exc) if isinstance(exc, ValueError) else type(exc).__name__
            status = 'FAILED'
        evidence['checks'].append({'name': name, 'status': status, 'detail': detail,
                                   'durationSeconds': round(time.monotonic() - start, 2)})
        print(name + ': ' + status, flush=True)
        return status == 'PASSED'

    def run(command, timeout=300):
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        require(result.returncode == 0, 'Command returned exit code ' + str(result.returncode))
        return 'Exit code 0 (raw output not retained)'

    completed = False
    interrupted = False
    try:
        check('syntax', lambda: run(['bash', '-c', 'for f in copado/functions/*.sh copado/local/*.sh scripts/*.sh; do bash -n "$f" || exit; done']))
        check('diff-whitespace', lambda: run(['git', 'diff', '--check']))
        check('contracts', lambda: check_contracts(ROOT))
        check('verifier-regressions', lambda: run([sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts', '-p', 'test_*.py']))
        check('viewer-contract', lambda: run(['node', 'scripts/test-result-table.cjs']))
        if args.mode in ['fast', 'all']:
            check('host-function-mocks', lambda: run(['bash', 'copado/local/test_execution.sh']))
        if args.mode in ['container', 'all']:
            if check('docker-available', lambda: run(['docker', 'info', '--format', '{{.ServerVersion}}'], 30)):
                built = args.skip_build or check('docker-build', lambda: run(['docker', 'build', '--platform', 'linux/amd64', '-t', args.image, 'copado/images'], 1200))
                if built:
                    image_id = subprocess.check_output(['docker', 'image', 'inspect', args.image, '--format', '{{.Id}}'], text=True).strip()
                    evidence['localImageId'] = image_id
                    for name, script in [('container-function-mocks', 'test_execution.sh'), ('real-engine-smoke', 'test_real_engines.sh')]:
                        check(name, lambda script=script: run(['docker', 'run', '--rm', '--platform', 'linux/amd64', '--network', 'none',
                              '--mount', f'type=bind,source={ROOT},target=/t,readonly', image_id, 'bash', '/t/copado/local/' + script], 600))
            else:
                evidence['checks'].append({'name': 'container-tests', 'status': 'BLOCKED', 'detail': 'Docker unavailable'})
        else:
            evidence['checks'].append({'name': 'container-tests', 'status': 'NOT_RUN', 'detail': 'Select --mode container or all'})
        completed = True
    except KeyboardInterrupt:
        interrupted = True
        evidence['checks'].append({'name': 'verification-run', 'status': 'INTERRUPTED',
                                   'detail': 'Verification interrupted before completion'})
    except Exception as exc:
        # Provider exceptions may contain sensitive output; retain only the type.
        evidence['checks'].append({'name': 'verification-run', 'status': 'FAILED',
                                   'detail': type(exc).__name__})
    finally:
        evidence['status'] = 'PASSED' if completed and all(c['status'] in ['PASSED', 'NOT_RUN'] for c in evidence['checks']) else 'FAILED'
        if interrupted:
            evidence['status'] = 'INTERRUPTED'
        evidence['scope'] = 'Selected local checks only; not a release approval'
        (out / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
        (out / 'summary.md').write_text('# Local verification\n\n' + evidence['status'] + ' — ' + evidence['scope'] + '\n\n' + '\n'.join('- ' + c['name'] + ': ' + c['status'] for c in evidence['checks']) + '\n')
        print('Evidence: ' + str(out), flush=True)
    return 130 if interrupted else (0 if evidence['status'] == 'PASSED' else 1)


if __name__ == '__main__':
    sys.exit(main())
