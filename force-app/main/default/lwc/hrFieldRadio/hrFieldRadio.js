import { LightningElement, api } from 'lwc';
export default class HrFieldRadio extends LightningElement {
    @api field = {}; @api value = ''; @api isDisabled = false;
    get options() {
        try { return JSON.parse(this.field.picklistValuesJSON || '[]').map(v => ({ label: v.label, value: v.value })); }
        catch(e) { return []; }
    }
    handleChange(evt) {
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: evt.detail.value } }));
    }
}