import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getHRBuilderConfig from '@salesforce/apex/HR_FormRendererController.getFormSchema';
import saveFormApex      from '@salesforce/apex/HR_FormSchemaService.saveForm';
import publishFormApex   from '@salesforce/apex/HR_PublishService.publishForm';
import hasAdminPermission from '@salesforce/customPermission/HR_Form_Admin';

const AUTO_SAVE_DEFAULT_SEC = 30;
const MAX_SCHEMA_CHARS      = 131072;

export default class HrFormBuilder extends LightningElement {

    // ─── State ────────────────────────────────────────────────────────────────
    @track formSchema = {
        id: null, name: 'Untitled Form', apiName: '', category: 'General',
        status: 'Draft', sections: [], rules: [],
        targetObjectApi: 'Case', deploymentTarget: 'LWC_Component',
        onSubmitAction: 'Show_Message', successMessage: '',
        redirectUrl: '', allowDraftSave: true, requireConfirmation: false,
        tags: '', description: ''
    };

    @track selectedFieldId    = null;
    @track selectedSectionId  = null;
    @track showRulesEditor    = false;
    @track isSaving           = false;
    @track isPublishing       = false;
    @track toastMessage       = null;
    @track toastVariant       = 'success';

    _autoSaveTimer = null;
    _autoSaveIntervalSec = AUTO_SAVE_DEFAULT_SEC;

