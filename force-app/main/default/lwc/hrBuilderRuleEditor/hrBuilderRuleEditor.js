import { LightningElement, api, track } from 'lwc';

export default class HrBuilderRuleEditor extends LightningElement {
    @api formSchema = {};
    @track _rules   = [];

    connectedCallback() {
        this._rules = JSON.parse(JSON.stringify(this.formSchema.rules || []));
    }

    get hasRules() { return this._rules.length > 0; }

    // Enrich each rule with real-time validation state so the editor can flag
    // orphaned field references before the user ever tries to save.
    get rules() {
        const fieldApiNames = new Set(this.fieldOptions.map(o => o.value));
        const sectionIds = new Set(this.sectionOptions.map(o => o.value));
        return this._rules.map(rule => {
            const additionalConditions = Array.isArray(rule.additionalConditions) ? rule.additionalConditions : [];
            const triggerMissing = !!rule.triggerFieldApiName && !fieldApiNames.has(rule.triggerFieldApiName);
            const targetMissing = !!rule.targetApiName && (
                rule.targetType === 'Section'
                    ? !sectionIds.has(rule.targetApiName)
                    : !fieldApiNames.has(rule.targetApiName)
            );
            const conditionMissing = additionalConditions.some(
                c => !!c.triggerFieldApiName && !fieldApiNames.has(c.triggerFieldApiName)
            );

            const errors = [];
            if (triggerMissing) errors.push('Trigger field no longer exists on this form.');
            if (targetMissing) errors.push(`Target ${rule.targetType === 'Section' ? 'section' : 'field'} no longer exists on this form.`);
            if (conditionMissing) errors.push('One or more additional condition fields no longer exist on this form.');

            return {
                ...rule,
                additionalConditions,
                logicGroup: rule.logicGroup || 'AND',
                _hasError: errors.length > 0,
                _errorMessage: errors.join(' '),
                _hasAdditionalConditions: additionalConditions.length > 0,
                _targetOptions: rule.targetType === 'Section' ? this.sectionOptions : this.fieldOptions
            };
        });
    }

    get fieldOptions() {
        const opts = [];
        for (const sec of (this.formSchema.sections || [])) {
            for (const f of (sec.fields || [])) {
                opts.push({ label: f.label || f.apiName, value: f.apiName });
            }
        }
        return opts;
    }
    get sectionOptions() {
        return (this.formSchema.sections || []).map(s => ({ label: s.title || s.id, value: s.id }));
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
    get logicGroupOptions() {
        return [{ label: 'ALL conditions match (AND)', value: 'AND' }, { label: 'ANY condition matches (OR)', value: 'OR' }];
    }

    handleAddRule() {
        this._rules = [...this._rules, {
            id: 'r_' + Date.now(), name: 'New Rule',
            triggerFieldApiName: '', operator: 'equals', triggerValue: '',
            action: 'Show', targetType: 'Field', targetApiName: '',
            actionValue: '', isActive: true, logicGroup: 'AND', additionalConditions: []
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

    handleAddCondition(evt) {
        const { id } = evt.currentTarget.dataset;
        this._rules = this._rules.map(r => r.id === id ? {
            ...r,
            additionalConditions: [
                ...(Array.isArray(r.additionalConditions) ? r.additionalConditions : []),
                { id: 'c_' + Date.now(), triggerFieldApiName: '', operator: 'equals', triggerValue: '' }
            ]
        } : r);
        this._emit();
    }

    handleRemoveCondition(evt) {
        const { id, condId } = evt.currentTarget.dataset;
        this._rules = this._rules.map(r => r.id === id ? {
            ...r,
            additionalConditions: (r.additionalConditions || []).filter(c => c.id !== condId)
        } : r);
        this._emit();
    }

    handleConditionChange(evt) {
        const { id, condId, field } = evt.currentTarget.dataset;
        const value = (evt.detail && evt.detail.value !== undefined) ? evt.detail.value : evt.target.value;
        this._rules = this._rules.map(r => r.id === id ? {
            ...r,
            additionalConditions: (r.additionalConditions || []).map(c => c.id === condId ? { ...c, [field]: value } : c)
        } : r);
        this._emit();
    }

    _emit() {
        this.dispatchEvent(new CustomEvent('ruleupdated', { detail: { rules: this._rules } }));
    }
}