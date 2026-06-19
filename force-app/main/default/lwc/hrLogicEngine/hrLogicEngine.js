/**
 * hrLogicEngine
 * Client-side conditional logic evaluator. No LWC template — pure JS module.
 * Imported by hrFormRenderer to evaluate a compiled rule bundle against current field values.
 *
 * Rule bundle shape (compiled by HR_LogicEngineService.compileRules):
 * [{ id, name, triggerFieldApiName, operator, triggerValue, action, targetType,
 *    targetApiName, actionValue, isActive, logicGroup }]
 */

/**
 * Evaluate all rules against current field values.
 * Returns the list of rules whose conditions were met.
 * @param {Array}  ruleBundle - compiled rules array
 * @param {Object} fieldValues - map of apiName → current value
 * @returns {Array} triggered rule objects
 */
export function evaluateRules(ruleBundle, fieldValues) {
    if (!Array.isArray(ruleBundle) || !fieldValues) return [];
    return ruleBundle.filter(rule => {
        if (!rule.isActive) return false;
        const fieldVal = fieldValues[rule.triggerFieldApiName];
        return matchesCondition(rule.operator, fieldVal, rule.triggerValue);
    });
}

/**
 * Test whether a single field value satisfies an operator/trigger pair.
 * Mirrors HR_LogicEngineService.matchesCondition on the server.
 */
export function matchesCondition(operator, fieldValue, triggerValue) {
    const fv = fieldValue !== null && fieldValue !== undefined ? String(fieldValue) : '';
    const tv = triggerValue !== null && triggerValue !== undefined ? String(triggerValue) : '';

    switch (operator) {
        case 'equals':         return fv === tv;
        case 'not_equals':     return fv !== tv;
        case 'contains':       return fv.toLowerCase().includes(tv.toLowerCase());
        case 'not_contains':   return !fv.toLowerCase().includes(tv.toLowerCase());
        case 'starts_with':    return fv.toLowerCase().startsWith(tv.toLowerCase());
        case 'is_empty':       return fv === '' || fv === null || fv === undefined;
        case 'is_not_empty':   return fv !== '' && fv !== null && fv !== undefined;
        case 'greater_than':   return parseFloat(fv) > parseFloat(tv);
        case 'less_than':      return parseFloat(fv) < parseFloat(tv);
        case 'greater_equal':  return parseFloat(fv) >= parseFloat(tv);
        case 'less_equal':     return parseFloat(fv) <= parseFloat(tv);
        case 'in_list':        return tv.split('|').map(v => v.trim()).includes(fv);
        case 'not_in_list':    return !tv.split('|').map(v => v.trim()).includes(fv);
        default:               return false;
    }
}