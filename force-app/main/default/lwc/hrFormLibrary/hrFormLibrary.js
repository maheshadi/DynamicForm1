import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getFormLibrary from '@salesforce/apex/HR_FormSchemaService.getFormLibrary';
import cloneFormApex  from '@salesforce/apex/HR_FormSchemaService.cloneForm';
import getFormApex    from '@salesforce/apex/HR_FormSchemaService.getForm';
import { refreshApex } from '@salesforce/apex';

const PAGE_SIZE = 9;
const STATUS_COLOR = { Published:'#2e844a', Draft:'#e07400', Archived:'#706e6b' };
const CAT_COLOR = {
    Termination:'#ba0517', Onboarding:'#0070d2', Leave:'#6b5fc7',
    Compensation:'#e07400', Transfer:'#1b96ff', Performance:'#9e6a03',
    Benefits:'#2e844a', General:'#706e6b', Other:'#444'
};
function catColor(c)    { return CAT_COLOR[c] || '#444'; }
function statusColor(s) { return STATUS_COLOR[s] || '#706e6b'; }
function fmtDate(d)     { return d ? new Date(d).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'}) : ''; }

export default class HrFormLibrary extends NavigationMixin(LightningElement) {

    @track allForms      = [];
    @track isLoading     = true;
    @track hasError      = false;
    @track errorMessage  = '';
    @track searchTerm        = '';
    @track selectedStatus    = '';
    @track selectedCategory  = '';
    @track sortField         = 'LastModifiedDate';
    @track currentPage       = 1;
    @track showPreview        = false;
    @track previewFormApiName = '';
    @track previewFormName    = '';
    @track previewSchema      = null;
    @track previewLoading     = false;
    @track toastMessage  = '';
    @track toastVariant  = 'success';
    @track isCloning     = false;

    _wiredResult;

    @wire(getFormLibrary, { category: '', status: '' })
    wiredForms(result) {
        this._wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.allForms = data.map(f => ({
                id: f.Id, name: f.Name, apiName: f.HR_API_Name__c,
                status: f.HR_Status__c, category: f.HR_Category__c || 'General',
                description: f.HR_Description__c || '', version: f.HR_Version__c || 1,
                totalSubs: f.HR_Total_Submissions__c || 0, tags: f.HR_Tags__c || '',
                lastModified: f.LastModifiedDate
            }));
            this.isLoading = false;
        } else if (error) {
            this.hasError = true;
            this.errorMessage = (error && error.body && error.body.message) || 'Unable to load forms.';
            this.isLoading = false;
        }
    }

    // ── Filtered + Sorted ─────────────────────────────────────────────────────
    get filteredForms() {
        let forms = this.allForms.slice();
        const q = this.searchTerm.toLowerCase();
        if (q) forms = forms.filter(f =>
            f.name.toLowerCase().includes(q) || f.apiName.toLowerCase().includes(q) ||
            f.category.toLowerCase().includes(q) || f.tags.toLowerCase().includes(q));
        if (this.selectedStatus)   forms = forms.filter(f => f.status   === this.selectedStatus);
        if (this.selectedCategory) forms = forms.filter(f => f.category === this.selectedCategory);
        forms.sort((a, b) => {
            if (this.sortField === 'Name')                    return a.name.localeCompare(b.name);
            if (this.sortField === 'HR_Total_Submissions__c') return b.totalSubs - a.totalSubs;
            return new Date(b.lastModified) - new Date(a.lastModified);
        });
        return forms;
    }

    get pageItems() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredForms.slice(start, start + PAGE_SIZE).map(f => ({
            ...f,
            cardStyle    : 'border-top:3px solid ' + catColor(f.category) + ';',
            dotStyle     : 'background:' + catColor(f.category) + ';',
            badgeStyle   : 'background:' + statusColor(f.status) + '22;color:' + statusColor(f.status) + ';border:1px solid ' + statusColor(f.status) + ';',
            catPillStyle : 'background:' + catColor(f.category) + '22;color:' + catColor(f.category) + ';',
            modDate      : fmtDate(f.lastModified),
            isPublished  : f.status === 'Published'
        }));
    }

    get resultCount()    { return this.filteredForms.length; }
    get totalPages()     { return Math.max(1, Math.ceil(this.resultCount / PAGE_SIZE)); }
    get pageStart()      { return this.resultCount === 0 ? 0 : (this.currentPage - 1) * PAGE_SIZE + 1; }
    get pageEnd()        { return Math.min(this.currentPage * PAGE_SIZE, this.resultCount); }
    get isPrevDisabled() { return this.currentPage <= 1; }
    get isNextDisabled() { return this.currentPage >= this.totalPages; }
    get isEmpty()        { return !this.isLoading && this.resultCount === 0; }
    get totalCount()     { return this.allForms.length; }
    get publishedCount() { return this.allForms.filter(f => f.status === 'Published').length; }
    get draftCount()     { return this.allForms.filter(f => f.status === 'Draft').length; }
    get archivedCount()  { return this.allForms.filter(f => f.status === 'Archived').length; }
    get categoryCount()  { return new Set(this.allForms.map(f => f.category)).size; }
    get toastIcon()      { return 'utility:' + (this.toastVariant === 'success' ? 'success' : (this.toastVariant === 'warning' ? 'warning' : 'error')); }

    get categories() {
        const cats = [...new Set(this.allForms.map(f => f.category))].sort();
        return [
            { label: 'All Forms (' + this.allForms.length + ')', value: '', liClass: this.selectedCategory === '' ? 'fc-cat-item fc-cat-active' : 'fc-cat-item' },
            ...cats.map(c => ({
                label: c + ' (' + this.allForms.filter(f => f.category === c).length + ')',
                value: c,
                liClass: this.selectedCategory === c ? 'fc-cat-item fc-cat-active' : 'fc-cat-item'
            }))
        ];
    }
    get statusOptions() {
        return [{ label:'All Status',value:'' },{ label:'Published',value:'Published' },{ label:'Draft',value:'Draft' },{ label:'Archived',value:'Archived' }];
    }
    get sortOptions() {
        return [{ label:'Modified ↓',value:'LastModifiedDate' },{ label:'Name A–Z',value:'Name' },{ label:'Most Used',value:'HR_Total_Submissions__c' }];
    }

    // ── Handlers ──────────────────────────────────────────────────────────────
    handleSearch(evt)  { this.searchTerm = evt.target.value; this.currentPage = 1; }
    handleStatus(evt)  { this.selectedStatus = evt.detail.value; this.currentPage = 1; }
    handleSort(evt)    { this.sortField = evt.detail.value; this.currentPage = 1; }
    handleCategoryClick(evt) { this.selectedCategory = evt.currentTarget.dataset.value; this.currentPage = 1; }
    handlePrev() { if (this.currentPage > 1) this.currentPage--; }
    handleNext() { if (this.currentPage < this.totalPages) this.currentPage++; }

    handleEdit(evt) {
        const id   = evt.currentTarget.dataset.id;
        const form = this.allForms.find(f => f.id === id);
        if (form && form.apiName) {
            // sessionStorage is the signal; wiredPageRef in builder reads it on tab activation
            sessionStorage.setItem('hrfc_editFormApiName', form.apiName);
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: 'HR_Form_Builder' }
            });
        } else {
            this._toast('This form has no API name set. Open the builder directly.', 'warning');
        }
    }

    async handlePreview(evt) {
        const id   = evt.currentTarget.dataset.id;
        const form = this.allForms.find(f => f.id === id);
        if (!form || !form.apiName) {
            this._toast('No API name configured for preview.', 'warning');
            return;
        }
        this.previewFormApiName = form.apiName;
        this.previewFormName    = form.name;
        this.previewSchema      = null;
        this.previewLoading     = true;
        this.showPreview        = true;
        try {
            // Render the SAME working schema the builder preview shows, so both
            // previews are always identical. getForm returns the current draft
            // (with published fallback when the draft is empty).
            const rec = await getFormApex({ formApiName: form.apiName });
            this.previewSchema = this._assemblePreviewSchema(rec, form.apiName);
        } catch (e) {
            this._toast('Could not load preview: ' + ((e && e.body && e.body.message) || 'Unknown error'), 'error');
            this.showPreview = false;
        } finally {
            this.previewLoading = false;
        }
    }

    // Mirrors hrFormBuilder._loadForm so the Library preview and the Builder
    // preview render byte-for-byte the same schema.
    _assemblePreviewSchema(rec, apiName) {
        if (!rec) return null;
        const draft = rec.HR_Schema_JSON__c ? JSON.parse(rec.HR_Schema_JSON__c) : {};
        const pub   = rec.HR_Published_Schema_JSON__c ? JSON.parse(rec.HR_Published_Schema_JSON__c) : null;
        if (pub && !(draft.sections && draft.sections.length > 0)) {
            draft.sections = pub.sections || [];
            draft.rules    = pub.rules    || [];
        }
        return {
            ...draft,
            name:                rec.Name                       || draft.name,
            apiName:             rec.HR_API_Name__c             || apiName,
            allowDraftSave:      rec.HR_Allow_Draft_Save__c     != null ? rec.HR_Allow_Draft_Save__c     : draft.allowDraftSave,
            requireConfirmation: rec.HR_Require_Confirmation__c != null ? rec.HR_Require_Confirmation__c : draft.requireConfirmation,
            successMessage:      rec.HR_Success_Message__c      || draft.successMessage,
            redirectUrl:         rec.HR_Redirect_URL__c         || draft.redirectUrl,
            onSubmitAction:      rec.HR_On_Submit_Action__c     || draft.onSubmitAction
        };
    }

    handleClosePreview() {
        this.showPreview        = false;
        this.previewFormApiName = '';
        this.previewSchema      = null;
    }
    handlePreviewSubmit()     { this.template.querySelector('c-hr-form-renderer')?.submit(); }
    handlePreviewSaveDraft()  { this.template.querySelector('c-hr-form-renderer')?.saveDraft(); }
    handlePreviewReset()      { this.template.querySelector('c-hr-form-renderer')?.reset(); }

    async handleClone(evt) {
        const id   = evt.currentTarget.dataset.id;
        const form = this.allForms.find(f => f.id === id);
        if (!form) return;
        this.isCloning = true;
        try {
            await cloneFormApex({ formId: form.id });
            await refreshApex(this._wiredResult);
            this._toast('"' + form.name + '" cloned successfully!', 'success');
        } catch(e) {
            this._toast('Clone failed: ' + ((e && e.body && e.body.message) || 'Unknown error'), 'error');
        } finally {
            this.isCloning = false;
        }
    }

    handleNewForm() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'HR_Form_Builder' }
        });
    }

    handleImport() { this._toast('Import from file — coming in next release.', 'warning'); }

    _toast(message, variant = 'success') {
        this.toastMessage = message;
        this.toastVariant = variant;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.toastMessage = ''; }, 4000);
    }
}