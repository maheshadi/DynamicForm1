import { LightningElement, api, track, wire } from 'lwc';
import getWhitelistedObjects from '@salesforce/apex/HR_SFObjectService.getWhitelistedObjects';
import getRecordTypes       from '@salesforce/apex/HR_SFObjectService.getRecordTypes';
import describeObject       from '@salesforce/apex/HR_SFObjectService.describeObject';

const ACTION_COLORS  = { Show:'#2e844a', Hide:'#ba0517', 'Make Required':'#e07400', 'Auto-Populate':'#0070d2' };
const NUMBER_FIELDS  = new Set(['minLength', 'maxLength', 'minValue', 'maxValue', 'columns']);

// Which Salesforce field types each form field type can sensibly map onto.
// Undefined form types show all createable fields.
const TYPE_COMPAT = {
    Text:        ['STRING', 'TEXTAREA', 'PICKLIST', 'EMAIL', 'PHONE', 'URL'],
    Email:       ['EMAIL', 'STRING'],
    Phone:       ['PHONE', 'STRING'],
    URL:         ['URL', 'STRING'],
    Number:      ['DOUBLE', 'CURRENCY', 'PERCENT', 'INTEGER', 'STRING'],
    Currency:    ['CURRENCY', 'DOUBLE', 'STRING'],
    Percentage:  ['PERCENT', 'DOUBLE', 'STRING'],
    Date:        ['DATE', 'STRING'],
    DateTime:    ['DATETIME', 'STRING'],
    TextArea:    ['TEXTAREA', 'STRING'],
    RichText:    ['TEXTAREA', 'STRING'],
    Dropdown:    ['PICKLIST', 'STRING'],
    Radio:       ['PICKLIST', 'STRING'],
    Checkbox:    ['BOOLEAN'],
    MultiSelect: ['MULTIPICKLIST', 'TEXTAREA', 'STRING'],
    Lookup:      ['REFERENCE', 'STRING'],
    CurrentUser: ['REFERENCE', 'STRING']
};
const UNMAPPABLE_TYPES = new Set(['InfoBox', 'Instructions', 'Divider', 'SectionHeader', 'FileUpload', 'RecordField']);

export default class HrBuilderProperties extends LightningElement {
    _selectedFieldInternal = null;
    @api get selectedField() { return this._selectedFieldInternal; }
    set selectedField(v) {
        this._selectedFieldInternal = v;
        this._syncMappingObject();
    }
    @api selectedSection = null;
    @api formSchema      = {};

    @track activeTab = 'properties';
    @track _whitelistedObjects = [];
    @track _recordTypes        = [];

    @wire(getWhitelistedObjects)
    wiredWhitelist({ data }) {
        if (data) this._whitelistedObjects = data;
    }

    // Reactive on the currently selected target object
    @wire(getRecordTypes, { objectApiName: '$formSchema.targetObjectApi' })
    wiredRecordTypes({ data, error }) {
        this._recordTypes = (data && !error) ? data : [];
    }

    get targetObjectOptions() {
        return this._whitelistedObjects
            .filter(o => o.allowAsTarget)
            .map(o => ({ label: o.label + ' (' + o.apiName + ')', value: o.apiName }));
    }
    get lookupObjectOptions() {
        return this._whitelistedObjects
            .filter(o => o.allowAsLookup)
            .map(o => ({ label: o.label + ' (' + o.apiName + ')', value: o.apiName }));
    }
    get recordTypeOptions() {
        return [{ label: '— Default —', value: '' },
                ...this._recordTypes.map(rt => ({ label: rt.label, value: rt.devName }))];
    }
    get hasRecordTypes() { return this._recordTypes.length > 0; }
    get isLookupField()  { return !!this.selectedField && this.selectedField.type === 'Lookup'; }

    // ── SF field mapping picker ───────────────────────────────────────────────
    @track _mappingObjectApi = null;
    @track _mappingFields    = [];

    @wire(describeObject, { objectApiName: '$_mappingObjectApi' })
    wiredMappingDescribe({ data, error }) {
        this._mappingFields = (data && data.fields && !error) ? data.fields : [];
    }

    // Keep the mapping-object selection in sync with the selected field's stored
    // mapping ('Obj.Field' → Obj, plain 'Field' → the form's primary target object).
    _syncMappingObject() {
        const f = this._selectedFieldInternal;
        if (!f || UNMAPPABLE_TYPES.has(f.type)) return;
        const m = (f.sfFieldApi || '').trim();
        const obj = m.includes('.')
            ? m.split('.')[0]
            : (this.formSchema && this.formSchema.targetObjectApi) || null;
        if (obj && obj !== this._mappingObjectApi) this._mappingObjectApi = obj;
    }

    get isMappableField() {
        return !!this.selectedField && !UNMAPPABLE_TYPES.has(this.selectedField.type);
    }

