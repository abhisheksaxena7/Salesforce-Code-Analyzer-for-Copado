@isTest
public class EvaluateSFDXAnalyzerResultTest {

    @isTest
    private static void executeQg() {
        System.runAs([SELECT Id FROM User WHERE Username = 'username@myemail.com'][0]) {
            // Setup
            copado__Result__c jobStepResult = [SELECT Id FROM copado__Result__c WHERE copado__Job_Type__c = 'Run_CodeAnalyzer_QIF' LIMIT 1];

            // Exercise
            new EvaluateSFDXAnalyzerResult().execute(null, jobStepResult, 'Success');

            // Verify
            copado__Result__c testResult = [SELECT Id, copado__Status__c, copado__Progress_Status__c, copado__Error_Message__c FROM copado__Result__c WHERE copado__Job_Type__c = 'sfdx-scanner' AND copado__Test__c = null LIMIT 1];
            System.assertEquals('Success', testResult.copado__Status__c, 'The test result should not be Failed');
            System.assertEquals('Success', testResult.copado__Progress_Status__c, 'The progress status should not be Failed');
        }
    }

    @isTest
    private static void executeQgFailure() {
        System.runAs([SELECT Id FROM User WHERE Username = 'username@myemail.com'][0]) {
            // Setup
            copado__Result__c jobStepResult = [SELECT Id FROM copado__Result__c WHERE copado__Job_Type__c = 'Run_CodeAnalyzer_QIF' LIMIT 1];

            // Exercise
            new EvaluateSFDXAnalyzerResult().execute(null, jobStepResult, 'Failed');

            // Verify
            copado__Result__c testResult = [SELECT Id, copado__Status__c, copado__Progress_Status__c, copado__Error_Message__c FROM copado__Result__c WHERE copado__Job_Type__c = 'sfdx-scanner' AND copado__Test__c = null LIMIT 1];
            System.assertEquals('Failed', testResult.copado__Status__c, 'The test result should be Failed');
            System.assertEquals('Failed', testResult.copado__Progress_Status__c, 'The progress status should be Failed');
        }
    }

    @isTest
    private static void executeException() {
        System.runAs([SELECT Id FROM User WHERE Username = 'username@myemail.com'][0]) {
            //Setup
            String errorMessage = 'Attempt to de-reference a null';

            // Exercise
            Exception ex;
            try {
                new EvaluateSFDXAnalyzerResult().execute(null, null, 'Success');
            } catch (Exception e) {
                ex = e;
            }

            // Verify
            System.assertEquals(true, ex.getMessage().contains(errorMessage), 'The exception message matches.');
        }
    }

    @TestSetup
    private static void makeData() {
        User runAsUser = new User(
            LastName = 'UserLastName',
            Username = 'username@myemail.com',
            Email = 'username@myemail.com',
            Alias = 'MyAlias',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = UserInfo.getProfileId(),
            LanguageLocaleKey = 'en_US'
        );
        insert runAsUser;

        System.runAs(runAsUser) {
            copado.GlobalAPI copadoGlobalAPI = new copado.GlobalAPI();
            copado.GlobalAPI.UserLicense userLicense = new copado.GlobalAPI.UserLicense();
            userLicense.isCCMEnabled = true;
            userLicense.isCopadoEnabled = true;
            userLicense.userId = runAsUser.Id;
            copadoGlobalAPI.upsertCopadoLicense(userLicense);

            PermissionSetAssignment copado = new PermissionSetAssignment();
            copado.PermissionSetId = [SELECT Id, Name FROM PermissionSet WHERE Name = 'Copado_User' LIMIT 1].Id;
            copado.AssigneeId = runAsUser.Id;

            insert copado;


            copado__ExtensionConfiguration__c extensionConfiguration = new copado__ExtensionConfiguration__c(copado__Active__c = true, copado__ExtensionTool__c = 'Manual Tests', copado__ExtensionApplication__c = 'Test');
            insert extensionConfiguration;

            copado__Test__c testItem2 = new copado__Test__c(Name = 'SFDX Codeanalyzer Test - QG Execution', copado__ExtensionConfiguration__c = extensionConfiguration.Id, copado__ReadyToRun__c = true);
            List<copado__Test__c> tests = new List<copado__Test__c>{testItem2};
            insert tests;

            copado__Result__c qGResult = new copado__Result__c(copado__Job_Type__c = 'sfdx-scanner', copado__Status__c = 'Not Started');
            List<copado__Result__c> pmdTestResults = new List<copado__Result__c>{qGResult};
            insert pmdTestResults;


            copado__JobTemplate__c template = new copado__JobTemplate__c(Name = 'Run SFDX Codeanalyzer QIF', copado__Version__c = 1);
            insert template;

            copado__JobExecution__c execution2 = new copado__JobExecution__c(
                copado__Template__c = template.Id,
                copado__DataJson__c = '{"resultId" : "'+ qGResult.Id +'"}'
            );
            List<copado__JobExecution__c> executions = new List<copado__JobExecution__c>{execution2};
            insert executions;

            copado__JobStep__c jobStep2 = new copado__JobStep__c(Name = 'Evaluate SFDX Codeanalyzer Result', copado__JobExecution__c = execution2.Id, copado__Type__c = 'Function');
            List<copado__JobStep__c> jobSteps = new List<copado__JobStep__c>{jobStep2};
            insert jobSteps;

            copado__Result__c jobStepResult2 = new copado__Result__c(copado__Job_Type__c = 'Run_CodeAnalyzer_QIF', copado__JobStep__c = jobStep2.Id, copado__Status__c = 'Success');
            List<copado__Result__c> results = new List<copado__Result__c>{jobStepResult2};
            insert results;
        }
    }
}
