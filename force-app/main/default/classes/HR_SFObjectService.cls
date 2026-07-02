/**
 * HR_SFObjectService
 * Wrapper around Schema.describeSObjectType().
 * Returns field lists, picklist values, record types for builder dropdowns.
 */
public with sharing class HR_SFObjectService {

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getWhitelistedObjects() {
        List<HR_Object_Whitelist__mdt> whitelist = [
            SELECT HR_Object_API_Name__c, HR_Display_Label__c,
                   HR_Allow_As_Target__c, HR_Allow_As_Lookup__c
            FROM HR_Object_Whitelist__mdt
            WHERE HR_Is_Active__c = true
            ORDER BY HR_Display_Label__c ASC
        ];
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (HR_Object_Whitelist__mdt w : whitelist) {
            result.add(new Map<String, Object>{
                'apiName'        => w.HR_Object_API_Name__c,
                'label'          => w.HR_Display_Label__c,
                'allowAsTarget'  => w.HR_Allow_As_Target__c,
                'allowAsLookup'  => w.HR_Allow_As_Lookup__c
            });
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> describeObject(String objectApiName) {
        assertWhitelisted(objectApiName);
        Schema.DescribeSObjectResult dr = Schema.getGlobalDescribe()
            .get(objectApiName).getDescribe();

        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        for (Schema.SObjectField f : dr.fields.getMap().values()) {
            Schema.DescribeFieldResult fr = f.getDescribe();
            if (fr.isAccessible()) {
                fields.add(new Map<String, Object>{
                    'apiName'  => fr.getName(),
                    'label'    => fr.getLabel(),
                    'type'     => String.valueOf(fr.getType()),
                    'updateable' => fr.isUpdateable(),
                    'createable' => fr.isCreateable()
                });
            }
        }
        return new Map<String, Object>{
            'label'  => dr.getLabel(),
            'fields' => fields
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getPicklistValues(
            String objectApiName, String fieldApiName) {
        assertWhitelisted(objectApiName);
        Schema.DescribeFieldResult fr = Schema.getGlobalDescribe()
            .get(objectApiName).getDescribe()
            .fields.getMap().get(fieldApiName).getDescribe();

        List<Map<String, Object>> values = new List<Map<String, Object>>();
        for (Schema.PicklistEntry pe : fr.getPicklistValues()) {
            if (pe.isActive()) {
                values.add(new Map<String, Object>{
                    'label'     => pe.getLabel(),
                    'value'     => pe.getValue(),
                    'isDefault' => pe.isDefaultValue()
                });
            }
        }
        return values;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getRecordTypes(String objectApiName) {
        assertWhitelisted(objectApiName);
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Schema.RecordTypeInfo rt :
             Schema.getGlobalDescribe().get(objectApiName)
             .getDescribe().getRecordTypeInfos()) {
            if (rt.isAvailable() && !rt.isMaster()) {
                result.add(new Map<String, Object>{
                    'label'    => rt.getName(),
                    'devName'  => rt.getDeveloperName(),
                    'recordTypeId' => rt.getRecordTypeId()
                });
            }
        }
        return result;
    }

    public static List<Map<String, Object>> lookupSearch(
            String objectApiName, String searchTerm,
            String displayField, String searchFieldsCsv, String filterSOQL) {

        assertWhitelisted(objectApiName);

        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectApiName).getDescribe().fields.getMap();

        // Field identifiers are resolved through describe (canonical name, FLS-checked)
        // so user-supplied strings are never interpolated into SOQL directly.
        String safeDisplayField = resolveFieldIdentifier(fieldMap,
            String.isNotBlank(displayField) ? displayField : 'Name');

        List<String> searchFields = new List<String>();
        if (String.isNotBlank(searchFieldsCsv)) {
            for (String f : searchFieldsCsv.split(',')) {
                if (String.isNotBlank(f)) searchFields.add(resolveFieldIdentifier(fieldMap, f.trim()));
            }
        }
        if (searchFields.isEmpty()) searchFields.add(safeDisplayField);

        // Runtime defense-in-depth: the filter fragment is validated at schema-save
        // time, but re-validate here in case the stored schema was tampered with.
        if (String.isNotBlank(filterSOQL)
                && !HR_SchemaValidator.validateSOQLFragment(filterSOQL).isEmpty()) {
            throw new AuraHandledException('Lookup filter contains disallowed SOQL.');
        }

        String likeTerm = '%' + searchTerm + '%';   // bound, not interpolated
        List<String> conditions = new List<String>();
        for (String f : searchFields) {
            conditions.add(f + ' LIKE :likeTerm');
        }

        String soql = 'SELECT Id, ' + safeDisplayField
                    + ' FROM ' + objectApiName
                    + ' WHERE (' + String.join(conditions, ' OR ') + ')';
        if (String.isNotBlank(filterSOQL)) {
            soql += ' AND (' + filterSOQL + ')';
        }
        soql += ' WITH SECURITY_ENFORCED ORDER BY ' + safeDisplayField + ' LIMIT 10';

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (SObject rec : Database.query(soql)) {
            results.add(new Map<String, Object>{
                'id'    => rec.get('Id'),
                'label' => rec.get(safeDisplayField)
            });
        }
        return results;
    }

    // Resolves a field name to its canonical describe name, enforcing existence + FLS.
    // Throws for unknown/inaccessible fields — never returns raw user input.
    private static String resolveFieldIdentifier(
            Map<String, Schema.SObjectField> fieldMap, String fieldName) {
        Schema.SObjectField f = fieldMap.get(fieldName.toLowerCase());
        if (f == null || !f.getDescribe().isAccessible()) {
            throw new AuraHandledException('Invalid or inaccessible lookup field: ' + fieldName);
        }
        return f.getDescribe().getName();
    }

    public static void assertWhitelisted(String objectApiName) {
        List<HR_Object_Whitelist__mdt> wl = [
            SELECT Id FROM HR_Object_Whitelist__mdt
            WHERE HR_Object_API_Name__c = :objectApiName
              AND HR_Is_Active__c = true
            LIMIT 1
        ];
        if (wl.isEmpty()) {
            throw new AuraHandledException('Object not whitelisted: ' + objectApiName);
        }
    }
}