    get mappingObjectOptions() {
        const target = this.formSchema && this.formSchema.targetObjectApi;
        const opts = [];
        const seen = new Set();
        if (target) {
            opts.push({ label: target + ' — primary target', value: target });
            seen.add(target);
        }
        this._whitelistedObjects.forEach(o => {
            if (!seen.has(o.apiName)) {
                seen.add(o.apiName);
                opts.push({ label: o.label + ' (' + o.apiName + ') — related', value: o.apiName });
            }
        });
        return opts;
    }

    get mappingObjectValue() {
        const m = ((this.selectedField && this.selectedField.sfFieldApi) || '').trim();
        if (m.includes('.')) return m.split('.')[0];
        return this._mappingObjectApi || (this.formSchema && this.formSchema.targetObjectApi) || '';
    }

    get mappingFieldValue() {
        const m = ((this.selectedField && this.selectedField.sfFieldApi) || '').trim();
        return m.includes('.') ? m.substring(m.indexOf('.') + 1) : m;
    }

    get mappingFieldOptions() {
        const compat = TYPE_COMPAT[this.selectedField && this.selectedField.type];
        const fields = (this._mappingFields || [])
            .filter(f => f.createable && (!compat || compat.includes(f.type)))
            .map(f => ({ label: f.label + ' (' + f.apiName + ')', value: f.apiName }))
            .sort((a, b) => a.label.localeCompare(b.label));
        return [{ label: '— Not mapped —', value: '' }, ...fields];
    }

    handleMappingObjectChange(evt) {
        this._mappingObjectApi = evt.detail.value;
        // Object changed → previous field mapping no longer applies
        this._dispatch(this.selectedField.id, 'field', { sfFieldApi: '' });
    }

    handleMappingFieldChange(evt) {
        const fieldApi = evt.detail.value;
        const target   = this.formSchema && this.formSchema.targetObjectApi;
        const obj      = this._mappingObjectApi || target;
        const composed = !fieldApi ? '' : (obj === target ? fieldApi : obj + '.' + fieldApi);
        this._dispatch(this.selectedField.id, 'field', { sfFieldApi: composed });
    }

    // ── Tab state ─────────────────────────────────────────────────────────────
    get isPropertiesTab() { return this.activeTab === 'properties'; }
    get isLogicTab()      { return this.activeTab === 'logic'; }
    get isStyleTab()      { return this.activeTab === 'style'; }
    get isValidationTab() { return this.activeTab === 'validation'; }

    get tab1Class() { return this._tabClass('properties'); }
    get tab2Class() { return this._tabClass('logic'); }
    get tab3Class() { return this._tabClass('style'); }
    get tab4Class() { return this._tabClass('validation'); }
    _tabClass(name) { return 'hr-tab-btn' + (this.activeTab === name ? ' hr-tab-active' : ''); }

    handleTabClick(evt) { this.activeTab = evt.currentTarget.dataset.tab; }

    // ── Selection state ───────────────────────────────────────────────────────
    get hasSelection()      { return this.isFieldSelected || this.isSectionSelected || this.isFormSelected; }
    get isFieldSelected()   { return !!this.selectedField; }
    get isSectionSelected() { return !this.selectedField && !!this.selectedSection; }
    get isFormSelected()    { return !this.selectedField && !this.selectedSection; }
    get selectedSectionColumns() { return String((this.selectedSection && this.selectedSection.columns) || '2'); }

    // ── Logic tab — rules for selected field ─────────────────────────────────
    get fieldRules() {
        if (!this.selectedField || !this.formSchema || !this.formSchema.rules) return [];
        return this.formSchema.rules
            .filter(r => r.targetApiName === this.selectedField.apiName)
            .map(r => ({
                ...r,
                actionStyle: 'background:' + (ACTION_COLORS[r.action] || '#444') + '22;color:' + (ACTION_COLORS[r.action] || '#444') + ';'
            }));
    }
    get hasFieldRules() { return this.fieldRules.length > 0; }

    handleAddFieldRule() {
        if (!this.selectedField) return;
        const newRule = {
            id             : 'r_' + Date.now(),
            name           : 'Rule for ' + this.selectedField.label,
            triggerFieldApiName: '',
            operator       : 'equals',
            triggerValue   : '',
            action         : 'Show',
            targetType     : 'Field',
            targetApiName  : this.selectedField.apiName,
            actionValue    : '',
            isActive       : true,
            logicGroup     : 'AND',
            additionalConditions: []
        };
        const currentRules = (this.formSchema && this.formSchema.rules) ? [...this.formSchema.rules] : [];
        this.dispatchEvent(new CustomEvent('propertychanged', {
            detail: { targetId: null, targetType: 'form', changes: { rules: [...currentRules, newRule] } }
        }));
        // Switch to full rules editor for editing
        this.dispatchEvent(new CustomEvent('rulesclick'));
    }

    handleRemoveFieldRule(evt) {
        const ruleId = evt.currentTarget.dataset.id;
        const currentRules = (this.formSchema && this.formSchema.rules) ? this.formSchema.rules : [];
        this.dispatchEvent(new CustomEvent('propertychanged', {
            detail: { targetId: null, targetType: 'form', changes: { rules: currentRules.filter(r => r.id !== ruleId) } }
        }));
    }

