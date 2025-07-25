import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';

import VERSION_DATA_FIELD from '@salesforce/schema/ContentVersion.VersionData';
import TITLE_FIELD from '@salesforce/schema/ContentDocumentLink.ContentDocument.Title';
import LATEST_PUBLISHED_VERSION_FIELD from '@salesforce/schema/ContentDocumentLink.ContentDocument.LatestPublishedVersionId';

import jsyamllib from "@salesforce/resourceUrl/jsyamllib";
import { loadScript } from 'lightning/platformResourceLoader';

export default class ResultTable extends LightningElement {
    @api recordId;
    showTable = false;
    message = 'No Violations Found';
    @track relevantFormattedJson;
    _versionId;
    type;
    result = {};
    scriptsLoaded = false;
    formattedJson;

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'ContentDocumentLinks',
        fields: [
            `${LATEST_PUBLISHED_VERSION_FIELD.objectApiName}.${LATEST_PUBLISHED_VERSION_FIELD.fieldApiName}`,
            `${TITLE_FIELD.objectApiName}.${TITLE_FIELD.fieldApiName}`
        ]
    })
    docLinksInfo({ data }) {
        if (data) {
            const logsDoc = data?.records?.find((doc) => getFieldValue(doc, TITLE_FIELD) === 'output.json'); // change the file name from where data should be fetched

            if (logsDoc) {
                this._versionId = getFieldValue(logsDoc, LATEST_PUBLISHED_VERSION_FIELD);
            }
        }
    }

    @wire(getRecord, { recordId: '$_versionId', fields: [VERSION_DATA_FIELD] })
    wiredVersion({ data }) {
        if (data) {
            const rawData = getFieldValue(data, VERSION_DATA_FIELD);
            const serializedJson = this.b64DecodeUnicode(rawData);
            const { type, formattedJson } = this.getFormattedData(serializedJson);
            if (formattedJson.length > 0) {
                this.showTable = true;
                this.type = type;
                this.formattedJson = formattedJson;
                this.relevantFormattedJson = formattedJson;
                return;
            }
            return;
        }
    }

    async connectedCallback() {
        if (!this.scriptsLoaded) {
            await loadScript(this, jsyamllib);
            this.scriptsLoaded = true;
        }
    }

    get yamlData() {
        if (this.isYAML && this.scriptsLoaded) {
            return jsyaml.dump(this.formattedJson);
        }

        return '';
    }

    get recordCount() {
        return this.relevantFormattedJson?.length;
    }

    get groupedByEngine() {
        if (!this.formattedJson) return [];
        const engines = {};
        this.formattedJson.forEach(v => {
            if (!engines[v.engine]) {
                engines[v.engine] = { engine: v.engine, rules: {} };
            }
            if (!engines[v.engine].rules[v.rule]) {
                engines[v.engine].rules[v.rule] = {
                    rule: v.rule,
                    severity: v.severity,
                    tags: v.tags,
                    resource: v.resource,
                    violations: []
                };
            }
            engines[v.engine].rules[v.rule].violations.push(v);
        });
        // Convert rules object to array for each engine
        return Object.values(engines).map(engineObj => ({
            engine: engineObj.engine,
            rules: Object.values(engineObj.rules)
        }));
    }

    get groupedByRule() {
        if (!this.formattedJson) return [];
        const groups = {};
        this.formattedJson.forEach(v => {
            if (!groups[v.rule]) {
                groups[v.rule] = {
                    rule: v.rule,
                    engine: v.engine,
                    severity: v.severity,
                    tags: v.tags,
                    resource: v.resource,
                    violations: []
                };
            }
            groups[v.rule].violations.push(v);
        });
        return Object.values(groups);
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
                label: key.charAt(0).toUpperCase() + key.slice(1),
                fieldName: key,
                type: 'text'
            };
        });
    }


    get isTabular() {
        return (this.type === 'Table' && this.columns.length);
    }


    get isYAML() {
        return (this.type === 'YAML' && this.formattedJson);
    }


    get isString() {
        return (this.type === 'String' && this.formattedJson);
    }

    // Transformation function
    transformJson(parsedJson) {
        if (parsedJson.violations && Array.isArray(parsedJson.violations)) {
            return parsedJson.violations.map((violation, idx) => {
                const primaryLoc = violation.locations?.[violation.primaryLocationIndex] || violation.locations?.[0] || {};
                return {
                    id: `${violation.rule}-${primaryLoc.file}-${primaryLoc.startLine}-${idx}`,
                    rule: violation.rule,
                    engine: violation.engine,
                    severity: violation.severity,
                    tags: violation.tags,
                    file: primaryLoc.file,
                    line: primaryLoc.startLine,
                    message: violation.message,
                    resource: violation.resources?.[0] || '',
                    allLocations: violation.locations,
                    fullViolation: violation
                };
            });
        }
        return [];
    }

    getFormattedData(serializedJson) {
        try {
            const formattedJson = this.transformJson(JSON.parse(serializedJson));
            if (formattedJson?.length) {
                return {
                    type: 'Table', formattedJson
                };
            } else {
                return {
                    type: 'YAML', formattedJson
                };
            }
        } catch (error) {
            return {
                type: 'String',
                formattedJson: serializedJson
            };
        }
    }

    handleSearch(event) {
        const searchTerm = event.target.value ? event.target.value.trim().toLowerCase() : '';

        if (!searchTerm) {
            this._clearSearch();
        } else {
            this._applySearch(searchTerm);
        }
    }

    b64DecodeUnicode(str) {
        return decodeURIComponent(atob(str).split('').map(function (c) {
            return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
        }).join(''));
    }

    _clearSearch() {
        this.relevantFormattedJson = this.formattedJson;
    }


    _applySearch(searchTerm) {
        this.relevantFormattedJson = this.formattedJson.filter((row) => {
            for (const key in row) {
                const value = '' + row[key] || '';
                if (value && value.toLowerCase()?.includes(searchTerm)) {
                    return true;
                }
            }
            return false;
        });
    }
}