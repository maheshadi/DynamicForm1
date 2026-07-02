import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getFormSchema   from '@salesforce/apex/HR_FormRendererController.getFormSchema';
import submitFormApex  from '@salesforce/apex/HR_SubmissionService.submitForm';
import saveDraftApex   from '@salesforce/apex/HR_SubmissionService.saveDraft';
import getMyDraftsApex from '@salesforce/apex/HR_SubmissionService.getMyDrafts';
import { evaluateRules } from 'c/hrLogicEngine';

export default class HrFormRenderer extends NavigationMixin(LightningElement) {

    @api formApiName;
    @api recordId;
    @api submissionId;
    @api hideFooter = false;

    // Pass a schema object directly to bypass the wire (used by builder preview)
    _overrideSchema = null;
    @api
    get overrideSchema() { return this._overrideSchema; }
    set overrideSchema(val) {
        this._overrideSchema = val;
        if (val) {
            this._schema      = val;
            this._logicBundle = val.rules || [];
            this.config       = this._configFromSchema(val);
            this.isLoading    = false;
            this.hasError     = false;
            this._initDefaults();
            this._initVisibility();
        }
    }

    _startTime = null;
    _clientRequestId = null;

    @track _schema                = null;
    @track _logicBundle           = [];
    @track config                 = {};
    @track fieldValues            = {};
    @track fieldVisibility        = {};
    @track fieldRequiredOverrides = {};
    @track fieldDisabledOverrides = {};
    @track isLoading              = true;
    @track hasError               = false;
    @track errorMessage           = '';
    @track isSubmitted            = false;
    @track isSubmitting           = false;
    @track showConfirmation       = false;
    @track hasDraft               = false;
    @track draftAvailable         = false;

    _draftPayload = null;

    // ─── Wire ─────────────────────────────────────────────────────────────────
    @wire(getFormSchema, { formApiName: '$formApiName' })
    wiredSchema({ data, error }) {
        if (this._overrideSchema) return;   // builder preview: schema provided directly
        if (data) {
            this._schema      = data.schema;
            this._logicBundle = data.logicBundle || [];
            this.config       = data.config || {};
            this._startTime   = Date.now();
            this._initDefaults();
            this._initVisibility();
            this.isLoading = false;
            this._checkForDraft();
        } else if (error) {
            this.hasError     = true;
            this.errorMessage = 'Form unavailable. Please contact support.';
            this.isLoading    = false;
        }
    }

    // ─── Computed ─────────────────────────────────────────────────────────────
    get hasFormSelected() {
        return !!(this._overrideSchema) || !!(this.formApiName && this.formApiName.trim());
    }
    // Submit/saveDraft need an API name even when the schema is supplied directly
    // (builder & library preview pass override-schema); fall back to the schema's own.
    get _effectiveApiName() {
        return this.formApiName || (this._overrideSchema && this._overrideSchema.apiName) || null;
    }
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

    // ─── Public API ───────────────────────────────────────────────────────────
    @api async submit()    { await this.handleSubmit(); }
    @api async saveDraft() { await this.handleSaveDraft(); }
    @api       reset()     { this.handleReset(); }

    // ─── Form actions ──────────────────────────────────────────────────────────
    async handleSubmit() {
        if (!this._validateConstraints()) return;
        if (!this._validateRequired()) return;
        if (this.config.requireConfirmation) { this.showConfirmation = true; return; }
        await this._doSubmit();
    }

    // Constraint validation (pattern / min / max / length) across all rendered
    // sections — each invalid input shows its own inline error message.
    _validateConstraints() {
        let allValid = true;
        this.template.querySelectorAll('c-hr-form-section').forEach(sec => {
            if (sec.reportValidity && !sec.reportValidity()) allValid = false;
        });
        if (!allValid) {
            this._showToast('Please fix the highlighted field errors before submitting.', 'error');
        }
        return allValid;
    }

    handleCancelConfirm()        { this.showConfirmation = false; }
    async handleConfirmSubmit()  { await this._doSubmit(); }

