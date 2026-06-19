/**
 * HR_SubmissionServiceTest
 */
@IsTest
private class HR_SubmissionServiceTest {

    private static HR_Form__c createPublishedForm() {
        String schema = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'fields' => new List<Object>{
                        new Map<String, Object>{
                            'apiName' => 'subject', 'type' => 'Text', 'label' => 'Subject'
                        }
                    }
                }
            },
            'rules' => new List<Object>()
        });

        HR_Form__c form = new HR_Form__c(
            Name                       = 'Submit Test Form',
            HR_API_Name__c             = 'submit_test_form',
            HR_Category__c             = 'General',
            HR_Status__c               = 'Published',
            HR_Version__c              = 1,
            HR_Target_Object_API__c    = 'Case',
            HR_Deployment_Target__c    = 'LWC_Component',
            HR_On_Submit_Action__c     = 'Show_Message',
            HR_Allow_Draft_Save__c     = true,
            HR_Require_Confirmation__c = false,
            HR_Schema_JSON__c          = schema,
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

        HR_Form_Section__c sec = new HR_Form_Section__c(
            Name        = 'Section 1',
            HR_Form__c  = form.Id,
            HR_Order__c = 1,
            HR_Columns__c = '2'
        );
        insert sec;

        HR_Form_Field__c fld = new HR_Form_Field__c(
            Name              = 'Subject',
            HR_Section__c     = sec.Id,
            HR_Form__c        = form.Id,
            HR_API_Name__c    = 'subject',
            HR_Field_Type__c  = 'Text',
            HR_Order__c       = 1,
            HR_Column_Span__c = 'Half',
            HR_Required__c    = false,
            HR_Read_Only__c   = false,
            HR_Is_Active__c   = true,
            HR_SF_Field_API__c = 'Subject'
        );
        insert fld;

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
}