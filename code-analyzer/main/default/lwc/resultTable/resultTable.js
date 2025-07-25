import { LightningElement, api, track, wire } from 'lwc';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { loadScript } from 'lightning/platformResourceLoader';

import jsyamllib from "@salesforce/resourceUrl/jsyamllib";
import LATEST_PUBLISHED_VERSION_FIELD from '@salesforce/schema/ContentDocumentLink.ContentDocument.LatestPublishedVersionId';
import TITLE_FIELD from '@salesforce/schema/ContentDocumentLink.ContentDocument.Title';
import VERSION_DATA_FIELD from '@salesforce/schema/ContentVersion.VersionData';

// Constants for magic numbers and strings
const DEFAULT_GROUPING = 'engine';
const OUTPUT_FILE_NAME = 'output.json';
const UNKNOWN_FILE = 'Unknown File';
const UNKNOWN_TYPE = 'Unknown';
const MAIN_DEFAULT_PATTERN = /main\/default\/([^\/]+)\/(.+)/u;
const SEVERITY_PREFIX = 'sev';

export default class ResultTable extends LightningElement {
    @api recordId;
    @track filteredJson = null;
    @track relevantFormattedJson;
    @track selectedSeverity = null;
    @track violationCounts = null;

    formattedJson;
    groupBy = DEFAULT_GROUPING;
    groupByOptions = [
        { label: 'Engine/Rule', value: 'engine' },
        { label: 'Type/Filename', value: 'typefilename' }
    ];
    message = 'No Violations Found';
    result = {};
    scriptsLoaded = false;
    showTable = false;
    type;
    versionId;

    // Mapping of engine names to their short descriptions
    engineDescriptions = {
        cpd: 'Copy-Paste Detector: Finds duplicate code blocks in Apex and other supported languages.',
        eslint: 'Analyzes JavaScript and Lightning Web Components for code quality and style issues.',
        flow: 'Analyzes Salesforce Flows for best practices, security, and maintainability issues.',
        pmd: 'Performs static analysis on Apex, Visualforce. Includes the PMD AppExchange rules.',
        regex: 'Detects code patterns using regular expressions. Useful for enforcing simple, custom rules.',
        retirejs: 'Scans JavaScript libraries for known security vulnerabilities.',
        sfge: 'Salesforce Graph Engine: Advanced static analysis for security, CRUD/FLS, and data flow in Apex.'
    };

    @wire(getRelatedListRecords, {
        fields: [
            `${LATEST_PUBLISHED_VERSION_FIELD.objectApiName}.${LATEST_PUBLISHED_VERSION_FIELD.fieldApiName}`,
            `${TITLE_FIELD.objectApiName}.${TITLE_FIELD.fieldApiName}`
        ],
        parentRecordId: '$recordId',
        relatedListId: 'ContentDocumentLinks'
    })
    docLinksInfo({ data }) {
        if (data) {
            // Change the file name from where data should be fetched
            const logsDoc = data?.records?.find((doc) => getFieldValue(doc, TITLE_FIELD) === OUTPUT_FILE_NAME);

            if (logsDoc) {
                this.versionId = getFieldValue(logsDoc, LATEST_PUBLISHED_VERSION_FIELD);
            }
        }
    }

    @wire(getRecord, { fields: [VERSION_DATA_FIELD], recordId: '$versionId' })
    wiredVersion({ data }) {
        if (data) {
            const rawData = getFieldValue(data, VERSION_DATA_FIELD);
            const serializedJson = this.b64DecodeUnicode(rawData);
            const { formattedJson, type } = this.getFormattedData(serializedJson);

            if (formattedJson.length > 0) {
                this.formattedJson = formattedJson;
                this.relevantFormattedJson = formattedJson;
                this.showTable = true;
                this.type = type;
            }
        }
    }

    async connectedCallback() {
        if (!this.scriptsLoaded) {
            await loadScript(this, jsyamllib);
            this.scriptsLoaded = true;
        }
    }

    get columns() {
        if (this.type !== 'Table') {
            return [];
        }

        const allKeys = this.formattedJson.reduce((keys, item) => {
            return keys.concat(Object.keys(item));
        }, []);
        const uniqueKeys = [...new Set(allKeys)];

        return uniqueKeys.map(key => {
            return {
                fieldName: key,
                label: key.charAt(0).toUpperCase() + key.slice(1),
                type: 'text'
            };
        });
    }

