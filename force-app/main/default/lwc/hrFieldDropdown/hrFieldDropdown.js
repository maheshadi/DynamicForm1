import { LightningElement, api, wire, track } from 'lwc';
import getPicklistValues from '@salesforce/apex/HR_FormRendererController.getPicklistValues';
export default class HrFieldDropdown extends LightningElement {
    @api field = {}; @api value = ''; @api isDisabled = false;
    @track _dynamicOptions = null;

    @wire(getPicklistValues, { objectApiName: '$sfPicklistObject', fieldApiName: '$sfPicklistField' })
    wiredPicklist({ data }) { if (data) this._dynamicOptions = data.map(v => ({ label: v.label, value: v.value })); }

    get sfPicklistObject() { return this.field.picklistSource === 'SF_Picklist_Field' ? this.field.sfPicklistField?.split('.')[0] : null; }
    get sfPicklistField()  { return this.field.picklistSource === 'SF_Picklist_Field' ? this.field.sfPicklistField?.split('.')[1] : null; }
    get placeholder() { return this.field.placeholder || '-- Select --'; }
    get options() {
        if (this._dynamicOptions) return this._dynamicOptions;
        try {
            const vals = JSON.parse(this.field.picklistValuesJSON || '[]');
            return vals.map(v => ({ label: v.label, value: v.value }));
        } catch (e) { return []; }
    }
    handleChange(evt) {
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: evt.target.value } }));
    }
}