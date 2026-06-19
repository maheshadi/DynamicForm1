import { LightningElement } from 'lwc';

const PALETTE_GROUPS = [
    { name: 'Input Fields', types: [
        { fieldType: 'Text',      typeApi: 'text_input',   label: 'Text',        icon: 'utility:text' },
        { fieldType: 'Number',    typeApi: 'number_input', label: 'Number',      icon: 'utility:number_input' },
        { fieldType: 'Currency',  typeApi: 'currency',     label: 'Currency',    icon: 'utility:currency' },
        { fieldType: 'Date',      typeApi: 'date_picker',  label: 'Date',        icon: 'utility:date_input' },
        { fieldType: 'DateTime',  typeApi: 'datetime',     label: 'Date & Time', icon: 'utility:clock' },
        { fieldType: 'Email',     typeApi: 'email',        label: 'Email',       icon: 'utility:email' },
        { fieldType: 'Phone',     typeApi: 'phone',        label: 'Phone',       icon: 'utility:call' },
        { fieldType: 'URL',       typeApi: 'url',          label: 'URL',         icon: 'utility:link' },
        { fieldType: 'TextArea',  typeApi: 'text_area',    label: 'Text Area',   icon: 'utility:textarea' },
        { fieldType: 'RichText',  typeApi: 'rich_text',    label: 'Rich Text',   icon: 'utility:richtextbulletedlist' }
    ]},
    { name: 'Selection', types: [
        { fieldType: 'Dropdown',    typeApi: 'dropdown',     label: 'Dropdown',    icon: 'utility:picklist' },
        { fieldType: 'Radio',       typeApi: 'radio',        label: 'Radio',       icon: 'utility:record' },
        { fieldType: 'Checkbox',    typeApi: 'checkbox',     label: 'Checkbox',    icon: 'utility:check' },
        { fieldType: 'MultiSelect', typeApi: 'multi_select', label: 'Multi-Select',icon: 'utility:multi_picklist' }
    ]},
    { name: 'Salesforce', types: [
        { fieldType: 'Lookup',      typeApi: 'lookup',       label: 'Lookup',      icon: 'utility:search' },
        { fieldType: 'CurrentUser', typeApi: 'current_user', label: 'Current User',icon: 'utility:user' },
        { fieldType: 'RecordField', typeApi: 'record_field', label: 'Record Field',icon: 'utility:record_lookup' },
        { fieldType: 'FileUpload',  typeApi: 'file_upload',  label: 'File Upload', icon: 'utility:upload' }
    ]},
    { name: 'Layout', types: [
        { fieldType: 'InfoBox',      typeApi: 'info_box',     label: 'Info Box',    icon: 'utility:info' },
        { fieldType: 'Instructions', typeApi: 'instructions', label: 'Instructions',icon: 'utility:description' },
        { fieldType: 'Divider',      typeApi: 'divider',      label: 'Divider',     icon: 'utility:divider' }
    ]}
];

export default class HrBuilderPalette extends LightningElement {
    get paletteGroups() { return PALETTE_GROUPS; }

    handleDragStart(evt) {
        const tile = evt.currentTarget;
        evt.dataTransfer.setData('fieldType', tile.dataset.type);
        evt.dataTransfer.setData('typeApiName', tile.dataset.api);
        evt.dataTransfer.effectAllowed = 'copy';
    }
    handleClick(evt) {
        const tile = evt.currentTarget;
        this.dispatchEvent(new CustomEvent('hr_fieldadded', {
            bubbles: true, composed: true,
            detail: { fieldType: tile.dataset.type, typeApiName: tile.dataset.api }
        }));
    }
}