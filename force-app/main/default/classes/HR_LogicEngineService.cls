/**
 * HR_LogicEngineService
 * Compiles HR_Logic_Rule__c records into a JSON logic bundle for the client.
 * Also provides server-side rule evaluation at submit time.
 */
public with sharing class HR_LogicEngineService {

    public static List<HR_Logic_Rule__c> getRules(String formId) {
        return [
            SELECT Id, Name, HR_Order__c, HR_Is_Active__c,
                   HR_Trigger_Field__r.HR_API_Name__c,
                   HR_Operator__c, HR_Trigger_Value__c,
                   HR_Action__c, HR_Target_Type__c,
                   HR_Target_Field__r.HR_API_Name__c,
                   HR_Target_Section__r.Name,
                   HR_Action_Value__c, HR_Logic_Group__c
            FROM HR_Logic_Rule__c
            WHERE HR_Form__c    = :formId
              AND HR_Is_Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY HR_Order__c ASC
        ];
    }

    /**
     * Compiles active rules into JSON consumed by hrLogicEngine.js.
     * Structure: [ { triggerFieldApiName, operator, triggerValue, action,
     *                targetType, targetApiName, actionValue, logicGroup } ]
     */
    public static String compileRules(List<HR_Logic_Rule__c> rules) {
        List<Map<String, Object>> bundle = new List<Map<String, Object>>();
        for (HR_Logic_Rule__c r : rules) {
            bundle.add(new Map<String, Object>{
                'triggerFieldApiName' => r.HR_Trigger_Field__r.HR_API_Name__c,
                'operator'            => r.HR_Operator__c,
                'triggerValue'        => r.HR_Trigger_Value__c,
                'action'              => r.HR_Action__c,
                'targetType'          => r.HR_Target_Type__c,
                'targetApiName'       => r.HR_Target_Type__c == 'Field'
                                         ? r.HR_Target_Field__r.HR_API_Name__c
                                         : r.HR_Target_Section__r.Name,
                'actionValue'         => r.HR_Action_Value__c,
                'logicGroup'          => r.HR_Logic_Group__c
            });
        }
        return JSON.serialize(bundle);
    }

    /**
     * Server-side submission validation.
     * Evaluates Required rules against submitted payload.
     */
    public static List<HR_SchemaValidator.ValidationError> validateSubmission(
            String formApiName, Map<String, Object> payload) {

        HR_Form__c form = [
            SELECT Id FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName AND HR_Status__c = 'Published'
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        List<HR_Logic_Rule__c> rules = getRules(form.Id);
        List<HR_SchemaValidator.ValidationError> errors =
            new List<HR_SchemaValidator.ValidationError>();

        for (HR_Logic_Rule__c r : rules) {
            if (r.HR_Action__c != 'Make_Required') continue;
            String triggerApiName = r.HR_Trigger_Field__r.HR_API_Name__c;
            Object triggerValue = payload.get(triggerApiName);
            if (matchesCondition(r.HR_Operator__c, String.valueOf(triggerValue), r.HR_Trigger_Value__c)) {
                String targetApi = r.HR_Target_Field__r.HR_API_Name__c;
                Object fieldValue = payload.get(targetApi);
                if (fieldValue == null || String.isBlank(String.valueOf(fieldValue))) {
                    errors.add(new HR_SchemaValidator.ValidationError(
                        targetApi, 'This field is required.'));
                }
            }
        }
        return errors;
    }

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

    public static void evaluateRules(List<HR_Logic_Rule__c> rules,
            Map<String, Object> fieldValues, List<Map<String,Object>> actions) {
        for (HR_Logic_Rule__c r : rules) {
            Object trigVal = fieldValues.get(r.HR_Trigger_Field__r.HR_API_Name__c);
            if (matchesCondition(r.HR_Operator__c, String.valueOf(trigVal), r.HR_Trigger_Value__c)) {
                actions.add(new Map<String, Object>{
                    'action'        => r.HR_Action__c,
                    'targetType'    => r.HR_Target_Type__c,
                    'targetApiName' => r.HR_Target_Type__c == 'Field'
                                       ? r.HR_Target_Field__r.HR_API_Name__c
                                       : r.HR_Target_Section__r.Name,
                    'actionValue'   => r.HR_Action_Value__c
                });
            }
        }
    }
}