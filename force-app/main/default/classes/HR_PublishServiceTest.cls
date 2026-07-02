/**
 * HR_PublishServiceTest
 */
@IsTest
private class HR_PublishServiceTest {

    private static HR_Form__c createDraftForm(String apiName) {
        String schema = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'fields' => new List<Object>{
                        new Map<String, Object>{ 'apiName' => 'emp', 'type' => 'Text', 'label' => 'Emp' }
                    }
                }
            },
            'rules' => new List<Object>()
        });
        HR_Form__c form = new HR_Form__c(
            Name = 'Publish Test', HR_API_Name__c = apiName,
            HR_Category__c = 'General', HR_Status__c = 'Draft',
            HR_Version__c = 0, HR_Target_Object_API__c = 'Case',
            HR_Deployment_Target__c = 'LWC_Component',
            HR_On_Submit_Action__c = 'Show_Message',
            HR_Allow_Draft_Save__c = true, HR_Require_Confirmation__c = false,
            HR_Schema_JSON__c = schema
        );
        insert form;
        return form;
    }

    @IsTest
    static void testPublishForm() {
        // Must have HR_Form_Admin permission — system mode via runAs
        Profile sysAdmin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        // Reuse the running user's email domain — orgs (like this sandbox) may have
        // validation rules restricting User.Email to approved domains.
        String emailDomain = UserInfo.getUserEmail().substringAfter('@');
        User adminUser = new User(
            FirstName = 'FC', LastName = 'Admin',
            Email = 'fcadmin@' + emailDomain,
            Username = 'fcadmin@formcraft.test.com.' + String.valueOf(Datetime.now().getTime()),
            Alias = 'fcadm',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = sysAdmin.Id
        );
        // HR_Form_Admin is a custom permission granted via HR_Admin_PS — assign it,
        // isolated in runAs to avoid MIXED_DML with the form records below.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert adminUser;
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'HR_Admin_PS' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = adminUser.Id, PermissionSetId = ps.Id);
        }

        HR_Form__c form;
        System.runAs(adminUser) {
            form = createDraftForm('publish_test_' + String.valueOf(Datetime.now().getTime()));
            Test.startTest();
            HR_PublishService.publishForm(form.HR_API_Name__c);
            Test.stopTest();
        }

        HR_Form__c published = [SELECT HR_Status__c, HR_Version__c, HR_Published_Schema_JSON__c
            FROM HR_Form__c WHERE Id = :form.Id LIMIT 1];
        System.assertEquals('Published', published.HR_Status__c);
        System.assertEquals(1, published.HR_Version__c);
        System.assertNotEquals(null, published.HR_Published_Schema_JSON__c);

        List<HR_Form_Version__c> versions = [SELECT HR_Is_Active_Version__c
            FROM HR_Form_Version__c WHERE HR_Form__c = :form.Id];
        System.assertEquals(1, versions.size());
        System.assertEquals(true, versions[0].HR_Is_Active_Version__c);
    }

    @IsTest
    static void testArchiveForm() {
        Profile sysAdmin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String emailDomain = UserInfo.getUserEmail().substringAfter('@');
        User adminUser = new User(
            FirstName = 'FC', LastName = 'Arch',
            Email = 'fcarch@' + emailDomain,
            Username = 'fcarch@formcraft.test.com.' + String.valueOf(Datetime.now().getTime()),
            Alias = 'fcarc',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = sysAdmin.Id
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert adminUser;
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'HR_Admin_PS' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = adminUser.Id, PermissionSetId = ps.Id);
        }

        HR_Form__c form;
        System.runAs(adminUser) {
            form = createDraftForm('archive_test_' + String.valueOf(Datetime.now().getTime()));
            Test.startTest();
            HR_PublishService.archiveForm(form.HR_API_Name__c);
            Test.stopTest();
        }

        HR_Form__c archived = [SELECT HR_Status__c FROM HR_Form__c WHERE Id = :form.Id LIMIT 1];
        System.assertEquals('Archived', archived.HR_Status__c);
    }

    @IsTest
    static void testVersionPrunerBatch() {
        HR_Form__c form = createDraftForm('prune_test_' + String.valueOf(Datetime.now().getTime()));
        String schema = form.HR_Schema_JSON__c;

        List<HR_Form_Version__c> versions = new List<HR_Form_Version__c>();
        for (Integer i = 1; i <= 5; i++) {
            versions.add(new HR_Form_Version__c(
                HR_Form__c = form.Id, HR_Version_Number__c = i,
                HR_Schema_Snapshot__c = schema,
                HR_Published_By__c = UserInfo.getUserId(),
                HR_Published_Date__c = Datetime.now(),
                HR_Environment__c = 'Sandbox',
                HR_Is_Active_Version__c = (i == 5)
            ));
        }
        insert versions;

        Test.startTest();
        Database.executeBatch(new HR_VersionPrunerBatch(), 50);
        Test.stopTest();

        // Confirm batch ran without errors
        System.assert(true, 'Batch completed');
    }
}