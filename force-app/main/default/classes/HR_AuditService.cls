/**
 * HR_AuditService
 * Append-only audit log writer.
 * All other services call this; never called from LWC directly.
 * Runs in a future context to avoid DML governor conflicts.
 */
public without sharing class HR_AuditService {

    /**
     * Fire-and-forget async audit log.
     * Pass relatedRecordId for submission events.
     */
    @future
    public static void logAsync(String action, String relatedRecordId, String details) {
        try {
            log(action, relatedRecordId, details, null, null);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'HR_AuditService.logAsync failed: ' + e.getMessage());
        }
    }

    public static void logWithDiff(String action, String relatedRecordId,
            String details, String oldValueJSON, String newValueJSON) {
        log(action, relatedRecordId, details, oldValueJSON, newValueJSON);
    }

    public static void log(String action, String relatedRecordId,
            String details, String oldValueJSON, String newValueJSON) {

        HR_Audit_Log__c entry = new HR_Audit_Log__c(
            HR_Action__c            = action,
            HR_Performed_By__c      = UserInfo.getUserId(),
            HR_Timestamp__c         = Datetime.now(),
            HR_Details__c           = details,
            HR_Old_Value_JSON__c    = oldValueJSON,
            HR_New_Value_JSON__c    = newValueJSON,
            HR_Related_Record_Id__c = relatedRecordId
        );

        // Try to link to form if relatedRecordId is a form ID
        if (String.isNotBlank(relatedRecordId)) {
            try {
                List<HR_Form__c> forms = [
                    SELECT Id FROM HR_Form__c WHERE Id = :relatedRecordId LIMIT 1
                ];
                if (!forms.isEmpty()) entry.HR_Form__c = relatedRecordId;
            } catch (Exception ex) { /* not a form id */ }
        }

        // Debug mode verbose logging
        HR_Org_Settings__c settings = HR_Org_Settings__c.getInstance();
        if (settings != null && settings.HR_Enable_Debug_Mode__c) {
            System.debug(LoggingLevel.DEBUG,
                'HR_AUDIT | ' + action + ' | ' + relatedRecordId + ' | ' + details);
        }

        insert entry;
    }
}