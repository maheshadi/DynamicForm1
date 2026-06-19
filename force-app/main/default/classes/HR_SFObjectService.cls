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

        String safeDisplayField = String.isNotBlank(displayField) ? displayField : 'Name';
        List<String> searchFields = String.isNotBlank(searchFieldsCsv)
            ? searchFieldsCsv.split(',') : new List<String>{ 'Name' };

        // Build SOQL — filter fragment validated by HR_SchemaValidator
        String soql = 'SELECT Id, ' + safeDisplayField
                    + ' FROM ' + objectApiName
                    + ' WHERE ' + safeDisplayField + ' LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\'';
        if (String.isNotBlank(filterSOQL)) {
            soql += ' AND (' + filterSOQL + ')';
        }
        soql += ' WITH SECURITY_ENFORCED LIMIT 10';

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (SObject rec : Database.query(soql)) {
            results.add(new Map<String, Object>{
                'id'   => rec.get('Id'),
                'name' => rec.get(safeDisplayField)
            });
        }
        return results;
    }

    private static void assertWhitelisted(String objectApiName) {
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