import { LightningElement, api } from 'lwc';
export default class HrFieldInfoBox extends LightningElement {
    @api field = {};
    get isDivider()      { return this.field.type === 'Divider'; }
    get isInfoBox()      { return this.field.type === 'InfoBox'; }
    get isInstructions() { return this.field.type === 'Instructions'; }
}