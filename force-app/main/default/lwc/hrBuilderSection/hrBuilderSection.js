import { LightningElement, api, track } from 'lwc';

export default class HrBuilderSection extends LightningElement {
    @api section         = {};
    @api selectedFieldId  = null;
    @api selectedSectionId = null;

    @track _collapsed = false;

    get isCollapsed()   { return this._collapsed; }
    get collapseIcon()  { return this._collapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get fieldCount()    { return (this.section.fields || []).length; }
    get isEmpty()       { return this.fieldCount === 0; }
    get fieldsGridClass() {
        const cols = this.section.columns || 2;
        return `hr-fields-grid slds-grid slds-wrap slds-gutters_x-small slds-p-around_x-small hr-cols-${cols}`;
    }
    get sectionClass() {
        const isSelected = this.selectedSectionId === this.section.id;
        return `hr-builder-section slds-box slds-box_x-small slds-m-bottom_small${isSelected ? ' hr-selected' : ''}`;
    }
    get enrichedFields() {
        return (this.section.fields || []).map(f => ({
            ...f,
            isSelected: this.selectedFieldId === f.id
        }));
    }

    isFieldSelected(fieldId) { return this.selectedFieldId === fieldId; }

    handleSectionClick(evt) {
        evt.stopPropagation();
        this.dispatchEvent(new CustomEvent('sectionselected', {
            detail: { sectionId: this.section.id }
        }));
    }
    handleToggleCollapse(evt) { evt.stopPropagation(); this._collapsed = !this._collapsed; }
    handleRemoveSection(evt)  {
        evt.stopPropagation();
        this.dispatchEvent(new CustomEvent('sectionremoved', { detail: { sectionId: this.section.id } }));
    }
    handleFieldSelected(evt)  { this.dispatchEvent(new CustomEvent('fieldselected',  { detail: evt.detail })); }
    handleFieldRemoved(evt)   { this.dispatchEvent(new CustomEvent('fieldremoved',   { detail: evt.detail })); }

    // Section-level drag (reorder sections)
    handleSectionDragStart(evt) {
        evt.dataTransfer.setData('sectionId', this.section.id);
        evt.dataTransfer.effectAllowed = 'move';
    }
    handleSectionDragOver(evt) { evt.preventDefault(); evt.dataTransfer.dropEffect = 'move'; }
    handleSectionDrop(evt) {
        evt.preventDefault();
        const draggedSectionId = evt.dataTransfer.getData('sectionId');
        if (draggedSectionId && draggedSectionId !== this.section.id) {
            this.dispatchEvent(new CustomEvent('sectiondrop', {
                detail: { draggedId: draggedSectionId, targetId: this.section.id }
            }));
        }
        // Field drop from palette onto section
        const fieldType   = evt.dataTransfer.getData('fieldType');
        const typeApiName = evt.dataTransfer.getData('typeApiName');
        if (fieldType) {
            this.dispatchEvent(new CustomEvent('hr_fieldadded', {
                bubbles: true, composed: true,
                detail: { fieldType, typeApiName, sectionId: this.section.id }
            }));
        }
    }
    // Field reorder within section
    handleFieldDragStart(evt) {
        evt.dataTransfer.setData('fieldId', evt.detail.fieldId);
        evt.dataTransfer.setData('sectionId', this.section.id);
    }
    handleFieldDrop(evt) {
        const draggedFieldId = evt.dataTransfer.getData('fieldId');
        const targetFieldId  = evt.detail.fieldId;
        const sourceSectionId = evt.dataTransfer.getData('sectionId');
        if (!draggedFieldId || draggedFieldId === targetFieldId) return;
        if (sourceSectionId !== this.section.id) return; // cross-section move not supported

        const fields = [...(this.section.fields || [])];
        const dragIdx  = fields.findIndex(f => f.id === draggedFieldId);
        const dropIdx  = fields.findIndex(f => f.id === targetFieldId);
        if (dragIdx === -1 || dropIdx === -1) return;
        const [moved] = fields.splice(dragIdx, 1);
        fields.splice(dropIdx, 0, moved);

        this.dispatchEvent(new CustomEvent('fieldreorder', {
            detail: { type: 'field', parentId: this.section.id, items: fields }
        }));
    }
}