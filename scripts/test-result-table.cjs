// Pure transformation tests of the actual component source; no browser/LDS claims.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
let source = fs.readFileSync(path.join(__dirname, '../force-app/main/default/lwc/resultTable/resultTable.js'), 'utf8');
source = source.replace(/^import .*;\s*$/gm, '')
  .replace(/@(?:api|track)\s+/g, '')
  .replace(/@wire\([\s\S]*?\n    \}\)\s*/g, '')
  .replace(/^\s*@wire\([^\n]*\)\s*$/gm, '')
  .replace('export default class ResultTable', 'class ResultTable');
const context = vm.createContext({ LightningElement: class {} });
vm.runInContext(source + '\nglobalThis.component = new ResultTable();', context);
const c = context.component;
const report = {violationCounts:{total:2,sev2:1,sev4:1}, violations:[
  {engine:'apexguru',rule:'Example',severity:2,message:'finding',tags:['Performance'],locations:[{file:'/app/changed-sources/force-app/main/default/classes/Example.cls',startLine:7}]},
  {engine:'future-engine',rule:'NewRule',severity:4,message:'other',tags:[],locations:[]}
]};
const data = c.getFormattedData(JSON.stringify(report));
assert.equal(data.formattedJson.length, 2);
assert.equal(data.formattedJson[0].file, 'classes/Example.cls');
assert.equal(data.formattedJson[0].line, 7);
c.formattedJson = data.formattedJson;
assert.equal(c.groupByEngineAndRuleArray(c.formattedJson).length, 2);
c.selectedSeverity = '2';
assert.equal(c.groupByEngineAndRuleArray(c.formattedJson).length, 1);
c.selectedSeverity = null;
assert.equal(c.getFormattedData(JSON.stringify({violations:[],violationCounts:{total:0}})).formattedJson.length, 0);
assert.equal(c.getEngineDescription('future-engine'), '');
for (const engine of ['apexguru','pmd','eslint','regex','flow','sfge','cpd','retire-js','uibundle']) assert.ok(c.engineDescriptions[engine], engine);
console.log('Actual resultTable transformations, grouping, severity, empty and unknown-engine contracts passed.');
// Verify descriptions for engines exposed by the actual installed plugin.
(async () => {
  const os = require('node:os');
  const { createRequire } = require('node:module');
  const { pathToFileURL } = require('node:url');
  const candidates = process.env.CODE_ANALYZER_PLUGIN_DIR ? [process.env.CODE_ANALYZER_PLUGIN_DIR] : [
    process.env.XDG_DATA_HOME && path.join(process.env.XDG_DATA_HOME, 'sf/node_modules/@salesforce/plugin-code-analyzer'),
    path.join(os.homedir(), '.local/share/sf/node_modules/@salesforce/plugin-code-analyzer'),
    path.join(os.homedir(), '.local/share/sfdx/node_modules/@salesforce/plugin-code-analyzer'),
    '/usr/local/lib/node_modules/@salesforce/plugin-code-analyzer',
    '/usr/local/lib/sf/node_modules/@salesforce/plugin-code-analyzer'
  ].filter(Boolean);
  const pkg = candidates.map(dir => path.join(dir, 'package.json')).find(file => fs.existsSync(file));
  assert.ok(pkg, 'Code Analyzer plugin required for discovery coverage');
  const expected = JSON.parse(fs.readFileSync(path.join(__dirname, '../test-data/assertions/scenarios.v1.json'))).localEnginePins['@salesforce/plugin-code-analyzer'];
  assert.equal(JSON.parse(fs.readFileSync(pkg)).version, expected, 'Host plugin pin differs from catalog');
  const req = createRequire(pkg);
  const { EnginePluginsFactoryImpl } = await import(pathToFileURL(req.resolve('./lib/lib/factories/EnginePluginsFactory.js')).href);
  const engines = new EnginePluginsFactoryImpl().create().flatMap(plugin => plugin.getAvailableEngineNames());
  for (const engine of engines) assert.ok(c.engineDescriptions[engine], `Missing description: ${engine}`);
  console.log('Installed plugin engine descriptions passed.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