    // ── Options ───────────────────────────────────────────────────────────────
    get categoryOptions() {
        return ['Termination','Onboarding','Leave','Compensation','Transfer','Performance','Benefits','General','Other']
            .map(c => ({ label: c, value: c }));
    }
    get submitActionOptions() {
        return [
            { label: 'Show Message',  value: 'Show_Message' },
            { label: 'Redirect URL',  value: 'Redirect_URL' },
            { label: 'Launch Flow',   value: 'Launch_Flow'  },
            { label: 'Close Modal',   value: 'Close_Modal'  }
        ];
    }
    get columnOptions()       { return [{ label:'1 Column', value:'1' }, { label:'2 Columns', value:'2' }]; }
    get spanOptions()         { return [{ label:'Half (1 col)', value:'Half' }, { label:'Full (2 cols)', value:'Full' }]; }
    get labelPositionOptions(){ return [{ label:'Top', value:'top' }, { label:'Left', value:'left' }, { label:'Hidden', value:'hidden' }]; }
    get fieldSizeOptions()    { return [{ label:'Small', value:'small' }, { label:'Medium', value:'medium' }, { label:'Large', value:'large' }]; }

    // ── Change handlers ───────────────────────────────────────────────────────
    _dispatch(targetId, targetType, changes) {
        this.dispatchEvent(new CustomEvent('propertychanged', { detail: { targetId, targetType, changes } }));
    }

    // lightning-combobox puts the selected value in evt.detail.value;
    // evt.target.value is stale (holds the pre-change value) for custom LWC components.
    // lightning-input text/number/color puts the value in evt.target.value.
    // Use detail.value when present, fall back to target.value for native inputs.
    _readValue(evt) {
        return (evt.detail && evt.detail.value !== undefined) ? evt.detail.value : evt.target.value;
    }

    _coerce(field, value) {
        return NUMBER_FIELDS.has(field) ? (value === '' ? null : Number(value)) : value;
    }

    // Convert any user-typed string to a valid ^[a-z][a-z0-9_]*$ API name.
    // Handles camelCase, PascalCase, spaces, and leading digits gracefully.
    _sanitizeApiName(raw) {
        let s = (raw || '')
            .trim()
            .replace(/([a-z])([A-Z])/g, '$1_$2')        // camelCase → snake_case
            .replace(/([A-Z]+)([A-Z][a-z])/g, '$1_$2')  // ABCDef → ABC_Def
            .toLowerCase()
            .replace(/[^a-z0-9_]/g, '_')                 // non-alphanumeric → _
            .replace(/^[^a-z]+/, '')                     // strip leading non-letter chars
            .replace(/_+/g, '_')                         // collapse consecutive underscores
            .replace(/_+$/, '');                         // strip trailing underscore
        return s;
    }

    // Tracks whether the user has manually edited the form API name. Once they do,
    // we stop auto-deriving it from the form name (matches Salesforce field behavior).
    _apiNameTouched = false;

    handleFormChange(evt) {
        const f   = evt.target.dataset.field;
        const raw = this._readValue(evt);

        if (f === 'apiName') {
            this._apiNameTouched = true;
            const clean = this._sanitizeApiName(raw);
            this._dispatch(null, 'form', { apiName: clean });
            return;
        }

        if (f === 'name') {
            const changes = { name: raw };
            // Auto-populate the API name from the form name (Salesforce-style) only for
            // a new, unsaved form whose API name the user hasn't manually set yet.
            if (!this.formSchema.id && !this._apiNameTouched) {
                changes.apiName = this._sanitizeApiName(raw);
            }
            this._dispatch(null, 'form', changes);
            return;
        }

        if (f === 'targetObjectApi') {
            // Record types belong to the object — reset the selection on object change.
            this._dispatch(null, 'form', { targetObjectApi: raw, recordTypeDevName: '' });
            return;
        }

        this._dispatch(null, 'form', { [f]: this._coerce(f, raw) });
    }
    handleFormToggle(evt)    { this._dispatch(null, 'form', { [evt.target.dataset.field]: evt.target.checked }); }
    handleSectionChange(evt) {
        const f   = evt.target.dataset.field;
        const val = this._coerce(f, this._readValue(evt));
        this._dispatch(this.selectedSection.id, 'section', { [f]: val });
    }
    handleSectionToggle(evt) { this._dispatch(this.selectedSection.id, 'section', { [evt.target.dataset.field]: evt.target.checked }); }
    handleFieldChange(evt) {
        const f   = evt.target.dataset.field;
        let   val = this._coerce(f, this._readValue(evt));
        if (f === 'apiName') {
            val = this._sanitizeApiName(val);
            if (!val) return;  // never dispatch an empty API name
        }
        this._dispatch(this.selectedField.id, 'field', { [f]: val });
    }
    handleFieldToggle(evt)   { this._dispatch(this.selectedField.id, 'field', { [evt.target.dataset.field]: evt.target.checked }); }
    handleRulesClick()       { this.dispatchEvent(new CustomEvent('rulesclick')); }
}