import { LightningElement, api } from 'lwc';
export default class HrFieldText extends LightningElement {
    @api field = {}; @api value = ''; @api isDisabled = false;
    get inputType() {
        const t = this.field.type;
        if (t === 'Email') return 'email';
        if (t === 'Phone') return 'tel';
        if (t === 'URL')   return 'url';
        return 'text';
    }
    handleChange(evt) {
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: evt.target.value } }));
    }
}