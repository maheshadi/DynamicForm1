import { LightningElement, api } from 'lwc';

export default class HrBuilderProperties extends LightningElement {
    @api selectedField   = null;
    @api selectedSection = null;
    @api formSchema      = {};

    get hasSelection()      { return this.isFieldSelected || this.isSectionSelected || this.isFormSelected; }
    get isFieldSelected()   { return !!this.selectedField; }
    get isSectionSelected() { return !this.selectedField && !!this.selectedSection; }
    get isFormSelected()    { return !this.selectedField && !this.selectedSection; }
    get selectedSectionColumns() { return String(this.selectedSection?.columns || '2'); }

    get categoryOptions() {
        return ['Termination','Onboarding','Leave','Compensation','Transfer','Performance','Benefits','General','Other']
            .map(c => ({ label: c, value: c }));
    }
    get submitActionOptions() {
        return [
            { label: 'Show Message',    value: 'Show_Message' },
            { label: 'Redirect URL',    value: 'Redirect_URL' },
            { label: 'Launch Flow',     value: 'Launch_Flow'  },
            { label: 'Close Modal',     value: 'Close_Modal'  }
        ];
    }
    get columnOptions() { return [{ label: '1 Column', value: '1' }, { label: '2 Columns', value: '2' }]; }
    get spanOptions()   { return [{ label: 'Half (1 col)', value: 'Half' }, { label: 'Full (2 cols)', value: 'Full' }]; }

    _dispatch(targetId, targetType, changes) {
        this.dispatchEvent(new CustomEvent('propertychanged', { detail: { targetId, targetType, changes } }));
    }

    handleFormChange(evt)    { this._dispatch(null, 'form',    { [evt.target.dataset.field]: evt.target.value }); }
    handleFormToggle(evt)    { this._dispatch(null, 'form',    { [evt.target.dataset.field]: evt.target.checked }); }
    handleSectionChange(evt) {
        const val = evt.target.dataset.field === 'columns' ? Number(evt.target.value) : evt.target.value;
        this._dispatch(this.selectedSection.id, 'section', { [evt.target.dataset.field]: val });
    }
    handleSectionToggle(evt) { this._dispatch(this.selectedSection.id, 'section', { [evt.target.dataset.field]: evt.target.checked }); }
    handleFieldChange(evt)   { this._dispatch(this.selectedField.id, 'field', { [evt.target.dataset.field]: evt.target.value }); }
    handleFieldToggle(evt)   { this._dispatch(this.selectedField.id, 'field', { [evt.target.dataset.field]: evt.target.checked }); }
    handleRulesClick()       { this.dispatchEvent(new CustomEvent('rulesclick')); }
}