/**
 * HR_LogicEngineService
 * Compiles and evaluates form logic rules stored as JSON in HR_Form__c.
 * Rules are read directly from the published schema JSON — no separate object needed.
 */
public with sharing class HR_LogicEngineService {

    // ─── Server-side submission validation ────────────────────────────────────

    public static List<HR_SchemaValidator.ValidationError> validateSubmission(
            String formApiName, Map<String, Object> payload) {

        HR_Form__c form = [
            SELECT Id
            FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName AND HR_Status__c = 'Published'
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        HR_FormSchema schema = HR_FormSchema.parse(
            HR_PublishService.getActiveSchemaJSON(form.Id));

        List<HR_SchemaValidator.ValidationError> errors =
            new List<HR_SchemaValidator.ValidationError>();

        // activeRulesByAction applies the isActive parity rule (only explicit
        // false deactivates), mirroring hrLogicEngine.evaluateRules on the client.
        for (HR_FormSchema.Rule r : schema.activeRulesByAction('Make_Required')) {
            if (conditionsMet(r.raw, payload)) {
                Object fieldValue = payload.get(r.targetApiName);
                if (fieldValue == null || String.isBlank(String.valueOf(fieldValue))) {
                    errors.add(new HR_SchemaValidator.ValidationError(
                        r.targetApiName, 'This field is required.'));
                }
            }
        }
        return errors;
    }

    // ─── Rule condition group evaluator (AND/OR) ──────────────────────────────
    // A rule's overall condition is its primary trigger (triggerFieldApiName/operator/
    // triggerValue) combined with any additionalConditions, joined by logicGroup
    // ('AND' by default, or 'OR'). Mirrors hrLogicEngine.ruleConditionsMet on the client.

    public static Boolean conditionsMet(Map<String, Object> rule, Map<String, Object> fieldValues) {
        List<Map<String, Object>> conditions = new List<Map<String, Object>>{
            new Map<String, Object>{
                'triggerFieldApiName' => rule.get('triggerFieldApiName'),
                'operator'            => rule.get('operator'),
                'triggerValue'        => rule.get('triggerValue')
            }
        };
        if (rule.get('additionalConditions') != null) {
            for (Object condObj : (List<Object>) rule.get('additionalConditions')) {
                conditions.add((Map<String, Object>) condObj);
            }
        }

        Boolean useOr = 'OR' == (String) rule.get('logicGroup');
        for (Map<String, Object> cond : conditions) {
            String triggerApi = (String) cond.get('triggerFieldApiName');
            Boolean matched = matchesCondition(
                (String) cond.get('operator'),
                String.valueOf(fieldValues.get(triggerApi)),
                (String) cond.get('triggerValue')
            );
            if (useOr && matched) return true;
            if (!useOr && !matched) return false;
        }
        return !useOr;
    }

    // ─── Condition evaluator ───────────────────────────────────────────────────

    // String comparisons are case-insensitive on both tiers (Apex == already is;
    // contains/starts_with are lowered explicitly). Mirrors hrLogicEngine.matchesCondition.
    public static Boolean matchesCondition(String operator, String actual, String expected) {
        String actualLc   = actual   == null ? null : actual.toLowerCase();
        String expectedLc = expected == null ? ''   : expected.toLowerCase();
        if (operator == 'equals')        return actual == expected;
        if (operator == 'not_equals')    return actual != expected;
        if (operator == 'contains')      return actualLc != null && actualLc.contains(expectedLc);
        if (operator == 'not_contains')  return actualLc == null || !actualLc.contains(expectedLc);
        if (operator == 'starts_with')   return actualLc != null && actualLc.startsWith(expectedLc);
        if (operator == 'is_empty')      return String.isBlank(actual);
        if (operator == 'is_not_empty')  return String.isNotBlank(actual);
        if (operator == 'greater_than')  return numericCompare(actual, expected, '>');
        if (operator == 'less_than')     return numericCompare(actual, expected, '<');
        if (operator == 'greater_equal') return numericCompare(actual, expected, '>=');
        if (operator == 'less_equal')    return numericCompare(actual, expected, '<=');
        if (operator == 'in_list')       return splitList(expected).contains(actual);
        if (operator == 'not_in_list')   return !splitList(expected).contains(actual);
        return false;
    }

    // Mirrors the client engine's behavior: a non-numeric value on either side means
    // "no match" rather than a thrown exception that blocks the whole submission.
    private static Boolean numericCompare(String actual, String expected, String op) {
        Decimal a, b;
        try {
            a = Decimal.valueOf(actual);
            b = Decimal.valueOf(expected);
        } catch (Exception e) {
            return false;
        }
        if (op == '>')  return a >  b;
        if (op == '<')  return a <  b;
        if (op == '>=') return a >= b;
        if (op == '<=') return a <= b;
        return false;
    }

    // Splits a pipe-delimited rule value into trimmed items, honoring "\|" as a literal pipe
    // (splits only on unescaped pipes, then unescapes "\|" back to "|" in each item).
    private static List<String> splitList(String raw) {
        List<String> result = new List<String>();
        if (raw == null) return result;
        for (String part : raw.split('(?<!\\\\)\\|')) {
            result.add(part.replace('\\|', '|').trim());
        }
        return result;
    }
}