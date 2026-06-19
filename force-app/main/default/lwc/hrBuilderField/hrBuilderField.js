import { LightningElement, api } from 'lwc';

const TYPE_ICONS = {
    Text:'utility:text', Number:'utility:number_input', Currency:'utility:currency',
    Date:'utility:date_input', DateTime:'utility:clock', Email:'utility:email',
    Phone:'utility:call', URL:'utility:link', TextArea:'utility:textarea',
    RichText:'utility:richtextbulletedlist', Dropdown:'utility:picklist',
    Radio:'utility:record', Checkbox:'utility:check', MultiSelect:'utility:multi_picklist',
    Lookup:'utility:search', CurrentUser:'utility:user', RecordField:'utility:record_lookup',
    FileUpload:'utility:upload', InfoBox:'utility:info', Instructions:'utility:description',
    Divider:'utility:divider'
};

export default class HrBuilderField extends LightningElement {
    @api field      = {};
    @api isSelected = false;

    get fieldClass() {
        return `hr-builder-field slds-box slds-box_xx-small slds-m-bottom_xx-small${this.isSelected ? ' hr-selected' : ''}`;
    }
    get fieldIcon() { return TYPE_ICONS[this.field.type] || 'utility:text'; }

    handleClick(evt) {
        evt.stopPropagation();
        this.dispatchEvent(new CustomEvent('fieldselected', { detail: { fieldId: this.field.id } }));
    }
    handleRemove(evt) {
        evt.stopPropagation();
        this.dispatchEvent(new CustomEvent('fieldremoved', { detail: { fieldId: this.field.id } }));
    }
    handleDragStart(evt) {
        evt.dataTransfer.setData('fieldId',  this.field.id);
        evt.dataTransfer.effectAllowed = 'move';
        this.dispatchEvent(new CustomEvent('fielddragstart', { detail: { fieldId: this.field.id } }));
    }
    handleDragOver(evt) { evt.preventDefault(); evt.dataTransfer.dropEffect = 'move'; }
    handleDrop(evt) {
        evt.preventDefault();
        this.dispatchEvent(new CustomEvent('fielddrop', { detail: { fieldId: this.field.id } }));
    }
}