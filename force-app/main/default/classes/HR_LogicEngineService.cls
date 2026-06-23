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
            SELECT HR_Published_Schema_JSON__c
            FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName AND HR_Status__c = 'Published'
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        Map<String, Object> schema = String.isBlank(form.HR_Published_Schema_JSON__c)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(form.HR_Published_Schema_JSON__c);

        List<Map<String, Object>> rules = getRulesFromSchema(schema);
        List<HR_SchemaValidator.ValidationError> errors =
            new List<HR_SchemaValidator.ValidationError>();

        for (Map<String, Object> r : rules) {
            if (r.get('action') != 'Make_Required') continue;
            String triggerApi = (String) r.get('triggerFieldApiName');
            String operator   = (String) r.get('operator');
            String expected   = (String) r.get('triggerValue');
            Object trigVal    = payload.get(triggerApi);
            if (matchesCondition(operator, String.valueOf(trigVal), expected)) {
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

    // ─── Condition evaluator ───────────────────────────────────────────────────

    public static Boolean matchesCondition(String operator, String actual, String expected) {
        if (operator == 'equals')        return actual == expected;
        if (operator == 'not_equals')    return actual != expected;
        if (operator == 'contains')      return actual != null && actual.contains(expected);
        if (operator == 'not_contains')  return actual == null || !actual.contains(expected);
        if (operator == 'starts_with')   return actual != null && actual.startsWith(expected);
        if (operator == 'is_empty')      return String.isBlank(actual);
        if (operator == 'is_not_empty')  return String.isNotBlank(actual);
        if (operator == 'greater_than')  return Decimal.valueOf(actual) >  Decimal.valueOf(expected);
        if (operator == 'less_than')     return Decimal.valueOf(actual) <  Decimal.valueOf(expected);
        if (operator == 'greater_equal') return Decimal.valueOf(actual) >= Decimal.valueOf(expected);
        if (operator == 'less_equal')    return Decimal.valueOf(actual) <= Decimal.valueOf(expected);
        if (operator == 'in_list')       return expected != null && expected.split('\\|').contains(actual);
        if (operator == 'not_in_list')   return expected == null || !expected.split('\\|').contains(actual);
        return false;
    }

    // ─── Server-side rule evaluation ──────────────────────────────────────────

    public static void evaluateRules(List<Map<String, Object>> rules,
            Map<String, Object> fieldValues, List<Map<String, Object>> actions) {
        for (Map<String, Object> r : rules) {
            String triggerApi = (String) r.get('triggerFieldApiName');
            String operator   = (String) r.get('operator');
            String expected   = (String) r.get('triggerValue');
            Object trigVal    = fieldValues.get(triggerApi);
            if (matchesCondition(operator, String.valueOf(trigVal), expected)) {
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
