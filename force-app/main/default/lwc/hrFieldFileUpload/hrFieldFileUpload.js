import { LightningElement, api } from 'lwc';
export default class HrFieldFileUpload extends LightningElement {
    @api field        = {};
    @api submissionId = null;
    @api isDisabled   = false;

    get acceptedFormats() {
        if (!this.field.allowedFileTypes) return null;
        try { return JSON.parse(this.field.allowedFileTypes); }
        catch(e) { return null; }
    }
    handleUpload(evt) {
        const files = evt.detail.files;
        const ids   = files.map(f => f.documentId).join(',');
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: ids } }));
    }
}