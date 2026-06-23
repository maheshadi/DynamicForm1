import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getFormSchema   from '@salesforce/apex/HR_FormRendererController.getFormSchema';
import submitFormApex  from '@salesforce/apex/HR_SubmissionService.submitForm';
import saveDraftApex   from '@salesforce/apex/HR_SubmissionService.saveDraft';
import { evaluateRules } from 'c/hrLogicEngine';

export default class HrFormRenderer extends NavigationMixin(LightningElement) {

    @api formApiName;      // undefined by default → wire won't fire until set
    @api recordId;
    @api submissionId;
    @api hideFooter = false;  // set by modal parents that supply their own footer

    _startTime = null;  // set when schema loads so duration reflects actual fill time

    @track _schema          = null;
    @track _logicBundle     = [];
    @track config           = {};
    @track fieldValues      = {};
    @track fieldVisibility  = {};
    @track fieldRequiredOverrides = {};
    @track fieldDisabledOverrides = {};
    @track isLoading        = true;
    @track hasError         = false;
    @track errorMessage     = '';
    @track isSubmitted      = false;
    @track isSubmitting     = false;
    @track showConfirmation = false;
    @track hasDraft         = false;

    // ─── Wire ─────────────────────────────────────────────────────────────────
    @wire(getFormSchema, { formApiName: '$formApiName' })
    wiredSchema({ data, error }) {
        if (data) {
            this._schema      = data.schema;
            this._logicBundle = data.logicBundle || [];
            this.config       = data.config || {};
            this._startTime   = Date.now();
            this._initVisibility();
            this.isLoading = false;
        } else if (error) {
            this.hasError    = true;
            this.errorMessage = 'Form unavailable. Please contact support.';
            this.isLoading   = false;
        }
    }

    // ─── Computed ─────────────────────────────────────────────────────────────
    get hasFormSelected() { return !!(this.formApiName && this.formApiName.trim()); }
    get isReady()        { return !this.isLoading && !this.hasError && !!this._schema; }
    get successMessage() { return this.config.successMessage || 'Your form has been submitted successfully.'; }

    get visibleSections() {
        if (!this._schema) return [];
        return (this._schema.sections || []).filter(sec =>
            this.fieldVisibility[sec.id] !== false
        );
    }

    get confirmationRows() {
        const rows = [];
        for (const sec of (this._schema.sections || [])) {
            for (const f of (sec.fields || [])) {
                const val = this.fieldValues[f.apiName];
                if (val !== undefined && val !== null && val !== '') {
                    rows.push({ label: f.label, value: String(val) });
                }
            }
        }
        return rows;
    }

    // ─── Handlers ─────────────────────────────────────────────────────────────
    handleValueChanged(evt) {
        const { apiName, value } = evt.detail;
        this.fieldValues = { ...this.fieldValues, [apiName]: value };
        this._runLogicEngine();
    }

    // ─── Public API (for modal parents) ──────────────────────────────────────
    @api
    async submit() { await this.handleSubmit(); }

    @api
    async saveDraft() { await this.handleSaveDraft(); }

    @api
    cancel() { this.handleCancel(); }

    // ─── Handlers ─────────────────────────────────────────────────────────────
    async handleSubmit() {
        if (!this._validateRequired()) return;
        if (this.config.requireConfirmation) {
            this.showConfirmation = true;
            return;
        }
        await this._doSubmit();
    }

    handleCancelConfirm() { this.showConfirmation = false; }
    async handleConfirmSubmit() { await this._doSubmit(); }

    async handleSaveDraft() {
        try {
            const id = await saveDraftApex({
                formApiName: this.formApiName,
                payloadJSON: JSON.stringify(this.fieldValues)
            });
            this.hasDraft = true;
            this._showToast('Draft saved.', 'success');
        } catch (e) {
            this._showToast(this._errMsg(e), 'error');
        }
    }

    handleCancel() {
        this.fieldValues = {};
        this._initVisibility();
    }

    // ─── Private ──────────────────────────────────────────────────────────────
    _initVisibility() {
        if (!this._schema) return;
        const vis = {};
        for (const sec of (this._schema.sections || [])) {
            vis[sec.id] = true;
            for (const f of (sec.fields || [])) vis[f.apiName] = true;
        }
        this.fieldVisibility = vis;
    }

    _runLogicEngine() {
        const actions = evaluateRules(this._logicBundle, this.fieldValues);
        const vis     = { ...this.fieldVisibility };
        const req     = { ...this.fieldRequiredOverrides };
        const dis     = { ...this.fieldDisabledOverrides };

        for (const a of actions) {
            const target = a.targetApiName;
            if (a.action === 'Show')          { vis[target] = true; }
            else if (a.action === 'Hide')     { vis[target] = false; }
            else if (a.action === 'Make_Required') { req[target] = true; }
            else if (a.action === 'Make_Optional') { req[target] = false; }
            else if (a.action === 'Enable')   { dis[target] = false; }
            else if (a.action === 'Disable')  { dis[target] = true; }
            else if (a.action === 'Set_Value') {
                this.fieldValues = { ...this.fieldValues, [target]: a.actionValue };
            }
        }
        this.fieldVisibility       = vis;
        this.fieldRequiredOverrides = req;
        this.fieldDisabledOverrides = dis;
    }

    _validateRequired() {
        let valid = true;
        for (const sec of (this._schema.sections || [])) {
            for (const f of (sec.fields || [])) {
                const isRequired = f.required || this.fieldRequiredOverrides[f.apiName];
                const isVisible  = this.fieldVisibility[f.apiName] !== false;
                if (isRequired && isVisible) {
                    const val = this.fieldValues[f.apiName];
                    if (val === undefined || val === null || val === '') {
                        this._showToast(`"${f.label}" is required.`, 'error');
                        valid = false;
                    }
                }
            }
        }
        return valid;
    }

    async _doSubmit() {
        this.isSubmitting = true;
        try {
            const durationSec = this._startTime ? Math.round((Date.now() - this._startTime) / 1000) : 0;
            await submitFormApex({
                formApiName: this.formApiName,
                payloadJSON: JSON.stringify(this.fieldValues),
                durationSec
            });
            this.isSubmitted = true;
            this.showConfirmation = false;
            if (this.config.onSubmitAction === 'Redirect_URL' && this.config.redirectUrl) {
                this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url: this.config.redirectUrl } });
            }
        } catch (e) {
            this._showToast(this._errMsg(e), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    _showToast(msg, variant) {
        const evt = new CustomEvent('hr_toast', { detail: { message: msg, variant }, bubbles: true, composed: true });
        this.dispatchEvent(evt);
    }

    _errMsg(e) { return e?.body?.message || e?.message || 'An unexpected error occurred.'; }
}