    get groupedByEngine() {
        const data = this.filteredJson || this.formattedJson;
        if (!data) {
            return [];
        }

        const engines = {};
        data.forEach(violation => {
            if (!engines[violation.engine]) {
                engines[violation.engine] = {
                    engine: violation.engine,
                    rules: {},
                    violationCount: 0
                };
            }
            if (!engines[violation.engine].rules[violation.rule]) {
                engines[violation.engine].rules[violation.rule] = {
                    engine: violation.engine,
                    resource: violation.resource,
                    rule: violation.rule,
                    severity: violation.severity,
                    tags: violation.tags,
                    violations: []
                };
            }
            engines[violation.engine].rules[violation.rule].violations.push(violation);
            engines[violation.engine].violationCount += 1;
        });

        // Convert rules object to array for each engine, and add description
        return Object.values(engines).map(engineObj => ({
            description: this.engineDescriptions[engineObj.engine] || '',
            engine: engineObj.engine,
            label: `${engineObj.engine} (${engineObj.violationCount})`,
            rules: Object.values(engineObj.rules).map(ruleObj => ({
                ...ruleObj,
                tagsString: Array.isArray(ruleObj.tags) ? ruleObj.tags.join(', ') : ''
            })),
            violationCount: engineObj.violationCount
        }));
    }

    get filteredGroupedByEngine() {
        const data = this.filteredJson || this.formattedJson;
        if (!data) {
            return [];
        }

        const filterSeverity = this.selectedSeverity;
        const engines = {};
        data.forEach(violation => {
            if (filterSeverity && String(violation.severity) !== String(filterSeverity)) {
                return;
            }
            if (!engines[violation.engine]) {
                engines[violation.engine] = {
                    engine: violation.engine,
                    rules: {},
                    violationCount: 0
                };
            }
            if (!engines[violation.engine].rules[violation.rule]) {
                engines[violation.engine].rules[violation.rule] = {
                    engine: violation.engine,
                    resource: violation.resource,
                    rule: violation.rule,
                    severity: violation.severity,
                    tags: violation.tags,
                    violations: []
                };
            }
            engines[violation.engine].rules[violation.rule].violations.push(violation);
            engines[violation.engine].violationCount += 1;
        });

        return Object.values(engines).map(engineObj => ({
            description: this.engineDescriptions[engineObj.engine] || '',
            engine: engineObj.engine,
            label: `${engineObj.engine} (${engineObj.violationCount})`,
            rules: Object.values(engineObj.rules).map(ruleObj => ({
                ...ruleObj,
                tagsString: Array.isArray(ruleObj.tags) ? ruleObj.tags.join(', ') : ''
            })),
            violationCount: engineObj.violationCount
        }));
    }

    get groupedByRule() {
        if (!this.formattedJson) {
            return [];
        }

        const groups = {};
        this.formattedJson.forEach(violation => {
            if (!groups[violation.rule]) {
                groups[violation.rule] = {
                    engine: violation.engine,
                    resource: violation.resource,
                    rule: violation.rule,
                    severity: violation.severity,
                    tags: violation.tags,
                    violations: []
                };
            }
            groups[violation.rule].violations.push(violation);
        });

        return Object.values(groups);
    }

    get groupedByMetadataTypeArray() {
        // Use filteredJson if present, otherwise formattedJson
        const data = this.filteredJson || this.formattedJson;
        if (!data) {
            return [];
        }

        const filterSeverity = this.selectedSeverity;
        const metaTypeMap = {};

        data.forEach(violation => {
            if (filterSeverity && String(violation.severity) !== String(filterSeverity)) {
                return;
            }

            let metaType = UNKNOWN_TYPE;
            let fileKey = violation.file || UNKNOWN_FILE;

            if (violation.file) {
                // Find the segment after 'main/default/'
                const match = violation.file.match(MAIN_DEFAULT_PATTERN);
                if (match) {
                    [, metaType, fileKey] = match;
                }
            }

            if (!metaTypeMap[metaType]) {
                metaTypeMap[metaType] = {};
            }
            if (!metaTypeMap[metaType][fileKey]) {
                metaTypeMap[metaType][fileKey] = [];
            }
            metaTypeMap[metaType][fileKey].push(violation);
        });

        // Convert to array structure for template, with counts in labels
        return Object.keys(metaTypeMap).map(metaType => {
            const filesArr = Object.keys(metaTypeMap[metaType]).map(file => ({
                key: file,
                label: `${file} (${metaTypeMap[metaType][file].length})`,
                violations: metaTypeMap[metaType][file]
            }));
            const totalViolations = filesArr.reduce((sum, fileObj) => sum + fileObj.violations.length, 0);
            return {
                files: filesArr,
                key: metaType,
                label: `${metaType} (${totalViolations})`
            };
        });
    }

