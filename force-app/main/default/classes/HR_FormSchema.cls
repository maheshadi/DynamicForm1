/**
 * HR_FormSchema
 * Typed domain wrapper over the form schema JSON blob (HR_Schema_JSON__c /
 * HR_Form_Version__c.HR_Schema_Snapshot__c).
 *
 * Parse the blob once with HR_FormSchema.parse(), then use typed accessors
 * instead of scattering (String) map.get(...) casts across services — the
 * stringly-typed access pattern is where most schema-shape defects came from.
 *
 * Parsing is tolerant by design: unknown keys are ignored, missing keys get
 * safe defaults, and a malformed blob yields an empty schema rather than an
 * exception (validation of schema content is HR_SchemaValidator's job).
 *
 * Note: rules keep a reference to their raw JSON map (Rule.raw) so evaluators
 * that still operate on untyped maps (HR_LogicEngineService.conditionsMet)
 * work unchanged during incremental adoption.
 */
public with sharing class HR_FormSchema {

    public List<Section> sections = new List<Section>();
    public List<Rule>    rules    = new List<Rule>();

    private Map<String, Field> fieldsByApiName = new Map<String, Field>();

    // ─── Typed shapes ──────────────────────────────────────────────────────────

    public class Section {
        public String id;
        public String title;
        public List<Field> fields = new List<Field>();
    }

    public class Field {
        public String  id;
        public String  apiName;
        public String  fieldType;      // JSON key "type" (reserved word in Apex)
        public String  label;
        public String  sfFieldApi;     // target SObject field mapping
        public Boolean required = false;
        public Object  defaultValue;
    }

    public class Rule {
        public String  id;
        public String  name;
        public String  action;
        public String  targetType;
        public String  targetApiName;
        public String  triggerFieldApiName;
        public Boolean isActive = true;         // only explicit false deactivates
        public Map<String, Object> raw;         // original JSON map for evaluators
    }

    // ─── Parsing ───────────────────────────────────────────────────────────────

    public static HR_FormSchema parse(String schemaJSON) {
        HR_FormSchema result = new HR_FormSchema();
        if (String.isBlank(schemaJSON)) return result;

        Map<String, Object> root;
        try {
            root = (Map<String, Object>) JSON.deserializeUntyped(schemaJSON);
        } catch (Exception e) {
            return result;   // malformed blob → empty schema (validator reports it)
        }

        if (root.get('sections') instanceof List<Object>) {
            for (Object secObj : (List<Object>) root.get('sections')) {
                if (!(secObj instanceof Map<String, Object>)) continue;
                result.sections.add(result.parseSection((Map<String, Object>) secObj));
            }
        }
        if (root.get('rules') instanceof List<Object>) {
            for (Object ruleObj : (List<Object>) root.get('rules')) {
                if (!(ruleObj instanceof Map<String, Object>)) continue;
                result.rules.add(parseRule((Map<String, Object>) ruleObj));
            }
        }
        return result;
    }

    private Section parseSection(Map<String, Object> src) {
        Section sec = new Section();
        sec.id    = str(src.get('id'));
        sec.title = str(src.get('title'));
        if (src.get('fields') instanceof List<Object>) {
            for (Object fldObj : (List<Object>) src.get('fields')) {
                if (!(fldObj instanceof Map<String, Object>)) continue;
                Field f = parseField((Map<String, Object>) fldObj);
                sec.fields.add(f);
                if (String.isNotBlank(f.apiName)) {
                    fieldsByApiName.put(f.apiName, f);
                }
            }
        }
        return sec;
    }

    private static Field parseField(Map<String, Object> src) {
        Field f = new Field();
        f.id           = str(src.get('id'));
        f.apiName      = str(src.get('apiName'));
        f.fieldType    = str(src.get('type'));
        f.label        = str(src.get('label'));
        f.sfFieldApi   = str(src.get('sfFieldApi'));
        f.required     = src.get('required') == true;
        f.defaultValue = src.get('defaultValue');
        return f;
    }

    private static Rule parseRule(Map<String, Object> src) {
        Rule r = new Rule();
        r.id                  = str(src.get('id'));
        r.name                = str(src.get('name'));
        r.action              = str(src.get('action'));
        r.targetType          = str(src.get('targetType'));
        r.targetApiName       = str(src.get('targetApiName'));
        r.triggerFieldApiName = str(src.get('triggerFieldApiName'));
        r.isActive            = src.get('isActive') != false;
        r.raw                 = src;
        return r;
    }

    private static String str(Object val) {
        return val == null ? null : String.valueOf(val);
    }

    // ─── Accessors ─────────────────────────────────────────────────────────────

    /** All fields across all sections, in render order. */
    public List<Field> allFields() {
        List<Field> result = new List<Field>();
        for (Section sec : sections) result.addAll(sec.fields);
        return result;
    }

    /** O(1) lookup by field API name; null when absent. */
    public Field fieldByApiName(String apiName) {
        return fieldsByApiName.get(apiName);
    }

    /** Active rules with the given action (missing isActive counts as active). */
    public List<Rule> activeRulesByAction(String action) {
        List<Rule> result = new List<Rule>();
        for (Rule r : rules) {
            if (r.isActive && r.action == action) result.add(r);
        }
        return result;
    }
}
