import { LightningElement, api } from 'lwc';

export default class HrFormField extends LightningElement {
    @api field      = {};
    @api value      = '';
    @api isRequired = false;
    @api isDisabled = false;

    get labelClass()    { return 'slds-text-body_small'; }
    get showRequired()  { return this.isRequired || !!(this.field && this.field.required); }
    get t()            { return (this.field && this.field.type) || ''; }
    get isText()       { return ['Text','Email','Phone','URL'].includes(this.t); }
    get isNumber()     { return ['Number','Currency'].includes(this.t); }
    get isDate()       { return ['Date','DateTime'].includes(this.t); }
    get isTextArea()   { return ['TextArea','RichText'].includes(this.t); }
    get isDropdown()   { return this.t === 'Dropdown'; }
    get isRadio()      { return this.t === 'Radio'; }
    get isCheckbox()   { return this.t === 'Checkbox'; }
    get isMultiSelect(){ return this.t === 'MultiSelect'; }
    get isLookup()     { return this.t === 'Lookup'; }
    get isCurrentUser(){ return this.t === 'CurrentUser'; }
    get isRecordField(){ return this.t === 'RecordField'; }
    get isFileUpload() { return this.t === 'FileUpload'; }
    get isInfoBox()    { return ['InfoBox','Instructions','Divider'].includes(this.t); }

    bubble(evt) {
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: evt.detail }));
    }
}