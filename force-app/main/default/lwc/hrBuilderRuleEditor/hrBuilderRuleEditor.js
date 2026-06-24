import { LightningElement, api, track } from 'lwc';

export default class HrBuilderRuleEditor extends LightningElement {
    @api formSchema = {};
    @track _rules   = [];

    connectedCallback() {
        this._rules = JSON.parse(JSON.stringify(this.formSchema.rules || []));
    }

    get rules()    { return this._rules; }
    get hasRules() { return this._rules.length > 0; }

    get fieldOptions() {
        const opts = [];
        for (const sec of (this.formSchema.sections || [])) {
            for (const f of (sec.fields || [])) {
                opts.push({ label: f.label || f.apiName, value: f.apiName });
            }
        }
        return opts;
    }
    get operatorOptions() {
        return ['equals','not_equals','contains','not_contains','starts_with',
                'is_empty','is_not_empty','greater_than','less_than','in_list','not_in_list']
            .map(o => ({ label: o.replace(/_/g, ' '), value: o }));
    }
    get actionOptions() {
        return ['Show','Hide','Make_Required','Make_Optional','Auto_Populate','Set_Value','Enable','Disable']
            .map(a => ({ label: a.replace(/_/g, ' '), value: a }));
    }
    get targetTypeOptions() {
        return [{ label: 'Field', value: 'Field' }, { label: 'Section', value: 'Section' }];
    }

    handleAddRule() {
        this._rules = [...this._rules, {
            id: 'r_' + Date.now(), name: 'New Rule',
            triggerFieldApiName: '', operator: 'equals', triggerValue: '',
            action: 'Show', targetType: 'Field', targetApiName: '',
            actionValue: '', isActive: true, logicGroup: ''
        }];
        this._emit();
    }

    handleRemoveRule(evt) {
        const id = evt.currentTarget.dataset.id;
        this._rules = this._rules.filter(r => r.id !== id);
        this._emit();
    }

    handleRuleChange(evt) {
        const { id, field } = evt.currentTarget.dataset;
        // lightning-combobox fires detail.value; lightning-input fires target.value
        const value = (evt.detail && evt.detail.value !== undefined) ? evt.detail.value : evt.target.value;
        this._rules = this._rules.map(r => r.id === id ? { ...r, [field]: value } : r);
        this._emit();
    }

    handleRuleToggle(evt) {
        const { id, field } = evt.currentTarget.dataset;
        this._rules = this._rules.map(r => r.id === id ? { ...r, [field]: evt.target.checked } : r);
        this._emit();
    }

    _emit() {
        this.dispatchEvent(new CustomEvent('ruleupdated', { detail: { rules: this._rules } }));
    }
}