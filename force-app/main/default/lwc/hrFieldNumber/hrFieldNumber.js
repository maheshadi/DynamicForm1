import { LightningElement, api } from 'lwc';
export default class HrFieldNumber extends LightningElement {
    @api field = {}; @api value = null; @api isDisabled = false;
    get formatter() { return this.field.type === 'Currency' ? 'currency' : 'decimal'; }
    handleChange(evt) {
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: evt.target.value } }));
    }
}