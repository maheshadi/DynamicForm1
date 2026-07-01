/**
 * HR_PublishService
 * Publishes a draft form: increments version, copies JSON to published snapshot,
 * creates HR_Form_Version__c, triggers LWC bundle generation note.
 */
public with sharing class HR_PublishService {

    @AuraEnabled
    public static void publishForm(String formApiName) {
        assertAdminPermission();

        HR_Form__c form = [
            SELECT Id, HR_Schema_JSON__c, HR_Version__c, HR_Status__c
            FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        // Validate schema before publish
        List<HR_SchemaValidator.ValidationError> errors =
            HR_SchemaValidator.validate(form.HR_Schema_JSON__c);
        if (!errors.isEmpty()) {
            throw new AuraHandledException(
                'Schema validation failed: ' + JSON.serialize(errors));
        }

        Decimal newVersion = (form.HR_Version__c == null ? 0 : form.HR_Version__c) + 1;

        // Deactivate prior active version
        List<HR_Form_Version__c> priorVersions = [
            SELECT Id FROM HR_Form_Version__c
            WHERE HR_Form__c = :form.Id AND HR_Is_Active_Version__c = true
            WITH SECURITY_ENFORCED
        ];
        for (HR_Form_Version__c v : priorVersions) {
            v.HR_Is_Active_Version__c = false;
        }
        if (!priorVersions.isEmpty()) {
            SObjectAccessDecision dec = Security.stripInaccessible(AccessType.UPDATABLE, priorVersions);
            update dec.getRecords();
        }

        // Create new version snapshot
        HR_Form_Version__c newVer = new HR_Form_Version__c(
            HR_Form__c             = form.Id,
            HR_Version_Number__c   = newVersion,
            HR_Schema_Snapshot__c  = form.HR_Schema_JSON__c,
            HR_Published_By__c     = UserInfo.getUserId(),
            HR_Published_Date__c   = Datetime.now(),
            HR_Environment__c      = getTargetEnvironment(),
            HR_Is_Active_Version__c = true
        );
        insert newVer;

        // Update form
        form.HR_Published_Schema_JSON__c = form.HR_Schema_JSON__c;
        form.HR_Status__c                = 'Published';
        form.HR_Version__c               = newVersion;
        form.HR_Last_Published_By__c     = UserInfo.getUserId();
        form.HR_Last_Published_Date__c   = Datetime.now();

        SObjectAccessDecision formDec = Security.stripInaccessible(
            AccessType.UPDATABLE, new List<SObject>{ form });
        update formDec.getRecords();

        HR_AuditService.logAsync('Form_Published', form.Id, null);
    }

    @AuraEnabled
    public static void archiveForm(String formApiName) {
        assertAdminPermission();
        HR_Form__c form = [SELECT Id, HR_Status__c FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName WITH SECURITY_ENFORCED LIMIT 1];
        form.HR_Status__c = 'Archived';
        SObjectAccessDecision dec = Security.stripInaccessible(
            AccessType.UPDATABLE, new List<SObject>{ form });
        update dec.getRecords();
        HR_AuditService.logAsync('Form_Archived', form.Id, null);
    }

    @AuraEnabled
    public static void rollbackToVersion(String formId, String versionId) {
        assertAdminPermission();

        HR_Form_Version__c ver = [
            SELECT HR_Schema_Snapshot__c, HR_Version_Number__c
            FROM HR_Form_Version__c
            WHERE Id = :versionId AND HR_Form__c = :formId
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        HR_Form__c form = [SELECT Id FROM HR_Form__c WHERE Id = :formId
            WITH SECURITY_ENFORCED LIMIT 1];
        form.HR_Schema_JSON__c = ver.HR_Schema_Snapshot__c;
        form.HR_Status__c      = 'Draft';

        SObjectAccessDecision dec = Security.stripInaccessible(
            AccessType.UPDATABLE, new List<SObject>{ form });
        update dec.getRecords();

        HR_AuditService.logAsync('Form_Rolled_Back', formId, null);
    }

    // ─── Immutable schema access ───────────────────────────────────────────────
    // The renderer and submission pipeline must read the schema that was actually
    // published from the immutable HR_Form_Version__c snapshot, not from
    // HR_Form__c.HR_Published_Schema_JSON__c (a plain field that could be edited
    // or corrupted outside the publish flow).

    public static String getActiveSchemaJSON(Id formId) {
        List<HR_Form_Version__c> versions = [
            SELECT HR_Schema_Snapshot__c
            FROM HR_Form_Version__c
            WHERE HR_Form__c = :formId AND HR_Is_Active_Version__c = true
            WITH SECURITY_ENFORCED LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0].HR_Schema_Snapshot__c;
    }

    // ─── Private helpers ───────────────────────────────────────────────────────

    private static void assertAdminPermission() {
        if (!FeatureManagement.checkPermission('HR_Form_Admin')) {
            throw new AuraHandledException('HR_Form_Admin permission required to publish forms.');
        }
    }

    private static String getTargetEnvironment() {
        Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
        return org.IsSandbox ? 'Sandbox' : 'Production';
    }
}