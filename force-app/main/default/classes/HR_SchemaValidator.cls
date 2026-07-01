/**
 * HR_SchemaValidator
 * Validates a form JSON schema blob: checks required properties,
 * field type registry, rule target references, max limits.
 * Returns List<ValidationError> — empty means valid.
 */
public with sharing class HR_SchemaValidator {

    public class ValidationError {
        @AuraEnabled public String field   { get; set; }
        @AuraEnabled public String message { get; set; }
        public ValidationError(String field, String message) {
            this.field   = field;
            this.message = message;
        }
    }

    // ─── Top-level validate ────────────────────────────────────────────────────

    public static List<ValidationError> validate(String schemaJSON) {
        List<ValidationError> errors = new List<ValidationError>();

        if (String.isBlank(schemaJSON)) {
            errors.add(new ValidationError('schema', 'Schema JSON cannot be blank.'));
            return errors;
        }

        // Guard against oversized blob
        HR_Builder_Config__mdt cfg = getConfig();
        if (schemaJSON.length() > (Integer) cfg.HR_Schema_JSON_Max_Chars__c) {
            errors.add(new ValidationError('schema',
                'Schema JSON exceeds maximum allowed size of '
                + cfg.HR_Schema_JSON_Max_Chars__c + ' characters.'));
            return errors;
        }

        Map<String, Object> schema;
        try {
            schema = (Map<String, Object>) JSON.deserializeUntyped(schemaJSON);
        } catch (Exception e) {
            errors.add(new ValidationError('schema', 'Schema JSON is not valid JSON: ' + e.getMessage()));
            return errors;
        }

        // Validate sections
        List<Object> sections = schema.containsKey('sections')
            ? (List<Object>) schema.get('sections') : new List<Object>();

        if (sections.size() > (Integer) cfg.HR_Max_Sections_Per_Form__c) {
            errors.add(new ValidationError('sections',
                'Max ' + cfg.HR_Max_Sections_Per_Form__c + ' sections allowed per form.'));
        }

        Set<String> validFieldTypes = getValidFieldTypes();
        Set<String> fieldApiNames   = new Set<String>();
        Integer totalFields = 0;

        for (Object secObj : sections) {
            Map<String, Object> sec = (Map<String, Object>) secObj;
            List<Object> fields = sec.containsKey('fields')
                ? (List<Object>) sec.get('fields') : new List<Object>();
            totalFields += fields.size();

            for (Object fldObj : fields) {
                errors.addAll(validateField((Map<String, Object>) fldObj,
                    validFieldTypes, fieldApiNames));
            }
        }

        if (totalFields > (Integer) cfg.HR_Max_Fields_Per_Form__c) {
            errors.add(new ValidationError('fields',
                'Max ' + cfg.HR_Max_Fields_Per_Form__c + ' fields allowed per form.'));
        }

        // Validate logic rules
        List<Object> rules = schema.containsKey('rules')
            ? (List<Object>) schema.get('rules') : new List<Object>();
        if (rules.size() > (Integer) cfg.HR_Max_Rules_Per_Form__c) {
            errors.add(new ValidationError('rules',
                'Max ' + cfg.HR_Max_Rules_Per_Form__c + ' logic rules allowed per form.'));
        }
        for (Object ruleObj : rules) {
            errors.addAll(validateRule((Map<String, Object>) ruleObj, fieldApiNames));
        }

        return errors;
    }

    // ─── Field-level ──────────────────────────────────────────────────────────

    public static List<ValidationError> validateField(
            Map<String, Object> field,
            Set<String> validFieldTypes,
            Set<String> seenApiNames) {

        List<ValidationError> errors = new List<ValidationError>();
        String apiName = (String) field.get('apiName');

        if (String.isBlank(apiName)) {
            errors.add(new ValidationError('field.apiName', 'Field API Name is required.'));
            return errors;
        }
        if (!Pattern.matches('^[a-z][a-z0-9_]*$', apiName)) {
            errors.add(new ValidationError('field.' + apiName,
                'API Name must match ^[a-z][a-z0-9_]*$'));
        }
        if (seenApiNames.contains(apiName)) {
            errors.add(new ValidationError('field.' + apiName,
                'Duplicate field API name within form: ' + apiName));
        }
        seenApiNames.add(apiName);

        String fieldType = (String) field.get('type');
        if (String.isBlank(fieldType) || !validFieldTypes.contains(fieldType.toLowerCase())) {
            errors.add(new ValidationError('field.' + apiName,
                'Unknown field type: ' + fieldType));
        }

        return errors;
    }

    // ─── Rule-level ───────────────────────────────────────────────────────────

    public static List<ValidationError> validateRule(
            Map<String, Object> rule, Set<String> fieldApiNames) {

        List<ValidationError> errors = new List<ValidationError>();
        String triggerField = (String) rule.get('triggerFieldApiName');
        String targetType   = (String) rule.get('targetType');
        String targetApi    = (String) rule.get('targetApiName');

        if (String.isBlank(triggerField) || !fieldApiNames.contains(triggerField)) {
            errors.add(new ValidationError('rule.triggerField',
                'Rule trigger field not found in form: ' + triggerField));
        }
        if (targetType == 'Field' && (String.isBlank(targetApi) || !fieldApiNames.contains(targetApi))) {
            errors.add(new ValidationError('rule.targetField',
                'Rule target field not found in form: ' + targetApi));
        }

        // Additional AND/OR conditions (see HR_LogicEngineService.conditionsMet)
        if (rule.get('additionalConditions') != null) {
            for (Object condObj : (List<Object>) rule.get('additionalConditions')) {
                Map<String, Object> cond = (Map<String, Object>) condObj;
                String condField = (String) cond.get('triggerFieldApiName');
                if (String.isBlank(condField) || !fieldApiNames.contains(condField)) {
                    errors.add(new ValidationError('rule.additionalCondition',
                        'Rule condition field not found in form: ' + condField));
                }
            }
        }

        // Validate SOQL filter fragments for injection risks
        String filterSOQL = (String) rule.get('lookupFilterSOQL');
        if (String.isNotBlank(filterSOQL)) {
            errors.addAll(validateSOQLFragment(filterSOQL));
        }

        return errors;
    }

    // ─── SOQL fragment safety ─────────────────────────────────────────────────

    public static List<ValidationError> validateSOQLFragment(String fragment) {
        List<ValidationError> errors = new List<ValidationError>();
        String upper = fragment.toUpperCase();
        // Block dangerous keywords
        List<String> blocked = new List<String>{
            'DELETE', 'INSERT', 'UPDATE', 'UPSERT', 'MERGE',
            'DROP', 'CREATE', 'ALTER', '$USER', 'UNION', 'SELECT'
        };
        for (String kw : blocked) {
            if (upper.contains(kw)) {
                errors.add(new ValidationError('lookupFilter',
                    'SOQL filter contains disallowed keyword: ' + kw));
            }
        }
        return errors;
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static HR_Builder_Config__mdt getConfig() {
        List<HR_Builder_Config__mdt> cfgs = [
            SELECT HR_Max_Fields_Per_Form__c, HR_Max_Sections_Per_Form__c,
                   HR_Max_Rules_Per_Form__c, HR_Schema_JSON_Max_Chars__c
            FROM HR_Builder_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        return cfgs.isEmpty() ? new HR_Builder_Config__mdt(
            HR_Max_Fields_Per_Form__c   = 200,
            HR_Max_Sections_Per_Form__c = 20,
            HR_Max_Rules_Per_Form__c    = 50,
            HR_Schema_JSON_Max_Chars__c = 131072
        ) : cfgs[0];
    }

    private static Set<String> getValidFieldTypes() {
        Set<String> types = new Set<String>();
        // Load from CMDT (case-insensitive — store lowercase)
        for (HR_Field_Type_Config__mdt ftc : [
            SELECT HR_Type_API__c FROM HR_Field_Type_Config__mdt
            WHERE HR_Is_Active__c = true
        ]) {
            if (String.isNotBlank(ftc.HR_Type_API__c)) {
                types.add(ftc.HR_Type_API__c.toLowerCase());
            }
        }
        // Hardcoded fallback — covers both PascalCase and lowercase variants
        if (types.isEmpty()) {
            types.addAll(new Set<String>{
                'text_input','text','number','currency','date_picker','date','datetime',
                'email','phone','url','text_area','textarea','rich_text','richtext',
                'dropdown','radio_group','radio','checkbox','multi_select','multiselect',
                'lookup','current_user','currentuser','record_field','recordfield',
                'section_header','sectionheader','info_block','infobox','instructions',
                'divider','file_upload','fileupload','percentage'
            });
        }
        return types;
    }
}