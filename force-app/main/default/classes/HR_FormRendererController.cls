/**
 * HR_FormRendererController
 * @AuraEnabled controller for hrFormRenderer LWC.
 * Serves published schema + logic bundle to the client.
 */
public with sharing class HR_FormRendererController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getFormSchema(String formApiName) {
        // Guard: reject blank / null formApiName before any query
        if (String.isBlank(formApiName)) {
            throw new AuraHandledException('formApiName is required');
        }
        // 1. Validate access
        HR_AccessService.assertCanView(formApiName);

        // 2. Query published schema only — SECURITY_ENFORCED prevents FLS bypass
        List<HR_Form__c> forms = [
            SELECT HR_Published_Schema_JSON__c, HR_Allow_Draft_Save__c,
                   HR_On_Submit_Action__c, HR_Success_Message__c,
                   HR_Redirect_URL__c, HR_Require_Confirmation__c,
                   HR_Target_Object_API__c, HR_Record_Type_Dev_Name__c
            FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName
              AND HR_Status__c   = 'Published'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (forms.isEmpty()) {
            throw new AuraHandledException('Form not found or not published: ' + formApiName);
        }
        HR_Form__c form = forms[0];

        // 3. Compile logic rules into client-side bundle
        List<HR_Logic_Rule__c> rules = HR_LogicEngineService.getRules(form.Id);
        String logicBundle = HR_LogicEngineService.compileRules(rules);

        // 4. Return schema + logic bundle + config
        return new Map<String, Object>{
            'schema'      => String.isBlank(form.HR_Published_Schema_JSON__c)
                              ? new Map<String, Object>{ 'sections' => new List<Object>() }
                              : JSON.deserializeUntyped(form.HR_Published_Schema_JSON__c),
            'logicBundle' => String.isBlank(logicBundle) ? new List<Object>() : JSON.deserializeUntyped(logicBundle),
            'config'      => getFormConfig(form)
        };
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getPicklistValues(String objectApiName, String fieldApiName) {
        return HR_SFObjectService.getPicklistValues(objectApiName, fieldApiName);
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> lookupSearch(
            String objectApiName, String searchTerm,
            String displayField, String searchFields, String filterSOQL) {
        return HR_SFObjectService.lookupSearch(objectApiName, searchTerm, displayField, searchFields, filterSOQL);
    }

    // ─── Private helpers ───────────────────────────────────────────────────────

    private static Map<String, Object> getFormConfig(HR_Form__c form) {
        return new Map<String, Object>{
            'allowDraftSave'      => form.HR_Allow_Draft_Save__c,
            'onSubmitAction'      => form.HR_On_Submit_Action__c,
            'successMessage'      => form.HR_Success_Message__c,
            'redirectUrl'         => form.HR_Redirect_URL__c,
            'requireConfirmation' => form.HR_Require_Confirmation__c,
            'targetObjectApi'     => form.HR_Target_Object_API__c,
            'recordTypeDevName'   => form.HR_Record_Type_Dev_Name__c
        };
    }
}