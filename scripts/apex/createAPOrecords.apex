// Use .apex files to store anonymous Apex.
// You can execute anonymous Apex in VS Code by selecting the
//     apex text and running the command:
//     SFDX: Execute Anonymous Apex with Currently Selected Text
// You can also execute the entire file by running the command:
//     SFDX: Execute Anonymous Apex with Editor Contents

Id repoid = [select Id, Name from copado__Git_Repository__c where copado__URI__c = 'git@product-int-ssh.cvc.copado.com:copado-labs/sfdx-scanner.git' limit 1].Id;
String packageName = 'copado-sfdx-scanner';
copado__Deployment_Flow__c pipe = new copado__Deployment_Flow__c();
pipe.Name = 'Copado Labs - ' + packageName;
pipe.copado__Platform__c = 'SFDX';
pipe.copado__Git_Repository__c = repoid;
pipe.copado__Active__c = true;
pipe.copado__Main_Branch__c = 'master';
insert pipe;

copado__Artifact__c pckg = new copado__Artifact__c();
pckg.Name = packageName;
pckg.RecordTypeId = '0120N000000Ml2lQAC'; // salesforce package
pckg.copado__Pipeline__c = pipe.Id;
pckg.copado__Package_Namespace__c = 'copado_labs';
if (String.isBlank(pckg.copado__Package_Namespace__c)){
    pckg.copado__No_Namespace__c = true;
}
pckg.copado__Target_Dev_Hub_Org__c = 'a0Rb0000007XdNgEAK'; // FL APO
pckg.copado__DefaultBranch__c = 'master';
pckg.cmcSf__PackagePath__c = 'force-app';
pckg.copado__Source_Api_Version__c = '55.0';
pckg.copado__Artifact_Repository__c = repoid;
insert pckg;
