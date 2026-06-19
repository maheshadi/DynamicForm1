import { LightningElement, api } from 'lwc';
export default class HrFieldCheckbox extends LightningElement {
    @api field = {}; @api value = false; @api isDisabled = false;
    get isChecked() { return this.value === true || this.value === 'true'; }
    handleChange(evt) {
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: evt.target.checked } }));
    }
}