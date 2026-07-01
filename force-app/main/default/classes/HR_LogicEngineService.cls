/**
 * HR_LogicEngineService
 * Compiles and evaluates form logic rules stored as JSON in HR_Form__c.
 * Rules are read directly from the published schema JSON — no separate object needed.
 */
public with sharing class HR_LogicEngineService {

    // ─── Extract rules list from a deserialized schema map ────────────────────

    public static List<Map<String, Object>> getRulesFromSchema(Map<String, Object> schema) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        if (schema == null || !schema.containsKey('rules')) return result;
        for (Object rObj : (List<Object>) schema.get('rules')) {
            result.add((Map<String, Object>) rObj);
        }
        return result;
    }

    // ─── Compile rules into JSON string for the client logic engine ───────────

    public static String compileRules(List<Map<String, Object>> rules) {
        return JSON.serialize(rules);
    }

    // ─── Server-side submission validation ────────────────────────────────────

    public static List<HR_SchemaValidator.ValidationError> validateSubmission(
            String formApiName, Map<String, Object> payload) {

        HR_Form__c form = [
            SELECT Id
            FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName AND HR_Status__c = 'Published'
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        String schemaJSON = HR_PublishService.getActiveSchemaJSON(form.Id);
        Map<String, Object> schema = String.isBlank(schemaJSON)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(schemaJSON);

        List<Map<String, Object>> rules = getRulesFromSchema(schema);
        List<HR_SchemaValidator.ValidationError> errors =
            new List<HR_SchemaValidator.ValidationError>();

        for (Map<String, Object> r : rules) {
            if (r.get('action') != 'Make_Required') continue;
            if (conditionsMet(r, payload)) {
                String targetApi  = (String) r.get('targetApiName');
                Object fieldValue = payload.get(targetApi);
                if (fieldValue == null || String.isBlank(String.valueOf(fieldValue))) {
                    errors.add(new HR_SchemaValidator.ValidationError(
                        targetApi, 'This field is required.'));
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

    public static Boolean matchesCondition(String operator, String actual, String expected) {
        if (operator == 'equals')        return actual == expected;
        if (operator == 'not_equals')    return actual != expected;
        if (operator == 'contains')      return actual != null && actual.contains(expected);
        if (operator == 'not_contains')  return actual == null || !actual.contains(expected);
        if (operator == 'starts_with')   return actual != null && actual.startsWith(expected);
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

    // ─── Server-side rule evaluation ──────────────────────────────────────────

    public static void evaluateRules(List<Map<String, Object>> rules,
            Map<String, Object> fieldValues, List<Map<String, Object>> actions) {
        for (Map<String, Object> r : rules) {
            if (conditionsMet(r, fieldValues)) {
                actions.add(new Map<String, Object>{
                    'action'        => r.get('action'),
                    'targetType'    => r.get('targetType'),
                    'targetApiName' => r.get('targetApiName'),
                    'actionValue'   => r.get('actionValue')
                });
            }
        }
    }
}