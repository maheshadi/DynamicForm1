/**
 * HR_VersionPrunerBatch
 * Scheduled batch that deletes oldest HR_Form_Version__c records
 * beyond the max retention limit per form.
 * Schedule: System.schedule('FC Version Pruner', '0 0 2 * * ?', new HR_VersionPrunerBatch());
 */
public class HR_VersionPrunerBatch implements Database.Batchable<SObject>, Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new HR_VersionPrunerBatch(), 50);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, HR_Version_Number__c, HR_Form__c, HR_Is_Active_Version__c
            FROM HR_Form_Version__c
            WHERE HR_Is_Active_Version__c = false
            ORDER BY HR_Form__c, HR_Version_Number__c ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<HR_Form_Version__c> versions = new List<HR_Form_Version__c>();
        for (SObject s : scope) { versions.add((HR_Form_Version__c) s); }
        Integer maxVersions = getMaxVersions();

        // Group versions by form
        Map<Id, List<HR_Form_Version__c>> versionsByForm =
            new Map<Id, List<HR_Form_Version__c>>();
        for (HR_Form_Version__c v : versions) {
            if (!versionsByForm.containsKey(v.HR_Form__c)) {
                versionsByForm.put(v.HR_Form__c, new List<HR_Form_Version__c>());
            }
            versionsByForm.get(v.HR_Form__c).add(v);
        }

        List<HR_Form_Version__c> toDelete = new List<HR_Form_Version__c>();
        for (Id formId : versionsByForm.keySet()) {
            List<HR_Form_Version__c> allVersions = versionsByForm.get(formId);
            // Count total (including active) to determine excess
            Integer totalCount = [
                SELECT COUNT() FROM HR_Form_Version__c WHERE HR_Form__c = :formId
            ];
            Integer excess = totalCount - maxVersions;
            if (excess > 0) {
                // allVersions is already sorted ASC by version number (oldest first)
                Integer toRemove = Math.min(excess, allVersions.size());
                for (Integer i = 0; i < toRemove; i++) {
                    toDelete.add(allVersions[i]);
                }
            }
        }

        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'HR_VersionPrunerBatch complete.');
    }

    private static Integer getMaxVersions() {
        List<HR_Builder_Config__mdt> cfgs = [
            SELECT HR_Max_Versions_Per_Form__c FROM HR_Builder_Config__mdt
            WHERE DeveloperName = 'Default' LIMIT 1
        ];
        return (cfgs.isEmpty() || cfgs[0].HR_Max_Versions_Per_Form__c == null)
            ? 20 : Integer.valueOf(cfgs[0].HR_Max_Versions_Per_Form__c);
    }
}