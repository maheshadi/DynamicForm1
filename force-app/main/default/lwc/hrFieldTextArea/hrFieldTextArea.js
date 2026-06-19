import { LightningElement, api } from 'lwc';
export default class HrFieldTextArea extends LightningElement {
    @api field = {}; @api value = ''; @api isDisabled = false;
    get isRichText() { return this.field.type === 'RichText'; }
    handleChange(evt) {
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: evt.target.value } }));
    }
}