    async handleSaveDraft() {
        try {
            await saveDraftApex({
                formApiName: this._effectiveApiName,
                payloadJSON: JSON.stringify(this.fieldValues)
            });
            this.hasDraft = true;
            this._showToast('Draft saved.', 'success');
        } catch (e) {
            this._showToast(this._errMsg(e), 'error');
        }
    }

    handleReset() {
        this._initDefaults();
        this._initVisibility();
        this.fieldRequiredOverrides = {};
        this.fieldDisabledOverrides = {};
        this.showConfirmation       = false;
    }

    // ─── Draft resume ─────────────────────────────────────────────────────────
    // Best-effort: offers to restore the user's saved draft for this form.
    // Only for live (non-preview) renders of forms that allow draft save.
    async _checkForDraft() {
        if (this._overrideSchema || !this.formApiName) return;
        if (!this.config || !this.config.allowDraftSave) return;
        try {
            const drafts = await getMyDraftsApex({ formApiName: this.formApiName });
            if (drafts && drafts.length > 0) {
                this._draftPayload  = drafts[0].HR_Payload_JSON__c;
                this.draftAvailable = true;
            }
        } catch (e) { /* draft resume is optional — never block the form */ }
    }

    handleResumeDraft() {
        try {
            const saved = JSON.parse(this._draftPayload || '{}');
            this.fieldValues = { ...this.fieldValues, ...saved };
            this.hasDraft = true;
            this._runLogicEngine();
        } catch (e) { /* corrupt payload — start fresh instead */ }
        this.draftAvailable = false;
    }

    handleDismissDraft() { this.draftAvailable = false; }

    // ─── Private ──────────────────────────────────────────────────────────────
    _configFromSchema(schema) {
        return {
            allowDraftSave:      schema.allowDraftSave,
            requireConfirmation: schema.requireConfirmation,
            successMessage:      schema.successMessage,
            redirectUrl:         schema.redirectUrl,
            onSubmitAction:      schema.onSubmitAction
        };
    }

    _initDefaults() {
        if (!this._schema) return;
        const defaults = {};
        for (const sec of (this._schema.sections || [])) {
            for (const f of (sec.fields || [])) {
                if (f.defaultValue !== undefined && f.defaultValue !== null && f.defaultValue !== '') {
                    defaults[f.apiName] = f.defaultValue;
                }
            }
        }
        this.fieldValues = defaults;
        // New fill session → new idempotency key. Retries of the SAME session reuse
        // the key so the server can dedupe double-clicks / network replays.
        this._clientRequestId = this._newRequestId();
    }

    _newRequestId() {
        try {
            if (window.crypto && window.crypto.randomUUID) return window.crypto.randomUUID();
        } catch (e) { /* fall through */ }
        return 'req_' + Date.now() + '_' + Math.random().toString(36).slice(2, 12);
    }

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
        const vis = { ...this.fieldVisibility };
        const req = { ...this.fieldRequiredOverrides };
        const dis = { ...this.fieldDisabledOverrides };

        for (const a of actions) {
            const t = a.targetApiName;
            if      (a.action === 'Show')          vis[t] = true;
            else if (a.action === 'Hide')          vis[t] = false;
            else if (a.action === 'Make_Required') req[t] = true;
            else if (a.action === 'Make_Optional') req[t] = false;
            else if (a.action === 'Enable')        dis[t] = false;
            else if (a.action === 'Disable')       dis[t] = true;
            else if (a.action === 'Set_Value')     this.fieldValues = { ...this.fieldValues, [t]: a.actionValue };
        }
        this.fieldVisibility        = vis;
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
                formApiName: this._effectiveApiName,
                payloadJSON: JSON.stringify(this.fieldValues),
                durationSec,
                clientRequestId: this._clientRequestId
            });
            this.isSubmitted      = true;
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
        this.dispatchEvent(new CustomEvent('hr_toast', { detail: { message: msg, variant }, bubbles: true, composed: true }));
    }

    _errMsg(e) { return e?.body?.message || e?.message || 'An unexpected error occurred.'; }
}