    // ─── Page reference (reads formApiName from URL state) ───────────────────
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (pageRef && pageRef.state && pageRef.state.formApiName) {
            this._loadForm(pageRef.state.formApiName);
        }
    }

    connectedCallback() {
        this._startAutoSave();
    }

    disconnectedCallback() {
        if (this._autoSaveTimer) clearInterval(this._autoSaveTimer);
    }

    // ─── Computed ─────────────────────────────────────────────────────────────
    get canPublish()           { return hasAdminPermission; }
    get statusLabel()          { return this.formSchema.status || 'Draft'; }
    get saveDraftLabel()       { return this.isSaving ? 'Saving…' : 'Save Draft'; }
    get publishLabel()         { return this.isPublishing ? 'Publishing…' : 'Publish'; }
    get schemaCharCount()      { return JSON.stringify(this.formSchema).length; }
    get maxSchemaChars()       { return MAX_SCHEMA_CHARS; }
    get schemaUsagePercent()   { return Math.round((this.schemaCharCount / MAX_SCHEMA_CHARS) * 100); }
    get schemaUsageVariant()   { return this.schemaUsagePercent > 80 ? 'warning' : 'base'; }
    get toastIcon()            { return 'utility:' + (this.toastVariant === 'success' ? 'success' : 'error'); }

    get selectedField() {
        if (!this.selectedFieldId) return null;
        for (const sec of (this.formSchema.sections || [])) {
            const f = (sec.fields || []).find(f => f.id === this.selectedFieldId);
            if (f) return f;
        }
        return null;
    }

    get selectedSection() {
        if (!this.selectedSectionId) return null;
        return (this.formSchema.sections || []).find(s => s.id === this.selectedSectionId);
    }

    // ─── Event handlers ───────────────────────────────────────────────────────
    handleFieldAdded(evt) {
        const { fieldType, typeApiName } = evt.detail;
        const targetSectionId = this.selectedSectionId
            || (this.formSchema.sections.length > 0 ? this.formSchema.sections[0].id : null);

        if (!targetSectionId) {
            this._toast('Add a section first before dropping fields.', 'warning');
            return;
        }

        const newField = {
            id:           'f_' + Date.now(),
            apiName:      typeApiName + '_' + Date.now(),
            label:        this._titleCase(typeApiName.replace(/_/g, ' ')),
            type:         fieldType,
            required:     false,
            readOnly:     false,
            columnSpan:   'Half',
            placeholder:  '',
            helpText:     '',
            defaultValue: ''
        };

        this.formSchema = this._immutableUpdate(this.formSchema, schema => {
            const sec = schema.sections.find(s => s.id === targetSectionId);
            if (sec) sec.fields = [...(sec.fields || []), newField];
        });
        this.selectedFieldId = newField.id;
    }

    handleSectionAdded() {
        const newSection = {
            id:       's_' + Date.now(),
            title:    'New Section',
            columns:  2,
            collapsible: true,
            initiallyCollapsed: false,
            helpText: '',
            fields:   []
        };
        this.formSchema = this._immutableUpdate(this.formSchema, s => {
            s.sections = [...s.sections, newSection];
        });
        this.selectedSectionId = newSection.id;
        this.selectedFieldId   = null;
    }

    handleFieldSelected(evt)   { this.selectedFieldId = evt.detail.fieldId; this.selectedSectionId = null; }
    handleSectionSelected(evt) { this.selectedSectionId = evt.detail.sectionId; this.selectedFieldId = null; }

    handleFieldRemoved(evt) {
        const { fieldId } = evt.detail;
        this.formSchema = this._immutableUpdate(this.formSchema, schema => {
            schema.sections.forEach(sec => {
                sec.fields = (sec.fields || []).filter(f => f.id !== fieldId);
            });
        });
        if (this.selectedFieldId === fieldId) this.selectedFieldId = null;
    }

    handleSectionRemoved(evt) {
        const { sectionId } = evt.detail;
        this.formSchema = this._immutableUpdate(this.formSchema, schema => {
            schema.sections = schema.sections.filter(s => s.id !== sectionId);
        });
        if (this.selectedSectionId === sectionId) this.selectedSectionId = null;
    }

    handleFieldReorder(evt)   { this._applyReorder(evt.detail); }
    handleSectionReorder(evt) { this._applyReorder(evt.detail); }

    handlePropertyChanged(evt) {
        const { targetId, targetType, changes } = evt.detail;
        this.formSchema = this._immutableUpdate(this.formSchema, schema => {
            if (targetType === 'form') {
                Object.assign(schema, changes);
            } else if (targetType === 'section') {
                const sec = schema.sections.find(s => s.id === targetId);
                if (sec) Object.assign(sec, changes);
            } else if (targetType === 'field') {
                schema.sections.forEach(sec => {
                    const f = (sec.fields || []).find(f => f.id === targetId);
                    if (f) Object.assign(f, changes);
                });
            }
        });
    }

    handleRuleUpdated(evt) {
        this.formSchema = this._immutableUpdate(this.formSchema, s => {
            s.rules = evt.detail.rules;
        });
    }

    handleRulesClick()  { this.showRulesEditor = true; }
    handleCloseRules()  { this.showRulesEditor = false; }
    handlePreview()     { this._toast('Preview mode coming soon.', 'info'); }

    async handleSaveDraft() {
        this.isSaving = true;
        try {
            await this._saveDraft();
            this._toast('Draft saved successfully.', 'success');
        } catch (e) {
            this._toast('Save failed: ' + this._errorMessage(e), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handlePublish() {
        this.isPublishing = true;
        try {
            await this._saveDraft();
            await publishFormApex({ formApiName: this.formSchema.apiName });
            this.formSchema = this._immutableUpdate(this.formSchema, s => { s.status = 'Published'; });
            this._toast('Form published successfully!', 'success');
        } catch (e) {
            this._toast('Publish failed: ' + this._errorMessage(e), 'error');
        } finally {
            this.isPublishing = false;
        }
    }

    // ─── Private helpers ──────────────────────────────────────────────────────
    async _loadForm(apiName) {
        try {
            const data = await getHRBuilderConfig({ formApiName: apiName });
            if (data && data.schema) {
                this.formSchema = { ...data.schema, apiName };
            }
        } catch (e) {
            this._toast('Could not load form: ' + this._errorMessage(e), 'error');
        }
    }

    async _saveDraft() {
        return saveFormApex({
            formData: JSON.stringify({
                id:                  this.formSchema.id,
                name:                this.formSchema.name,
                apiName:             this.formSchema.apiName,
                category:            this.formSchema.category,
                description:         this.formSchema.description,
                tags:                this.formSchema.tags,
                schemaJSON:          JSON.stringify(this.formSchema),
                targetObjectApi:     this.formSchema.targetObjectApi,
                deploymentTarget:    this.formSchema.deploymentTarget,
                onSubmitAction:      this.formSchema.onSubmitAction,
                successMessage:      this.formSchema.successMessage,
                redirectUrl:         this.formSchema.redirectUrl,
                allowDraftSave:      this.formSchema.allowDraftSave,
                requireConfirmation: this.formSchema.requireConfirmation,
                recordTypeDevName:   this.formSchema.recordTypeDevName
            })
        });
    }

    _startAutoSave() {
        if (this._autoSaveTimer) clearInterval(this._autoSaveTimer);
        this._autoSaveTimer = setInterval(() => {
            if (!this.isSaving && this.formSchema.apiName) {
                this._saveDraft().catch(() => {});
            }
        }, this._autoSaveIntervalSec * 1000);
    }

    _immutableUpdate(schema, mutator) {
        const copy = JSON.parse(JSON.stringify(schema));
        mutator(copy);
        return copy;
    }

    _applyReorder({ items, parentId, type }) {
        this.formSchema = this._immutableUpdate(this.formSchema, schema => {
            if (type === 'section') {
                schema.sections = items;
            } else if (type === 'field') {
                const sec = schema.sections.find(s => s.id === parentId);
                if (sec) sec.fields = items;
            }
        });
    }

    _toast(message, variant = 'success') {
        this.toastMessage = message;
        this.toastVariant = variant;
        setTimeout(() => { this.toastMessage = null; }, 4000);
    }

    _errorMessage(e) {
        return e && e.body && e.body.message ? e.body.message : (e.message || 'Unknown error');
    }

    _titleCase(str) {
        return str.replace(/\b\w/g, c => c.toUpperCase());
    }
}