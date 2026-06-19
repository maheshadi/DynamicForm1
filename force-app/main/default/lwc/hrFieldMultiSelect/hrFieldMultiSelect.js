import { LightningElement, api } from 'lwc';
export default class HrFieldMultiSelect extends LightningElement {
    @api field = {}; @api value = ''; @api isDisabled = false;
    get options() {
        try { return JSON.parse(this.field.picklistValuesJSON || '[]').map(v => ({ label: v.label, value: v.value })); }
        catch(e) { return []; }
    }
    get selectedValues() {
        if (!this.value) return [];
        return Array.isArray(this.value) ? this.value : this.value.split(';');
    }
    handleChange(evt) {
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: evt.detail.value.join(';') } }));
    }
}