import { LightningElement, api } from 'lwc';
export default class HrFieldDate extends LightningElement {
    @api field = {}; @api value = ''; @api isDisabled = false;
    get inputType() { return this.field.type === 'DateTime' ? 'datetime-local' : 'date'; }
    handleChange(evt) {
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: evt.target.value } }));
    }
}