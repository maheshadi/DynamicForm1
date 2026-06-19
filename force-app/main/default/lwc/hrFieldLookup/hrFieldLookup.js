import { LightningElement, api, track } from 'lwc';
import lookupSearchApex from '@salesforce/apex/HR_FormRendererController.lookupSearch';

export default class HrFieldLookup extends LightningElement {
    @api field = {}; @api value = ''; @api isDisabled = false;
    @track searchTerm    = '';
    @track results       = [];
    @track showDropdown  = false;
    @track isSearching   = false;
    @track selectedRecord = null;
    _searchTimer = null;

    get hasResults() { return this.results.length > 0; }

    handleSearch(evt) {
        this.searchTerm = evt.target.value;
        clearTimeout(this._searchTimer);
        if (this.searchTerm.length < 2) { this.showDropdown = false; return; }
        this._searchTimer = setTimeout(() => this._doSearch(), 300);
    }

    async _doSearch() {
        this.isSearching = true; this.showDropdown = true;
        try {
            this.results = await lookupSearchApex({
                objectApiName: this.field.lookupObjectApi,
                searchTerm:    this.searchTerm,
                filterField:   this.field.lookupFilterField || null,
                filterValue:   this.field.lookupFilterValue || null
            });
        } catch(e) { this.results = []; }
        this.isSearching = false;
    }

    handleSelect(evt) {
        const id    = evt.currentTarget.dataset.id;
        const label = evt.currentTarget.dataset.label;
        this.selectedRecord = { id, label };
        this.searchTerm     = '';
        this.showDropdown   = false;
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: id } }));
    }

    handleClear() {
        this.selectedRecord = null;
        this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: null } }));
    }

    handleKeyDown(evt) {
        if (evt.key === 'Escape') { this.showDropdown = false; }
    }
}