import { LightningElement, api } from 'lwc';

export default class HrBuilderCanvas extends LightningElement {
    @api formSchema      = {};
    @api selectedFieldId   = null;
    @api selectedSectionId = null;

    get sections()    { return (this.formSchema && this.formSchema.sections) || []; }
    get hasSections() { return this.sections.length > 0; }

    // Drag-over: allow drop
    handleDragOver(evt) {
        evt.preventDefault();
        evt.dataTransfer.dropEffect = 'copy';
    }

    // Drop from palette onto canvas (not on a section) → dispatch hr_fieldadded
    handleDrop(evt) {
        evt.preventDefault();
        const fieldType  = evt.dataTransfer.getData('fieldType');
        const typeApiName = evt.dataTransfer.getData('typeApiName');
        if (fieldType && typeApiName) {
            this.dispatchEvent(new CustomEvent('hr_fieldadded', {
                bubbles: true, composed: true,
                detail: { fieldType, typeApiName }
            }));
        }
    }

    handleFieldSelected(evt)  { this.dispatchEvent(new CustomEvent('fieldselected',  { bubbles: false, detail: evt.detail })); }
    handleSectionSelected(evt){ this.dispatchEvent(new CustomEvent('sectionselected',{ bubbles: false, detail: evt.detail })); }
    handleFieldRemoved(evt)   { this.dispatchEvent(new CustomEvent('fieldremoved',   { bubbles: false, detail: evt.detail })); }
    handleSectionRemoved(evt) { this.dispatchEvent(new CustomEvent('sectionremoved', { bubbles: false, detail: evt.detail })); }
    handleFieldReorder(evt)   { this.dispatchEvent(new CustomEvent('fieldreorder',   { bubbles: false, detail: evt.detail })); }
    handleSectionDrop(evt)    { this.dispatchEvent(new CustomEvent('sectionreorder', { bubbles: false, detail: evt.detail })); }

    handleAddSection() {
        this.dispatchEvent(new CustomEvent('sectionadded', { bubbles: false }));
    }
}