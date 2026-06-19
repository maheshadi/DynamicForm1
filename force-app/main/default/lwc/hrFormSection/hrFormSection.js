import { LightningElement, api, track } from 'lwc';

export default class HrFormSection extends LightningElement {
    @api section                 = {};
    @api fieldValues             = {};
    @api fieldVisibility         = {};
    @api fieldRequiredOverrides  = {};
    @api fieldDisabledOverrides  = {};

    @track _collapsed = false;

    connectedCallback() {
        this._collapsed = !!this.section.initiallyCollapsed;
    }

    get isCollapsed()  { return this._collapsed; }
    get chevronIcon()  { return this._collapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get headerClass()  { return `hr-section-header${this.section.collapsible ? ' hr-collapsible' : ''}`; }
    get fieldsClass()  {
        const cols = this.section.columns || 2;
        return `slds-card__body slds-p-around_small slds-grid slds-wrap slds-gutters_x-small hr-cols-${cols}`;
    }

    get visibleFields() {
        return (this.section.fields || []).filter(f =>
            f.isActive !== false && this.fieldVisibility[f.apiName] !== false
        );
    }

    get enrichedVisibleFields() {
        return (this.section.fields || [])
            .filter(f => f.isActive !== false && this.fieldVisibility[f.apiName] !== false)
            .map(f => ({
                ...f,
                wrapClass: f.columnSpan === 'Full'
                    ? 'slds-col slds-size_1-of-1 slds-m-bottom_small'
                    : 'slds-col slds-size_1-of-2 slds-m-bottom_small',
                fieldValue: this.fieldValues[f.apiName] != null ? this.fieldValues[f.apiName] : '',
                fieldIsRequired: !!(f.required || this.fieldRequiredOverrides[f.apiName]),
                fieldIsDisabled: !!this.fieldDisabledOverrides[f.apiName]
            }));
    }

    fieldWrapClass(field) {
        return field.columnSpan === 'Full' ? 'slds-col slds-size_1-of-1 slds-m-bottom_small'
                                          : 'slds-col slds-size_1-of-2 slds-m-bottom_small';
    }
    getFieldValue(apiName) { return this.fieldValues[apiName] ?? ''; }
    isRequired(field)  { return field.required || !!this.fieldRequiredOverrides[field.apiName]; }
    isDisabled(apiName){ return !!this.fieldDisabledOverrides[apiName]; }

    handleToggle() {
        if (this.section.collapsible) this._collapsed = !this._collapsed;
    }
    handleValueChanged(evt) {
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: evt.detail }));
    }
}