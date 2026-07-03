/**
 * HR_SubmissionService
 * Validates, persists, and maps form submissions to target SObject.
 * Field-to-SF-object mappings are read from the published schema JSON (sfFieldApi property).
 */
public with sharing class HR_SubmissionService {

    @AuraEnabled
    public static String submitForm(String formApiName, String payloadJSON,
            Integer durationSec, String clientRequestId) {
        // 0. Access gate — view access is checked at render time, but submission
        // must be independently enforced server-side (client can be bypassed).
        HR_AccessService.assertCanSubmit(formApiName);

        // 0b. Idempotency: if this client request was already processed (double-click,
        // network retry), return the existing submission instead of creating a duplicate.
        if (String.isNotBlank(clientRequestId)) {
            List<HR_Form_Submission__c> existing = [
                SELECT Id FROM HR_Form_Submission__c
                WHERE HR_Client_Request_Id__c = :clientRequestId
                WITH SECURITY_ENFORCED LIMIT 1
            ];
            if (!existing.isEmpty()) return existing[0].Id;
        }

        // 1. Re-evaluate server-side logic rules to prevent client bypass
        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(payloadJSON);
        List<HR_SchemaValidator.ValidationError> errors =
            HR_LogicEngineService.validateSubmission(formApiName, payload);
        if (!errors.isEmpty()) {
            throw new AuraHandledException(JSON.serialize(errors));
        }

        // 2. Query form config — schema for field mapping comes from the immutable version snapshot
        HR_Form__c form = [
            SELECT Id, HR_Target_Object_API__c, HR_Record_Type_Dev_Name__c, HR_Version__c
            FROM HR_Form__c
            WHERE HR_API_Name__c = :formApiName
              AND HR_Status__c   = 'Published'
            WITH SECURITY_ENFORCED LIMIT 1
        ];

        // 3+4. Map payload to the primary target + any related records, then persist
        // the header. Savepoint covers the race where two identical requests pass the
        // idempotency pre-check: the loser's unique-key violation rolls back its
        // records too, leaving exactly one of each.
        Savepoint sp = Database.setSavepoint();
        try {
            MappedRecords recs = buildRecords(form, payload);

            SObjectAccessDecision dec = Security.stripInaccessible(AccessType.CREATABLE,
                new List<SObject>{ recs.primary });
            insert dec.getRecords()[0];
            String targetRecordId = (String) dec.getRecords()[0].get('Id');

            // Related records (Object.Field mappings): link each to the primary via its
            // auto-detected lookup, then insert together (mixed-type insert is fine).
            if (!recs.related.isEmpty()) {
                for (Integer i = 0; i < recs.related.size(); i++) {
                    recs.related[i].put(recs.relatedParentFields[i], targetRecordId);
                }
                SObjectAccessDecision relDec = Security.stripInaccessible(
                    AccessType.CREATABLE, recs.related);
                insert relDec.getRecords();
            }

            HR_Form_Submission__c sub = createSubmissionRecord(
                form, payloadJSON, targetRecordId, durationSec);
            sub.HR_Client_Request_Id__c = String.isNotBlank(clientRequestId) ? clientRequestId : null;
            insert sub;

            HR_AuditService.logAsync('Submission_Created', sub.Id, null);
            return sub.Id;
        } catch (DmlException e) {
            if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE && String.isNotBlank(clientRequestId)) {
                Database.rollback(sp);
                List<HR_Form_Submission__c> winner = [
                    SELECT Id FROM HR_Form_Submission__c
                    WHERE HR_Client_Request_Id__c = :clientRequestId
                    WITH SECURITY_ENFORCED LIMIT 1
                ];
                if (!winner.isEmpty()) return winner[0].Id;
            }
            throw e;
        }
    }

    @AuraEnabled
    public static String saveDraft(String formApiName, String payloadJSON) {
        // Repeated saves refine ONE draft per user per form (update in place) rather
        // than inserting a copy each time and burning through the draft cap.
        List<HR_Form_Submission__c> mine = [
            SELECT Id FROM HR_Form_Submission__c
            WHERE HR_Submitted_By__c = :UserInfo.getUserId()
              AND HR_Status__c = 'Draft'
              AND HR_Form__r.HR_API_Name__c = :formApiName
            WITH SECURITY_ENFORCED
            ORDER BY LastModifiedDate DESC LIMIT 1
        ];
        if (!mine.isEmpty()) {
            mine[0].HR_Payload_JSON__c = payloadJSON;
            update mine[0];
            return mine[0].Id;
        }

        // Enforce concurrent draft limit from custom setting (new drafts only)
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

    // Result of mapping the payload: one primary record plus related records whose
    // parent lookups (parallel list) are filled in after the primary insert.
    @TestVisible
    private class MappedRecords {
        public SObject primary;
        public List<SObject> related             = new List<SObject>();
        public List<String>  relatedParentFields = new List<String>();
    }

    /**
     * Builds the primary target record and any related-object records from the payload.
     * Mapping syntax on each form field (sfFieldApi):
     *   'Subject'                        → field on the primary target object
     *   'HRHD_FormData__c.Employee__c'   → field on a related object; one record per
     *                                      related object is created and linked to the
     *                                      primary via its lookup (auto-detected).
     */
    @TestVisible
    private static MappedRecords buildRecords(HR_Form__c form, Map<String, Object> payload) {
        MappedRecords result = new MappedRecords();
        String targetApi = form.HR_Target_Object_API__c;

        Schema.SObjectType targetType = Schema.getGlobalDescribe().get(targetApi);
        result.primary = targetType.newSObject();
        Map<String, Schema.SObjectField> targetFields = targetType.getDescribe().fields.getMap();

        if (String.isNotBlank(form.HR_Record_Type_Dev_Name__c)) {
            Id rtId = targetType.getDescribe()
                .getRecordTypeInfosByDeveloperName()
                .get(form.HR_Record_Type_Dev_Name__c)
                .getRecordTypeId();
            result.primary.put('RecordTypeId', rtId);
        }

        // Mappings come from the immutable published version snapshot — never from a
        // mutable field that could drift post-publish.
        // Named formDef (not "schema") so the Schema namespace isn't shadowed below.
        HR_FormSchema formDef = HR_FormSchema.parse(
            HR_PublishService.getActiveSchemaJSON(form.Id));

        Map<String, SObject> relatedByObject = new Map<String, SObject>();
        Map<String, Map<String, Schema.SObjectField>> relatedFieldMaps =
            new Map<String, Map<String, Schema.SObjectField>>();

        for (HR_FormSchema.Field fld : formDef.allFields()) {
            if (String.isBlank(fld.sfFieldApi)) continue;
            Object val = payload.get(fld.apiName);
            if (val == null) continue;

            String mapping = fld.sfFieldApi.trim();
            SObject rec;
            Map<String, Schema.SObjectField> fieldMap;
            String fieldApi;

            if (mapping.contains('.')) {
                String objApi = mapping.substringBefore('.');
                fieldApi      = mapping.substringAfter('.');
                if (objApi.equalsIgnoreCase(targetApi)) {
                    rec = result.primary;  fieldMap = targetFields;
                } else {
                    String key = objApi.toLowerCase();
                    if (!relatedByObject.containsKey(key)) {
                        // Related objects go through the same whitelist gate as targets —
                        // a tampered schema cannot write to arbitrary org objects.
                        HR_SFObjectService.assertWhitelisted(objApi);
                        Schema.SObjectType relType = Schema.getGlobalDescribe().get(objApi);
                        if (relType == null) {
                            throw new AuraHandledException('Unknown related object in mapping: ' + objApi);
                        }
                        Schema.DescribeSObjectResult relDescribe = relType.getDescribe();
                        relatedByObject.put(key, relType.newSObject());
                        relatedFieldMaps.put(key, relDescribe.fields.getMap());
                        result.related.add(relatedByObject.get(key));
                        result.relatedParentFields.add(findParentField(relDescribe, targetApi));
                    }
                    rec = relatedByObject.get(key);  fieldMap = relatedFieldMaps.get(key);
                }
            } else {
                rec = result.primary;  fieldMap = targetFields;  fieldApi = mapping;
            }

            // Per-field FLS: skip mappings the running user cannot create rather than
            // relying solely on the final stripInaccessible() over the whole record.
            Schema.SObjectField targetField = fieldMap.get(fieldApi.toLowerCase());
            if (targetField == null || !targetField.getDescribe().isCreateable()) continue;

            rec.put(targetField.getDescribe().getName(),
                    coerceValue(targetField.getDescribe(), val, fld.apiName));
        }
        return result;
    }

    // Finds the lookup on the related object that points at the primary target.
    // Prefers master-detail, then alphabetical order for determinism when several exist.
    @TestVisible
    private static String findParentField(
            Schema.DescribeSObjectResult childDescribe, String parentObjectApi) {
        List<String> masterDetail = new List<String>();
        List<String> lookups      = new List<String>();
        for (Schema.SObjectField f : childDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fr = f.getDescribe();
            if (fr.getType() != Schema.DisplayType.REFERENCE || !fr.isCreateable()) continue;
            for (Schema.SObjectType ref : fr.getReferenceTo()) {
                if (String.valueOf(ref).equalsIgnoreCase(parentObjectApi)) {
                    if (fr.getRelationshipOrder() != null) masterDetail.add(fr.getName());
                    else                                   lookups.add(fr.getName());
                }
            }
        }
        if (!masterDetail.isEmpty()) { masterDetail.sort(); return masterDetail[0]; }
        if (!lookups.isEmpty())      { lookups.sort();      return lookups[0]; }
        throw new AuraHandledException(
            'Related object ' + childDescribe.getName() + ' has no lookup to '
            + parentObjectApi + ' — cannot link it to the submission record.');
    }

    // Coerces a raw JSON payload value (String/Decimal/Boolean/List) to the target
    // field's type. Raw put() does not coerce, so a date string into a Date field
    // would otherwise throw an opaque "illegal assignment" at submit time.
    @TestVisible
    private static Object coerceValue(
            Schema.DescribeFieldResult fr, Object raw, String formFieldApi) {
        try {
            // Multi-select values arrive as a list → semicolon-join for (multi)picklists/text
            if (raw instanceof List<Object>) {
                List<String> parts = new List<String>();
                for (Object o : (List<Object>) raw) parts.add(String.valueOf(o));
                return String.join(parts, ';');
            }
            String s = String.valueOf(raw);
            switch on fr.getType() {
                when DATE {
                    return (raw instanceof Date) ? raw : Date.valueOf(s);
                }
                when DATETIME {
                    if (raw instanceof Datetime) return raw;
                    // lightning-input datetime sends ISO 8601 (with T/Z) — JSON parser handles it
                    return (Datetime) JSON.deserialize('"' + s + '"', Datetime.class);
                }
                when BOOLEAN {
                    return (raw instanceof Boolean) ? raw : Boolean.valueOf(s);
                }
                when DOUBLE, CURRENCY, PERCENT {
                    return (raw instanceof Decimal) ? raw : Decimal.valueOf(s.trim());
                }
                when INTEGER {
                    return (raw instanceof Integer) ? raw : Decimal.valueOf(s.trim()).intValue();
                }
                when else {
                    return s;   // STRING, TEXTAREA, PICKLIST, EMAIL, PHONE, URL, REFERENCE, ID
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException(
                'Value for form field "' + formFieldApi + '" is not valid for mapped field '
                + fr.getName() + ' (' + fr.getType() + '): ' + String.valueOf(raw));
        }
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