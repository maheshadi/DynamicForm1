import { LightningElement, api, track } from 'lwc';

const ACTION_COLORS  = { Show:'#2e844a', Hide:'#ba0517', 'Make Required':'#e07400', 'Auto-Populate':'#0070d2' };
const NUMBER_FIELDS  = new Set(['minLength', 'maxLength', 'minValue', 'maxValue', 'columns']);

export default class HrBuilderProperties extends LightningElement {
    @api selectedField   = null;
    @api selectedSection = null;
    @api formSchema      = {};

    @track activeTab = 'properties';

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
            targetType     : 'field',
            targetApiName  : this.selectedField.apiName
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

    handleFormChange(evt) {
        const f = evt.target.dataset.field;
        this._dispatch(null, 'form', { [f]: this._coerce(f, this._readValue(evt)) });
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