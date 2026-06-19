/**
 * HR_AccessService
 * Evaluates HR_Form_Access__c rules against the running user's
 * Profile, Permission Sets, and Roles.
 */
public with sharing class HR_AccessService {

    public static void assertCanView(String formApiName) {
        if (!canView(formApiName)) {
            throw new AuraHandledException('You do not have access to view form: ' + formApiName);
        }
    }

    public static void assertCanSubmit(String formApiName) {
        if (!canSubmit(formApiName)) {
            throw new AuraHandledException('You do not have permission to submit form: ' + formApiName);
        }
    }

    public static Boolean canView(String formApiName) {
        return checkAccess(formApiName, 'HR_Can_View__c');
    }

    public static Boolean canSubmit(String formApiName) {
        return checkAccess(formApiName, 'HR_Can_Submit__c');
    }

    @AuraEnabled(cacheable=false)
    public static List<HR_Form__c> getAccessibleForms(String category) {
        // Get all published forms and filter by access rules
        List<HR_Form__c> allForms = HR_FormSchemaService.getFormLibrary(category, 'Published');
        List<HR_Form__c> accessible = new List<HR_Form__c>();
        for (HR_Form__c f : allForms) {
            if (canView(f.HR_API_Name__c)) {
                accessible.add(f);
            }
        }
        return accessible;
    }

    // ─── Private ───────────────────────────────────────────────────────────────

    private static Boolean checkAccess(String formApiName, String accessField) {
        // Admins with HR_Form_Admin always have access
        if (FeatureManagement.checkPermission('HR_Form_Admin')) return true;

        HR_Form__c form;
        try {
            form = [SELECT Id FROM HR_Form__c
                WHERE HR_API_Name__c = :formApiName WITH SECURITY_ENFORCED LIMIT 1];
        } catch (Exception e) { return false; }

        Set<String> principalIds = getUserPrincipalIds();

        String soql = 'SELECT Id FROM HR_Form_Access__c '
                    + 'WHERE HR_Form__c = :form.Id '
                    + 'AND ' + accessField + ' = true '
                    + 'AND HR_Principal_Id__c IN :principalIds '
                    + 'WITH SECURITY_ENFORCED LIMIT 1';

        List<HR_Form_Access__c> matches = Database.query(soql);
        // If no access records configured, treat as open (public)
        Integer totalRules = [SELECT COUNT() FROM HR_Form_Access__c
            WHERE HR_Form__c = :form.Id WITH SECURITY_ENFORCED];
        return totalRules == 0 || !matches.isEmpty();
    }

    private static Set<String> getUserPrincipalIds() {
        Set<String> ids = new Set<String>();

        // Profile
        User u = [SELECT ProfileId, UserRoleId FROM User
            WHERE Id = :UserInfo.getUserId() WITH SECURITY_ENFORCED LIMIT 1];
        ids.add(u.ProfileId);
        if (u.UserRoleId != null) ids.add(u.UserRoleId);

        // Permission Sets
        for (PermissionSetAssignment psa : [
            SELECT PermissionSetId FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            WITH SECURITY_ENFORCED
        ]) {
            ids.add(psa.PermissionSetId);
        }

        // Public Groups
        for (GroupMember gm : [
            SELECT GroupId FROM GroupMember
            WHERE UserOrGroupId = :UserInfo.getUserId()
            WITH SECURITY_ENFORCED
        ]) {
            ids.add(gm.GroupId);
        }

        return ids;
    }
}