    get groupedViolationsArray() {
        // Use filteredJson if present, otherwise formattedJson
        const data = this.filteredJson || this.formattedJson;
        if (this.groupBy === 'engine') {
            return this.groupByEngineAndRuleArray(data);
        } else if (this.groupBy === 'typefilename') {
            // For type/filename grouping
            // Return: [{ key, label, files: [{ key, label, violations }] }]
            return this.groupedByMetadataTypeArray;
        }
        return [];
    }

    get groupedViolations() {
        if (this.groupBy === 'engine') {
            return this.groupByEngineAndRule(this.formattedJson);
        } else {
            return this.groupByFilename(this.formattedJson);
        }
    }

    get isEngineGrouping() {
        return this.groupBy === 'engine';
    }

    get isFilenameGrouping() {
        return this.groupBy === 'filename';
    }

    get isString() {
        return (this.type === 'String' && this.formattedJson);
    }

    get isTabular() {
        return (this.type === 'Table' && this.columns.length);
    }

    get isTypeFilenameGrouping() {
        return this.groupBy === 'typefilename';
    }

    get isYAML() {
        return (this.type === 'YAML' && this.formattedJson);
    }

    get recordCount() {
        return this.relevantFormattedJson?.length;
    }

    get severityLevels() {
        if (!this.violationCounts) {
            return [];
        }

        return Object.keys(this.violationCounts)
            .filter(key => key.startsWith(SEVERITY_PREFIX))
            .map(key => {
                const level = key.replace(SEVERITY_PREFIX, '');
                return {
                    buttonClass: `severity-${level}-btn`,
                    buttonVariant: 'brand',
                    count: this.violationCounts[key],
                    label: `Severity ${level}: ${this.violationCounts[key]}`,
                    level
                };
            })
            .sort((a, b) => a.level - b.level);
    }

    get violationColumns() {
        return [
            { fieldName: 'file', label: 'File', type: 'text' },
            { fieldName: 'line', label: 'Line', type: 'number' },
            { fieldName: 'message', label: 'Message', type: 'text' }
        ];
    }

    get violationColumnsForDisplay() {
        if (this.groupBy === 'typefilename') {
            // Show Engine, Severity, Rule, Line, and Message columns in this order
            return [
                { fieldName: 'engine', label: 'Engine', type: 'text' },
                { fieldName: 'rule', label: 'Rule', type: 'text' },
                { fieldName: 'severity', label: 'Severity', type: 'text' },
                { fieldName: 'line', label: 'Line', type: 'number' },
                { fieldName: 'message', label: 'Message', type: 'text' }
            ];
        }
        return this.violationColumns;
    }

    get yamlData() {
        if (this.isYAML && this.scriptsLoaded) {
            return jsyaml.dump(this.formattedJson);
        }

        return '';
    }

    b64DecodeUnicode(str) {
        return decodeURIComponent(atob(str).split('').map(function (c) {
            return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
        }).join(''));
    }

    getEngineDescription(engine) {
        return this.engineDescriptions[engine] || '';
    }

    getFormattedData(serializedJson) {
        try {
            const parsed = JSON.parse(serializedJson);
            // Set violationCounts from the top-level property
            this.violationCounts = parsed.violationCounts || null;
            const formattedJson = this.transformJson(parsed);

            if (formattedJson?.length) {
                return {
                    formattedJson,
                    type: 'Table'
                };
            } else {
                return {
                    formattedJson,
                    type: 'YAML'
                };
            }
        } catch (error) {
            return {
                formattedJson: serializedJson,
                type: 'String'
            };
        }
    }

