/**
 * HR_FormSchemaServiceTest
 * 100% coverage gate for HR_FormSchemaService and HR_SchemaValidator.
 */
@IsTest
private class HR_FormSchemaServiceTest {

    // ─── Test data factory ────────────────────────────────────────────────────

    private static HR_Form__c buildForm(String apiName) {
        return new HR_Form__c(
            Name                    = 'Test Form',
            HR_API_Name__c          = apiName,
            HR_Category__c          = 'General',
            HR_Status__c            = 'Draft',
            HR_Version__c           = 0,
            HR_Target_Object_API__c = 'Case',
            HR_Deployment_Target__c = 'LWC_Component',
            HR_On_Submit_Action__c  = 'Show_Message',
            HR_Allow_Draft_Save__c  = true,
            HR_Require_Confirmation__c = false,
            HR_Schema_JSON__c       = buildValidSchema()
        );
    }

    private static String buildValidSchema() {
        return JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'apiName' => 'section_1',
                    'title'   => 'Basic Info',
                    'fields'  => new List<Object>{
                        new Map<String, Object>{
                            'apiName' => 'employee_name',
                            'type'    => 'Text',
                            'label'   => 'Employee Name'
                        }
                    }
                }
            },
            'rules' => new List<Object>()
        });
    }

    // ─── saveForm ─────────────────────────────────────────────────────────────

    @IsTest
    static void testSaveFormCreate() {
        Map<String, Object> data = new Map<String, Object>{
            'name'               => 'Test Form',
            'apiName'            => 'test_form_create',
            'category'           => 'General',
            'description'        => 'Test',
            'tags'               => 'hr,test',
            'schemaJSON'         => buildValidSchema(),
            'targetObjectApi'    => 'Case',
            'deploymentTarget'   => 'LWC_Component',
            'onSubmitAction'     => 'Show_Message',
            'successMessage'     => 'Done',
            'redirectUrl'        => null,
            'allowDraftSave'     => true,
            'requireConfirmation'=> false,
            'recordTypeDevName'  => null
        };

        Test.startTest();
        String formId = HR_FormSchemaService.saveForm(data);
        Test.stopTest();

        System.assertNotEquals(null, formId, 'Form should be created');
        HR_Form__c saved = [SELECT HR_API_Name__c, HR_Status__c FROM HR_Form__c WHERE Id = :formId LIMIT 1];
        System.assertEquals('test_form_create', saved.HR_API_Name__c);
        System.assertEquals('Draft', saved.HR_Status__c);
    }

    @IsTest
    static void testSaveFormUpdate() {
        HR_Form__c form = buildForm('test_form_update');
        insert form;

        Map<String, Object> data = new Map<String, Object>{
            'id'                 => form.Id,
            'name'               => 'Updated Form',
            'apiName'            => 'test_form_update',
            'category'           => 'Onboarding',
            'description'        => 'Updated',
            'tags'               => null,
            'schemaJSON'         => buildValidSchema(),
            'targetObjectApi'    => 'Case',
            'deploymentTarget'   => 'LWC_Component',
            'onSubmitAction'     => 'Show_Message',
            'successMessage'     => null,
            'redirectUrl'        => null,
            'allowDraftSave'     => true,
            'requireConfirmation'=> false,
            'recordTypeDevName'  => null
        };

        Test.startTest();
        HR_FormSchemaService.saveForm(data);
        Test.stopTest();

        HR_Form__c updated = [SELECT Name, HR_Category__c FROM HR_Form__c WHERE Id = :form.Id LIMIT 1];
        System.assertEquals('Updated Form', updated.Name);
        System.assertEquals('Onboarding', updated.HR_Category__c);
    }

    @IsTest
    static void testSaveFormInvalidSchemaThrows() {
        Map<String, Object> data = new Map<String, Object>{
            'name'            => 'Bad Form',
            'apiName'         => 'bad_form',
            'category'        => 'General',
            'schemaJSON'      => 'NOT_JSON',
            'targetObjectApi' => 'Case',
            'deploymentTarget'=> 'LWC_Component',
            'onSubmitAction'  => 'Show_Message',
            'allowDraftSave'  => true,
            'requireConfirmation' => false
        };
        Test.startTest();
        try {
            HR_FormSchemaService.saveForm(data);
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected exception thrown');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetForm() {
        HR_Form__c form = buildForm('get_form_test');
        insert form;
        Test.startTest();
        HR_Form__c result = HR_FormSchemaService.getForm('get_form_test');
        Test.stopTest();
        System.assertEquals(form.Id, result.Id);
    }

    @IsTest
    static void testGetFormNotFound() {
        Test.startTest();
        try {
            HR_FormSchemaService.getForm('nonexistent_form_xyz');
            System.assert(false, 'Should throw');
        } catch (HR_FormSchemaService.HR_FormNotFoundException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void testCloneForm() {
        HR_Form__c form = buildForm('clone_source');
        insert form;
        Test.startTest();
        String cloneId = HR_FormSchemaService.cloneForm(form.Id);
        Test.stopTest();
        HR_Form__c clone = [SELECT Name, HR_Status__c FROM HR_Form__c WHERE Id = :cloneId LIMIT 1];
        System.assert(clone.Name.startsWith('Copy of'), 'Clone name prefix');
        System.assertEquals('Draft', clone.HR_Status__c);
    }

    @IsTest
    static void testDeleteForm() {
        HR_Form__c form = buildForm('delete_me');
        insert form;
        Test.startTest();
        HR_FormSchemaService.deleteForm(form.Id);
        Test.stopTest();
        Integer cnt = [SELECT COUNT() FROM HR_Form__c WHERE Id = :form.Id];
        System.assertEquals(0, cnt, 'Form should be deleted');
    }

    // ─── HR_SchemaValidator ───────────────────────────────────────────────────

    @IsTest
    static void testValidatorBlankSchema() {
        List<HR_SchemaValidator.ValidationError> errors =
            HR_SchemaValidator.validate('');
        System.assertEquals(1, errors.size());
        System.assertEquals('schema', errors[0].field);
    }

    @IsTest
    static void testValidatorInvalidJSON() {
        List<HR_SchemaValidator.ValidationError> errors =
            HR_SchemaValidator.validate('{bad json}');
        System.assertEquals(1, errors.size());
    }

    @IsTest
    static void testValidatorDuplicateApiName() {
        String schema = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'fields' => new List<Object>{
                        new Map<String, Object>{ 'apiName' => 'emp_name', 'type' => 'Text' },
                        new Map<String, Object>{ 'apiName' => 'emp_name', 'type' => 'Text' }
                    }
                }
            },
            'rules' => new List<Object>()
        });
        List<HR_SchemaValidator.ValidationError> errors = HR_SchemaValidator.validate(schema);
        System.assert(!errors.isEmpty(), 'Duplicate API name should fail');
    }

    @IsTest
    static void testValidatorSOQLInjection() {
        List<HR_SchemaValidator.ValidationError> errors =
            HR_SchemaValidator.validateSOQLFragment('Name = \'x\' UNION SELECT Id FROM User');
        System.assert(!errors.isEmpty(), 'UNION should be blocked');
    }

    @IsTest
    static void testValidatorValidSchema() {
        List<HR_SchemaValidator.ValidationError> errors =
            HR_SchemaValidator.validate(buildValidSchema());
        System.assertEquals(0, errors.size(), 'Valid schema should have no errors');
    }
}