/**
 * HR_FormDataMigrationBatch
 * One-time migration: copies HR_Logic_Rule__c records and HR_Form_Field__c sfFieldApi
 * mappings into HR_Form__c schema JSON blobs, then the four objects can be deleted.
 *
 * Execute via Anonymous Apex:
 *   Database.executeBatch(new HR_FormDataMigrationBatch(), 10);
 */
public without sharing class HR_FormDataMigrationBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id, HR_Schema_JSON__c, HR_Published_Schema_JSON__c
            FROM HR_Form__c
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<HR_Form__c> forms) {
        Set<Id> formIds = new Map<Id, HR_Form__c>(forms).keySet();

        // ── Load logic rules grouped by form ──────────────────────────────────
        Map<Id, List<HR_Logic_Rule__c>> rulesByForm = new Map<Id, List<HR_Logic_Rule__c>>();
        for (HR_Logic_Rule__c r : [
            SELECT Id, Name, HR_Form__c, HR_Order__c, HR_Is_Active__c,
                   HR_Trigger_Field__r.HR_API_Name__c,
                   HR_Operator__c, HR_Trigger_Value__c,
                   HR_Action__c, HR_Target_Type__c,
                   HR_Target_Field__r.HR_API_Name__c,
                   HR_Target_Section__r.Name,
                   HR_Action_Value__c, HR_Logic_Group__c
            FROM HR_Logic_Rule__c
            WHERE HR_Form__c IN :formIds
            ORDER BY HR_Order__c ASC
        ]) {
            if (!rulesByForm.containsKey(r.HR_Form__c)) {
                rulesByForm.put(r.HR_Form__c, new List<HR_Logic_Rule__c>());
            }
            rulesByForm.get(r.HR_Form__c).add(r);
        }

        // ── Load field-to-SF-object mappings grouped by form ──────────────────
        Map<Id, List<HR_Form_Field__c>> fieldsByForm = new Map<Id, List<HR_Form_Field__c>>();
        for (HR_Form_Field__c f : [
            SELECT HR_Form__c, HR_API_Name__c, HR_SF_Field_API__c
            FROM HR_Form_Field__c
            WHERE HR_Form__c IN :formIds
              AND HR_SF_Field_API__c != null
        ]) {
            if (!fieldsByForm.containsKey(f.HR_Form__c)) {
                fieldsByForm.put(f.HR_Form__c, new List<HR_Form_Field__c>());
            }
            fieldsByForm.get(f.HR_Form__c).add(f);
        }

        List<HR_Form__c> toUpdate = new List<HR_Form__c>();

        for (HR_Form__c form : forms) {
            Map<String, Object> draft = parseSchema(form.HR_Schema_JSON__c);
            Map<String, Object> pub   = parseSchema(form.HR_Published_Schema_JSON__c);

            Boolean changed = false;

            // 1. Merge logic rules from DB into JSON (DB is authoritative for migration)
            List<HR_Logic_Rule__c> dbRules = rulesByForm.containsKey(form.Id)
                ? rulesByForm.get(form.Id) : null;
            if (dbRules != null && !dbRules.isEmpty()) {
                List<Object> ruleList = buildRuleList(dbRules);
                draft.put('rules', ruleList);
                pub.put('rules', ruleList);
                changed = true;
            }

            // 2. Merge sfFieldApi into field objects within sections
            List<HR_Form_Field__c> dbFields = fieldsByForm.containsKey(form.Id)
                ? fieldsByForm.get(form.Id) : null;
            if (dbFields != null && !dbFields.isEmpty()) {
                Map<String, String> sfMap = new Map<String, String>();
                for (HR_Form_Field__c f : dbFields) {
                    sfMap.put(f.HR_API_Name__c, f.HR_SF_Field_API__c);
                }
                mergeSfFieldApi(draft, sfMap);
                mergeSfFieldApi(pub, sfMap);
                changed = true;
            }

            if (changed) {
                toUpdate.add(new HR_Form__c(
                    Id                        = form.Id,
                    HR_Schema_JSON__c         = JSON.serialize(draft),
                    HR_Published_Schema_JSON__c = JSON.serialize(pub)
                ));
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('HR_FormDataMigrationBatch complete. All logic rules and field mappings merged into JSON schemas.');
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static Map<String, Object> parseSchema(String schemaJson) {
        if (String.isBlank(schemaJson)) {
            return new Map<String, Object>{
                'sections' => new List<Object>(),
                'rules'    => new List<Object>()
            };
        }
        return (Map<String, Object>) JSON.deserializeUntyped(schemaJson);
    }

    private static List<Object> buildRuleList(List<HR_Logic_Rule__c> rules) {
        List<Object> ruleList = new List<Object>();
        for (HR_Logic_Rule__c r : rules) {
            String targetApi = r.HR_Target_Type__c == 'Field'
                ? r.HR_Target_Field__r.HR_API_Name__c
                : r.HR_Target_Section__r.Name;
            ruleList.add(new Map<String, Object>{
                'id'                  => r.Id,
                'name'                => r.Name,
                'triggerFieldApiName' => r.HR_Trigger_Field__r.HR_API_Name__c,
                'operator'            => r.HR_Operator__c,
                'triggerValue'        => r.HR_Trigger_Value__c,
                'action'              => r.HR_Action__c,
                'targetType'          => r.HR_Target_Type__c,
                'targetApiName'       => targetApi,
                'actionValue'         => r.HR_Action_Value__c,
                'logicGroup'          => r.HR_Logic_Group__c
            });
        }
        return ruleList;
    }

    private static void mergeSfFieldApi(Map<String, Object> schema, Map<String, String> sfMap) {
        if (!schema.containsKey('sections')) return;
        for (Object secObj : (List<Object>) schema.get('sections')) {
            Map<String, Object> sec = (Map<String, Object>) secObj;
            if (!sec.containsKey('fields')) continue;
            for (Object fldObj : (List<Object>) sec.get('fields')) {
                Map<String, Object> fld = (Map<String, Object>) fldObj;
                String apiName = (String) fld.get('apiName');
                if (sfMap.containsKey(apiName)) {
                    fld.put('sfFieldApi', sfMap.get(apiName));
                }
            }
        }
    }
}