    groupByEngineAndRule(violations) {
        // Your existing grouping logic
    }

    groupByEngineAndRuleArray(violations) {
        const filterSeverity = this.selectedSeverity;
        const engines = {};

        violations.forEach(violation => {
            if (filterSeverity && String(violation.severity) !== String(filterSeverity)) {
                return;
            }

            if (!engines[violation.engine]) {
                engines[violation.engine] = {
                    engine: violation.engine,
                    rules: {},
                    violationCount: 0
                };
            }
            if (!engines[violation.engine].rules[violation.rule]) {
                engines[violation.engine].rules[violation.rule] = {
                    engine: violation.engine,
                    resource: violation.resource,
                    rule: violation.rule,
                    severity: violation.severity,
                    tags: violation.tags,
                    violations: []
                };
            }
            engines[violation.engine].rules[violation.rule].violations.push(violation);
            engines[violation.engine].violationCount += 1;
        });

        return Object.values(engines).map(engineObj => ({
            description: this.engineDescriptions[engineObj.engine] || '',
            key: engineObj.engine,
            label: `${engineObj.engine} (${engineObj.violationCount})`,
            rules: Object.values(engineObj.rules).map(ruleObj => ({
                key: ruleObj.rule,
                label: `${ruleObj.rule} (${ruleObj.violations.length})`,
                resource: ruleObj.resource,
                severity: ruleObj.severity,
                tagsString: Array.isArray(ruleObj.tags) ? ruleObj.tags.join(', ') : '',
                violations: ruleObj.violations
            }))
        }));
    }

    groupByFilename(violations) {
        // New logic to group by filename
        const grouped = {};
        violations.forEach(violation => {
            const file = violation.sinkFileName || violation.file || UNKNOWN_FILE;
            if (!grouped[file]) {
                grouped[file] = [];
            }
            grouped[file].push(violation);
        });
        return grouped;
    }

    groupByFilenameArray(violations) {
        if (!violations) {
            return [];
        }

        const filterSeverity = this.selectedSeverity;
        const grouped = {};

        violations.forEach(violation => {
            if (filterSeverity && String(violation.severity) !== String(filterSeverity)) {
                return;
            }

            const file = violation.sinkFileName || violation.file || UNKNOWN_FILE;
            if (!grouped[file]) {
                grouped[file] = [];
            }
            grouped[file].push(violation);
        });

        return Object.keys(grouped).map(file => ({
            key: file,
            label: file,
            violations: grouped[file]
        }));
    }

    handleGroupByChange(event) {
        this.groupBy = event.detail.value;
    }

    handleSearch(event) {
        const searchTerm = event.target.value ? event.target.value.trim().toLowerCase() : '';

        if (!searchTerm) {
            this._clearSearch();
        } else {
            this._applySearch(searchTerm);
        }
    }

    handleSeverityClick(event) {
        const severity = event.currentTarget.dataset.severity;
        this.selectedSeverity = (this.selectedSeverity === severity) ? null : severity;
    }

    // Transformation function
    transformJson(parsedJson) {
        if (parsedJson.violations && Array.isArray(parsedJson.violations)) {
            return parsedJson.violations.map((violation, idx) => {
                const primaryLoc = violation.locations?.[violation.primaryLocationIndex] || violation.locations?.[0] || {};
                return {
                    allLocations: violation.locations,
                    engine: violation.engine,
                    file: primaryLoc.file,
                    fullViolation: violation,
                    id: `${violation.rule}-${primaryLoc.file}-${primaryLoc.startLine}-${idx}`,
                    line: primaryLoc.startLine,
                    message: violation.message,
                    resource: violation.resources?.[0] || '',
                    rule: violation.rule,
                    severity: violation.severity,
                    tags: violation.tags
                };
            });
        }
        return [];
    }

    _applySearch(searchTerm) {
        this.filteredJson = this.formattedJson.filter((row) => {
            for (const key in row) {
                const value = String(row[key]) || '';
                if (value && value.toLowerCase()?.includes(searchTerm)) {
                    return true;
                }
            }
            return false;
        });
    }

    _clearSearch() {
        this.filteredJson = null;
    }
}
