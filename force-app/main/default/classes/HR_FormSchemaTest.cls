/**
 * HR_FormSchemaTest
 * Covers the typed schema wrapper: happy-path parse, tolerant handling of
 * blank/malformed/partial blobs, and the accessor helpers.
 */
@IsTest
private class HR_FormSchemaTest {

    private static String fullSchema() {
        return JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'id'     => 's_1',
                    'title'  => 'Info',
                    'fields' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 'f_1', 'apiName' => 'emp_name', 'type' => 'Text',
                            'label' => 'Employee Name', 'sfFieldApi' => 'Subject',
                            'required' => true, 'defaultValue' => 'n/a'
                        },
                        new Map<String, Object>{
                            'id' => 'f_2', 'apiName' => 'dept', 'type' => 'Dropdown',
                            'label' => 'Department'
                        }
                    }
                },
                new Map<String, Object>{
                    'id'     => 's_2',
                    'title'  => 'Extra',
                    'fields' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 'f_3', 'apiName' => 'notes', 'type' => 'TextArea'
                        }
                    }
                }
            },
            'rules' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'r_1', 'name' => 'Require notes',
                    'action' => 'Make_Required', 'targetType' => 'Field',
                    'targetApiName' => 'notes', 'triggerFieldApiName' => 'dept',
                    'operator' => 'equals', 'triggerValue' => 'HR'
                },
                new Map<String, Object>{
                    'id' => 'r_2', 'name' => 'Disabled rule',
                    'action' => 'Make_Required', 'targetApiName' => 'emp_name',
                    'isActive' => false
                },
                new Map<String, Object>{
                    'id' => 'r_3', 'name' => 'Hide rule',
                    'action' => 'Hide', 'targetApiName' => 'notes'
                }
            }
        });
    }

    @IsTest
    static void testParseFullSchema() {
        HR_FormSchema schema = HR_FormSchema.parse(fullSchema());

        System.assertEquals(2, schema.sections.size(), 'Both sections parsed');
        System.assertEquals('Info', schema.sections[0].title);
        System.assertEquals(3, schema.allFields().size(), 'Fields flattened across sections');
        System.assertEquals(3, schema.rules.size(), 'All rules parsed');

        HR_FormSchema.Field f = schema.fieldByApiName('emp_name');
        System.assertNotEquals(null, f, 'Lookup by API name');
        System.assertEquals('Text', f.fieldType);
        System.assertEquals('Subject', f.sfFieldApi);
        System.assertEquals(true, f.required);
        System.assertEquals('n/a', f.defaultValue);

        HR_FormSchema.Field optional = schema.fieldByApiName('dept');
        System.assertEquals(false, optional.required, 'Missing required defaults to false');
        System.assertEquals(null, optional.sfFieldApi, 'Missing mapping stays null');
    }

    @IsTest
    static void testActiveRulesByAction() {
        HR_FormSchema schema = HR_FormSchema.parse(fullSchema());

        List<HR_FormSchema.Rule> required = schema.activeRulesByAction('Make_Required');
        System.assertEquals(1, required.size(), 'Explicitly inactive rule excluded');
        System.assertEquals('r_1', required[0].id);
        System.assertNotEquals(null, required[0].raw, 'Raw map retained for evaluators');
        System.assertEquals('equals', (String) required[0].raw.get('operator'));

        System.assertEquals(1, schema.activeRulesByAction('Hide').size(),
            'Missing isActive counts as active');
    }

    @IsTest
    static void testParseToleratesBadInput() {
        System.assertEquals(0, HR_FormSchema.parse(null).sections.size(), 'null blob');
        System.assertEquals(0, HR_FormSchema.parse('').sections.size(), 'blank blob');
        System.assertEquals(0, HR_FormSchema.parse('{not json').rules.size(), 'malformed blob');
        System.assertEquals(0, HR_FormSchema.parse('{"sections":"oops","rules":42}')
            .allFields().size(), 'wrong-typed keys ignored');

        HR_FormSchema partial = HR_FormSchema.parse('{"sections":[{"title":"NoFields"}]}');
        System.assertEquals(1, partial.sections.size(), 'Section without fields parses');
        System.assertEquals(0, partial.rules.size(), 'Missing rules key tolerated');
        System.assertEquals(null, partial.fieldByApiName('anything'), 'Absent field is null');
    }
}
