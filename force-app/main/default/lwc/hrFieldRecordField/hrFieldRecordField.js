import { LightningElement, api } from 'lwc';
export default class HrFieldRecordField extends LightningElement {
    @api field    = {};
    @api recordId = null;
    get fields()  { return this.field.sfFieldApi ? [this.field.sfFieldApi] : []; }
}