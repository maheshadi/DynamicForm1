/**
 * HR_SubmissionService
 * Validates, persists, and maps form submissions to target SObject.
 * Field-to-SF-object mappings are read from the published schema JSON (sfFieldApi property).
 */
public with sharing class HR_SubmissionService {

    @AuraEnabled
    public static String submitForm(String formApiName, String payloadJSON, Integer durationSec) {
        // 1. Re-evaluate server-side logic rules to prevent client bypass
        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(payloadJSON);
        List<HR_SchemaValidator.ValidationError> errors =
            HR_LogicEngineService.validateSubmission(formApiName, payload);
        if (!errors.isEmpty()) {
            throw new AuraHandledException(JSON.serialize(errors));
        }

        // 2. Query form config — include published schema for field mapping
        HR_Form__c form = [
            SELECT Id, HR_Target_Object_API__c, HR_Record_Type_Dev_Name__c,
                   HR_Version__c, HR_Published_Schema_JSON__c
            FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName
              AND HR_Status__c   = 'Published'
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        // 3. Map payload to target SObject using sfFieldApi from schema JSON and insert
        SObject targetRecord = mapToSObject(form, payload);
        SObjectAccessDecision dec = Security.stripInaccessible(AccessType.CREATABLE,
            new List<SObject>{ targetRecord });
        insert dec.getRecords()[0];
        String targetRecordId = (String) dec.getRecords()[0].get('Id');

        // 4. Persist submission header (full payload stored as JSON — single source of truth)
        HR_Form_Submission__c sub = createSubmissionRecord(
            form, payloadJSON, targetRecordId, durationSec);
        insert sub;

        // 5. Audit log async
        HR_AuditService.logAsync('Submission_Created', sub.Id, null);

        return sub.Id;
    }

    @AuraEnabled
    public static String saveDraft(String formApiName, String payloadJSON) {
        // Enforce concurrent draft limit from custom setting
        HR_Org_Settings__c settings = HR_Org_Settings__c.getInstance();
        Integer maxDrafts = (settings.HR_Max_Draft_Submissions__c != null)
            ? Integer.valueOf(settings.HR_Max_Draft_Submissions__c) : 5;

        Integer existingDrafts = [
            SELECT COUNT() FROM HR_Form_Submission__c
            WHERE HR_Submitted_By__c = :UserInfo.getUserId()
              AND HR_Status__c = 'Draft'
            WITH SECURITY_ENFORCED
        ];
        if (existingDrafts >= maxDrafts) {
            throw new AuraHandledException(
                'Maximum concurrent drafts (' + maxDrafts + ') reached. Please submit or delete an existing draft.');
        }

        HR_Form__c form = [
            SELECT Id, HR_Version__c, HR_Target_Object_API__c FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName AND HR_Status__c = 'Published'
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        HR_Form_Version__c ver = [
            SELECT Id FROM HR_Form_Version__c
            WHERE HR_Form__c = :form.Id AND HR_Is_Active_Version__c = true
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        HR_Form_Submission__c sub = new HR_Form_Submission__c(
            HR_Form__c              = form.Id,
            HR_Form_Version__c      = ver.Id,
            HR_Submitted_By__c      = UserInfo.getUserId(),
            HR_Status__c            = 'Draft',
            HR_Payload_JSON__c      = payloadJSON,
            HR_Target_Object_API__c = form.HR_Target_Object_API__c
        );
        insert sub;
        return sub.Id;
    }

    @AuraEnabled(cacheable=false)
    public static List<HR_Form_Submission__c> getMyDrafts(String formApiName) {
        return [
            SELECT Id, Name, HR_Status__c, CreatedDate, HR_Payload_JSON__c
            FROM HR_Form_Submission__c
            WHERE HR_Submitted_By__c = :UserInfo.getUserId()
              AND HR_Status__c       = 'Draft'
              AND HR_Form__r.HR_API_Name__c = :formApiName
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=false)
    public static HR_Form_Submission__c getDraftById(String draftId) {
        return [
            SELECT Id, HR_Payload_JSON__c, HR_Status__c
            FROM HR_Form_Submission__c
            WHERE Id = :draftId
              AND HR_Submitted_By__c = :UserInfo.getUserId()
              AND HR_Status__c       = 'Draft'
            WITH SECURITY_ENFORCED LIMIT 1
        ];
    }

    // ─── Private helpers ───────────────────────────────────────────────────────

    private static SObject mapToSObject(HR_Form__c form, Map<String, Object> payload) {
        SObject record = Schema.getGlobalDescribe()
            .get(form.HR_Target_Object_API__c).newSObject();

        // Set RecordTypeId if configured
        if (String.isNotBlank(form.HR_Record_Type_Dev_Name__c)) {
            Id rtId = Schema.getGlobalDescribe()
                .get(form.HR_Target_Object_API__c)
                .getDescribe()
                .getRecordTypeInfosByDeveloperName()
                .get(form.HR_Record_Type_Dev_Name__c)
                .getRecordTypeId();
            record.put('RecordTypeId', rtId);
        }

        // Read field-to-SF-object mappings from published schema JSON (sfFieldApi property)
        if (String.isBlank(form.HR_Published_Schema_JSON__c)) return record;

        Map<String, Object> schema =
            (Map<String, Object>) JSON.deserializeUntyped(form.HR_Published_Schema_JSON__c);
        List<Object> sections = schema.containsKey('sections')
            ? (List<Object>) schema.get('sections') : new List<Object>();

        for (Object secObj : sections) {
            Map<String, Object> sec = (Map<String, Object>) secObj;
            List<Object> fields = sec.containsKey('fields')
                ? (List<Object>) sec.get('fields') : new List<Object>();
            for (Object fldObj : fields) {
                Map<String, Object> fld = (Map<String, Object>) fldObj;
                String sfFieldApi = (String) fld.get('sfFieldApi');
                if (String.isBlank(sfFieldApi)) continue;
                String apiName = (String) fld.get('apiName');
                Object val = payload.get(apiName);
                if (val != null) {
                    record.put(sfFieldApi, val);
                }
            }
        }
        return record;
    }

    private static HR_Form_Submission__c createSubmissionRecord(
            HR_Form__c form, String payloadJSON,
            String targetRecordId, Integer durationSec) {

        HR_Form_Version__c ver = [
            SELECT Id FROM HR_Form_Version__c
            WHERE HR_Form__c = :form.Id AND HR_Is_Active_Version__c = true
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        return new HR_Form_Submission__c(
            HR_Form__c              = form.Id,
            HR_Form_Version__c      = ver.Id,
            HR_Submitted_By__c      = UserInfo.getUserId(),
            HR_Submitted_Date__c    = Datetime.now(),
            HR_Status__c            = 'Submitted',
            HR_Target_Record_Id__c  = targetRecordId,
            HR_Target_Object_API__c = form.HR_Target_Object_API__c,
            HR_Payload_JSON__c      = payloadJSON,
            HR_Duration_Seconds__c  = durationSec
        );
    }
}
