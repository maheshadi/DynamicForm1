/**
 * HR_FormSchemaService
 * CRUD operations on HR_Form__c and its children.
 * Validates schema JSON before every write.
 */
public with sharing class HR_FormSchemaService {

    // ─── Get ───────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static HR_Form__c getForm(String formApiName) {
        List<HR_Form__c> forms = [
            SELECT Id, Name, HR_API_Name__c, HR_Status__c, HR_Category__c,
                   HR_Schema_JSON__c, HR_Published_Schema_JSON__c,
                   HR_Target_Object_API__c, HR_Deployment_Target__c,
                   HR_On_Submit_Action__c, HR_Success_Message__c,
                   HR_Redirect_URL__c, HR_Allow_Draft_Save__c,
                   HR_Require_Confirmation__c, HR_Version__c, HR_Tags__c,
                   HR_Description__c, HR_LWC_Name__c, HR_Record_Type_Dev_Name__c
            FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (forms.isEmpty()) {
            throw new HR_FormNotFoundException('Form not found: ' + formApiName);
        }
        return forms[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<HR_Form__c> getFormLibrary(String category, String status) {
        String baseStatus = String.isBlank(status) ? 'Published' : status;
        String soql = 'SELECT Id, Name, HR_API_Name__c, HR_Status__c, HR_Category__c, '
                    + 'HR_Version__c, HR_Tags__c, HR_Description__c, '
                    + 'HR_Last_Published_Date__c, HR_Total_Submissions__c, LastModifiedDate '
                    + 'FROM HR_Form__c WHERE Id != null ';
        if (String.isNotBlank(baseStatus)) {
            soql += 'AND HR_Status__c = :baseStatus ';
        }
        if (String.isNotBlank(category)) {
            soql += 'AND HR_Category__c = :category ';
        }
        soql += 'WITH SECURITY_ENFORCED ORDER BY LastModifiedDate DESC';
        return Database.query(soql);
    }

    // ─── Save / Create ─────────────────────────────────────────────────────────

    @AuraEnabled
    public static String saveForm(Map<String, Object> formData) {
        String formId = (String) formData.get('id');
        String apiName = (String) formData.get('apiName');

        HR_Form__c form;
        if (String.isNotBlank(formId)) {
            form = [SELECT Id, HR_Version__c FROM HR_Form__c WHERE Id = :formId WITH SECURITY_ENFORCED LIMIT 1];
        } else {
            form = new HR_Form__c();
        }

        String schemaJSON = (String) formData.get('schemaJSON');

        form.Name                       = (String)  formData.get('name');
        form.HR_API_Name__c             = apiName;
        form.HR_Category__c             = (String)  formData.get('category');
        form.HR_Description__c          = (String)  formData.get('description');
        form.HR_Tags__c                 = (String)  formData.get('tags');
        form.HR_Schema_JSON__c          = schemaJSON;
        form.HR_Target_Object_API__c    = (String)  formData.get('targetObjectApi');
        form.HR_Record_Type_Dev_Name__c = (String)  formData.get('recordTypeDevName');
        form.HR_Deployment_Target__c    = (String)  formData.get('deploymentTarget');
        form.HR_On_Submit_Action__c     = (String)  formData.get('onSubmitAction');
        form.HR_Success_Message__c      = (String)  formData.get('successMessage');
        form.HR_Redirect_URL__c         = (String)  formData.get('redirectUrl');
        form.HR_Allow_Draft_Save__c     = (Boolean) formData.get('allowDraftSave');
        form.HR_Require_Confirmation__c = (Boolean) formData.get('requireConfirmation');

        // FLS check first: skip the (expensive) schema validation entirely if the
        // user isn't even allowed to write these fields.
        SObjectAccessDecision decision = Security.stripInaccessible(
            String.isNotBlank(formId) ? AccessType.UPDATABLE : AccessType.CREATABLE,
            new List<SObject>{ form }
        );
        SObject saved = decision.getRecords()[0];

        assertApiNameUnique(apiName, formId);

        List<HR_SchemaValidator.ValidationError> errors = HR_SchemaValidator.validate(schemaJSON);
        if (!errors.isEmpty()) {
            throw new AuraHandledException(JSON.serialize(errors));
        }

        upsert saved;
        String savedId = (String) saved.get('Id');

        HR_AuditService.logAsync(
            String.isNotBlank(formId) ? 'Form_Modified' : 'Form_Created',
            savedId, null
        );

        return savedId;
    }

    // ─── Helpers ───────────────────────────────────────────────────────────────

    private static void assertApiNameUnique(String apiName, String formId) {
        if (String.isBlank(apiName)) {
            return;
        }
        List<HR_Form__c> conflicts = [
            SELECT Id FROM HR_Form__c
            WHERE HR_API_Name__c = :apiName AND Id != :formId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!conflicts.isEmpty()) {
            throw new AuraHandledException(
                'A form with API name "' + apiName + '" already exists. Choose a unique API name.'
            );
        }
    }

    @AuraEnabled
    public static void deleteForm(String formId) {
        if (!FeatureManagement.checkPermission('HR_Form_Admin')) {
            throw new AuraHandledException('Administrator permission required to delete forms.');
        }
        HR_Form__c form = [SELECT Id FROM HR_Form__c WHERE Id = :formId WITH SECURITY_ENFORCED LIMIT 1];
        HR_AuditService.logAsync('Form_Deleted', formId, null);
        delete form;
    }

    @AuraEnabled
    public static String cloneForm(String formId) {
        HR_Form__c src = [
            SELECT Name, HR_API_Name__c, HR_Category__c, HR_Description__c,
                   HR_Tags__c, HR_Schema_JSON__c, HR_Target_Object_API__c,
                   HR_Record_Type_Dev_Name__c, HR_Deployment_Target__c,
                   HR_On_Submit_Action__c, HR_Success_Message__c,
                   HR_Redirect_URL__c, HR_Allow_Draft_Save__c, HR_Require_Confirmation__c
            FROM HR_Form__c WHERE Id = :formId WITH SECURITY_ENFORCED LIMIT 1
        ];

        HR_Form__c clone = src.clone(false, true, false, false);
        clone.Name           = 'Copy of ' + src.Name;
        clone.HR_API_Name__c = src.HR_API_Name__c + '_copy_' + String.valueOf(Datetime.now().getTime());
        clone.HR_Status__c   = 'Draft';
        clone.HR_Version__c  = 1;

        SObjectAccessDecision dec = Security.stripInaccessible(AccessType.CREATABLE, new List<SObject>{ clone });
        SObject inserted = dec.getRecords()[0];
        insert inserted;
        String cloneId = (String) inserted.get('Id');

        HR_AuditService.logAsync('Form_Cloned', cloneId, null);
        return cloneId;
    }

    // ─── Exceptions ────────────────────────────────────────────────────────────

    public class HR_FormNotFoundException extends Exception {}
}