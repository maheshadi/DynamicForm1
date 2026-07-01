/**
 * hrLogicEngine
 * Client-side conditional logic evaluator. No LWC template — pure JS module.
 * Imported by hrFormRenderer to evaluate a compiled rule bundle against current field values.
 *
 * Rule bundle shape (compiled by HR_LogicEngineService.compileRules):
 * [{ id, name, triggerFieldApiName, operator, triggerValue, action, targetType,
 *    targetApiName, actionValue, isActive, logicGroup,
 *    additionalConditions: [{ triggerFieldApiName, operator, triggerValue }] }]
 *
 * A rule's primary trigger plus any additionalConditions are combined using
 * logicGroup ('AND' by default, or 'OR') to decide whether the rule fires.
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
    return ruleBundle.filter(rule => rule.isActive && ruleConditionsMet(rule, fieldValues));
}

/**
 * Combines a rule's primary condition with any additionalConditions using AND/OR.
 * Mirrors HR_LogicEngineService.conditionsMet on the server.
 */
export function ruleConditionsMet(rule, fieldValues) {
    const conditions = [
        { triggerFieldApiName: rule.triggerFieldApiName, operator: rule.operator, triggerValue: rule.triggerValue },
        ...(Array.isArray(rule.additionalConditions) ? rule.additionalConditions : [])
    ];
    const useOr = rule.logicGroup === 'OR';
    const results = conditions.map(c =>
        matchesCondition(c.operator, fieldValues[c.triggerFieldApiName], c.triggerValue)
    );
    return useOr ? results.some(Boolean) : results.every(Boolean);
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
        case 'in_list':        return splitList(tv).includes(fv);
        case 'not_in_list':    return !splitList(tv).includes(fv);
        default:               return false;
    }
}

/**
 * Splits a pipe-delimited rule value into trimmed items, honoring "\|" as a literal pipe.
 * Mirrors HR_LogicEngineService.splitList on the server.
 */
function splitList(raw) {
    if (!raw) return [];
    return raw.split(/(?<!\\)\|/).map(v => v.replace(/\\\|/g, '|').trim());
}