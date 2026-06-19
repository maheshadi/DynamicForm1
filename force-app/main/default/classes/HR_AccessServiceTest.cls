/**
 * HR_AccessServiceTest
 */
@IsTest
private class HR_AccessServiceTest {

    private static HR_Form__c createForm(String apiName) {
        HR_Form__c form = new HR_Form__c(
            Name = 'Access Test', HR_API_Name__c = apiName,
            HR_Category__c = 'General', HR_Status__c = 'Published',
            HR_Version__c = 1, HR_Target_Object_API__c = 'Case',
            HR_Deployment_Target__c = 'LWC_Component',
            HR_On_Submit_Action__c = 'Show_Message',
            HR_Allow_Draft_Save__c = true, HR_Require_Confirmation__c = false,
            HR_Schema_JSON__c = '{"sections":[],"rules":[]}',
            HR_Published_Schema_JSON__c = '{"sections":[],"rules":[]}'
        );
        insert form;
        return form;
    }

    @IsTest
    static void testCanViewNoAccessRules() {
        // With no HR_Form_Access__c records, any user can view (open form)
        HR_Form__c form = createForm('open_form_access_test');
        Test.startTest();
        Boolean result = HR_AccessService.canView('open_form_access_test');
        Test.stopTest();
        System.assertEquals(true, result, 'No access rules = public form');
    }

    @IsTest
    static void testAssertCanViewNoRules() {
        createForm('assert_view_test');
        Test.startTest();
        try {
            HR_AccessService.assertCanView('assert_view_test');
            System.assert(true, 'Should not throw for open form');
        } catch (AuraHandledException e) {
            System.assert(false, 'Should not throw');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetAccessibleFormsReturnsPublished() {
        createForm('accessible_form_1');
        createForm('accessible_form_2');
        Test.startTest();
        List<HR_Form__c> forms = HR_AccessService.getAccessibleForms(null);
        Test.stopTest();
        System.assert(forms.size() >= 2, 'Should return at least 2 accessible forms');
    }

    @IsTest
    static void testLogicEngineMatchesCondition() {
        Test.startTest();
        System.assertEquals(true,  HR_LogicEngineService.matchesCondition('equals',        'yes',  'yes'));
        System.assertEquals(false, HR_LogicEngineService.matchesCondition('equals',        'no',   'yes'));
        System.assertEquals(true,  HR_LogicEngineService.matchesCondition('not_equals',    'a',    'b'));
        System.assertEquals(true,  HR_LogicEngineService.matchesCondition('contains',      'hello world', 'world'));
        System.assertEquals(true,  HR_LogicEngineService.matchesCondition('is_empty',      '',     null));
        System.assertEquals(true,  HR_LogicEngineService.matchesCondition('is_not_empty',  'val',  null));
        System.assertEquals(true,  HR_LogicEngineService.matchesCondition('starts_with',   'abc',  'ab'));
        System.assertEquals(true,  HR_LogicEngineService.matchesCondition('greater_than',  '10',   '5'));
        System.assertEquals(true,  HR_LogicEngineService.matchesCondition('in_list',       'B',    'A|B|C'));
        System.assertEquals(false, HR_LogicEngineService.matchesCondition('not_in_list',   'B',    'A|B|C'));
        Test.stopTest();
    }
}