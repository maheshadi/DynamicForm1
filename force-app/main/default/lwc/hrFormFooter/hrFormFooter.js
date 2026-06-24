import { LightningElement, api } from 'lwc';
export default class HrFormFooter extends LightningElement {
    @api allowDraftSave = false;
    @api isSubmitting   = false;
    @api hasDraft       = false;

    handleSubmit()    { this.dispatchEvent(new CustomEvent('submit'));    }
    handleSaveDraft() { this.dispatchEvent(new CustomEvent('savedraft')); }
    handleReset()     { this.dispatchEvent(new CustomEvent('reset'));     }
}