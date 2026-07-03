/**
 * HR_SubmissionServiceTest
 */
@IsTest
private class HR_SubmissionServiceTest {

    private static HR_Form__c createPublishedForm() {
        // sfFieldApi included so mapToSObject can map payload → Case.Subject
        String schema = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'id'     => 's_1',
                    'title'  => 'Section 1',
                    'columns'=> 2,
                    'fields' => new List<Object>{
                        new Map<String, Object>{
                            'id'         => 'f_1',
                            'apiName'    => 'subject',
                            'type'       => 'Text',
                            'label'      => 'Subject',
                            'sfFieldApi' => 'Subject',
                            'required'   => false
                        }
                    }
                }
            },
            'rules' => new List<Object>()
        });

        HR_Form__c form = new HR_Form__c(
            Name                        = 'Submit Test Form',
            HR_API_Name__c              = 'submit_test_form',
            HR_Category__c              = 'General',
            HR_Status__c                = 'Published',
            HR_Version__c               = 1,
            HR_Target_Object_API__c     = 'Case',
            HR_Deployment_Target__c     = 'LWC_Component',
            HR_On_Submit_Action__c      = 'Show_Message',
            HR_Allow_Draft_Save__c      = true,
            HR_Require_Confirmation__c  = false,
            HR_Schema_JSON__c           = schema,
            HR_Published_Schema_JSON__c = schema
        );
        insert form;

        HR_Form_Version__c ver = new HR_Form_Version__c(
            HR_Form__c              = form.Id,
            HR_Version_Number__c    = 1,
            HR_Schema_Snapshot__c   = schema,
            HR_Published_By__c      = UserInfo.getUserId(),
            HR_Published_Date__c    = Datetime.now(),
            HR_Environment__c       = 'Sandbox',
            HR_Is_Active_Version__c = true
        );
        insert ver;

        return form;
    }

    @IsTest
    static void testSaveDraft() {
        createPublishedForm();
        String payload = JSON.serialize(new Map<String, Object>{ 'subject' => 'Draft Test' });

        Test.startTest();
        String draftId = HR_SubmissionService.saveDraft('submit_test_form', payload);
        Test.stopTest();

        HR_Form_Submission__c sub = [SELECT HR_Status__c FROM HR_Form_Submission__c WHERE Id = :draftId LIMIT 1];
        System.assertEquals('Draft', sub.HR_Status__c);
    }

    @IsTest
    static void testGetMyDrafts() {
        createPublishedForm();
        String payload = JSON.serialize(new Map<String, Object>{ 'subject' => 'My Draft' });
        HR_SubmissionService.saveDraft('submit_test_form', payload);

        Test.startTest();
        List<HR_Form_Submission__c> drafts = HR_SubmissionService.getMyDrafts('submit_test_form');
        Test.stopTest();

        System.assert(drafts.size() >= 1, 'Should find at least 1 draft');
    }

    @IsTest
    static void testGetDraftById() {
        createPublishedForm();
        String payload = JSON.serialize(new Map<String, Object>{ 'subject' => 'Get by ID' });
        String draftId = HR_SubmissionService.saveDraft('submit_test_form', payload);

        Test.startTest();
        HR_Form_Submission__c draft = HR_SubmissionService.getDraftById(draftId);
        Test.stopTest();

        System.assertEquals(draftId, draft.Id);
    }

    // ─── Mapping: type coercion ────────────────────────────────────────────────

    @IsTest
    static void testCoerceValues() {
        Test.startTest();
        Object d = HR_SubmissionService.coerceValue(
            Schema.SObjectType.Contact.fields.Birthdate.getSObjectField().getDescribe(),
            '1990-01-15', 'birth_date');
        System.assertEquals(Date.newInstance(1990, 1, 15), d, 'Date string should coerce');

        Object b = HR_SubmissionService.coerceValue(
            Schema.SObjectType.Contact.fields.DoNotCall.getSObjectField().getDescribe(),
            'true', 'do_not_call');
        System.assertEquals(true, b, 'Boolean string should coerce');

        Object n = HR_SubmissionService.coerceValue(
            Schema.SObjectType.Opportunity.fields.Amount.getSObjectField().getDescribe(),
            '42.5', 'amount');
        System.assertEquals(42.5, n, 'Numeric string should coerce to Decimal');

        Object joined = HR_SubmissionService.coerceValue(
            Schema.SObjectType.Case.fields.Description.getSObjectField().getDescribe(),
            new List<Object>{ 'a', 'b' }, 'multi');
        System.assertEquals('a;b', joined, 'List should join with semicolons');

        try {
            HR_SubmissionService.coerceValue(
                Schema.SObjectType.Contact.fields.Birthdate.getSObjectField().getDescribe(),
                'not-a-date', 'birth_date');
            System.assert(false, 'Bad date should throw');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected coercion error');
        }
        Test.stopTest();
    }

    // ─── Mapping: primary + related records (no DML on target objects) ────────

    @IsTest
    static void testBuildRecordsPrimaryAndRelated() {
        String schema = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'id' => 's_1', 'title' => 'S1',
                    'fields' => new List<Object>{
                        new Map<String, Object>{ 'apiName' => 'last_name',    'type' => 'Text',
                                                 'label' => 'Last Name',      'sfFieldApi' => 'LastName' },
                        new Map<String, Object>{ 'apiName' => 'birth_date',   'type' => 'Date',
                                                 'label' => 'Birth Date',     'sfFieldApi' => 'Birthdate' },
                        new Map<String, Object>{ 'apiName' => 'case_subject', 'type' => 'Text',
                                                 'label' => 'Case Subject',   'sfFieldApi' => 'Case.Subject' }
                    }
                }
            },
            'rules' => new List<Object>()
        });

        HR_Form__c form = new HR_Form__c(
            Name = 'Related Map Test', HR_API_Name__c = 'related_map_test',
            HR_Category__c = 'General', HR_Status__c = 'Published',
            HR_Version__c = 1, HR_Target_Object_API__c = 'Contact',
            HR_Deployment_Target__c = 'LWC_Component',
            HR_On_Submit_Action__c = 'Show_Message',
            HR_Allow_Draft_Save__c = true, HR_Require_Confirmation__c = false,
            HR_Schema_JSON__c = schema, HR_Published_Schema_JSON__c = schema
        );
        insert form;
        insert new HR_Form_Version__c(
            HR_Form__c = form.Id, HR_Version_Number__c = 1,
            HR_Schema_Snapshot__c = schema,
            HR_Published_By__c = UserInfo.getUserId(),
            HR_Published_Date__c = Datetime.now(),
            HR_Environment__c = 'Sandbox', HR_Is_Active_Version__c = true
        );

        Map<String, Object> payload = new Map<String, Object>{
            'last_name'    => 'Smith',
            'birth_date'   => '1990-01-15',
            'case_subject' => 'Related case created by form'
        };

        Test.startTest();
        HR_SubmissionService.MappedRecords recs =
            HR_SubmissionService.buildRecords(form, payload);
        Test.stopTest();

        System.assertEquals('Contact', String.valueOf(recs.primary.getSObjectType()), 'Primary should be Contact');
        System.assertEquals('Smith', recs.primary.get('LastName'));
        System.assertEquals(Date.newInstance(1990, 1, 15), recs.primary.get('Birthdate'), 'Date should be coerced');

        System.assertEquals(1, recs.related.size(), 'One related record expected');
        System.assertEquals('Case', String.valueOf(recs.related[0].getSObjectType()));
        System.assertEquals('Related case created by form', recs.related[0].get('Subject'));
        System.assertEquals('ContactId', recs.relatedParentFields[0],
            'Case should link back to the Contact via ContactId');
    }

    @IsTest
    static void testFindParentFieldNoLookupThrows() {
        Test.startTest();
        try {
            HR_SubmissionService.findParentField(
                Schema.SObjectType.Contact, 'HR_Form_Version__c');
            System.assert(false, 'Should throw when no lookup exists');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected: no lookup to parent');
        }
        Test.stopTest();
    }
}