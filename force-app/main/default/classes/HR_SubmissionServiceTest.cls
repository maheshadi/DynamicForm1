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
}