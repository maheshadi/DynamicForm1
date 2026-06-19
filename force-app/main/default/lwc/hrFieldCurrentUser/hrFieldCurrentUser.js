import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID     from '@salesforce/user/Id';
import USER_NAME   from '@salesforce/schema/User.Name';
import USER_EMAIL  from '@salesforce/schema/User.Email';

export default class HrFieldCurrentUser extends LightningElement {
    @api field = {};

    userId = USER_ID;

    @wire(getRecord, { recordId: '$userId', fields: [USER_NAME, USER_EMAIL] })
    wiredUser({ data }) {
        if (data) {
            const val = this.field.currentUserAttribute === 'Email'
                ? getFieldValue(data, USER_EMAIL) : getFieldValue(data, USER_NAME);
            this.dispatchEvent(new CustomEvent('valuechanged', { detail: { apiName: this.field.apiName, value: val } }));
        }
    }

    get currentUserDisplay() {
        return this.userId ? '(Current User — auto-populated)' : '';
    }
}