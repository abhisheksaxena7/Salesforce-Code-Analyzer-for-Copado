# Code Analyzer for Copado

With Salesforce Code Analyzer for Copado, you can use Code Analyzer as a **quality gate** in your Copado pipeline. The extension runs analysis only on **changed components**, ensuring efficient code quality and security scanning throughout your development process.

## Is this extension for you?
Are you a Copado customer? ✅\
Do you want to use the latest and greatest from Salesforce for quality and security scanning? ✅\
If the answer is yes to both questions, then this extension is for you.

<details>
<summary>What is Salesforce Code Analyzer?</summary>

[Salesforce Code Analyzer](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/guide/code-analyzer.html) is a unified static code analysis tool for checking the quality, security, and performance of Salesforce code. It supports multiple engines: `sfge`, `pmd`, `pmd-appexchange`, `flow scanner`, `cpd`, `eslint`, `retire-js`, and `regex`. The tool includes hundreds of customizable rules and is required for AppExchange security review. You can tailor its behavior and define custom rules using a YAML config file.

</details>
<br/>

**⚠️ DISCLAIMER**

**Code Analyzer for Copado is NOT an officially supported tool**

👷 Use it at your own risk

<details>
<summary>Table of Contents</summary>

- [Getting Started](#getting-started)
  - [Pre-Requisites](#pre-requisites)
  - [Installation](#installation)
  - [Post-Installation](#post-installation)
    - [Picklist Values](#picklist-values)
    - [Create Extension Records](#create-extension-records)
    - [Create the Quality Gate](#create-the-quality-gate)
    - [Configure Pipeline System Property (Optional, but recommended)](#configure-pipeline-system-property-optional-but-recommended)
    - [Customize other configuration (Optional)](#customize-other-configuration-optional)
- [Testing the setup](#testing-the-setup)
- [In-depth setup and walkthrough examples](#in-depth-setup-and-walkthrough-examples)
  - [Trigger Points](#trigger-points)
    - [After Commit](#after-commit)
    - [Before Deployment](#before-deployment)
    - [After Promotion](#after-promotion)
  - [Reviewing the scan results](#reviewing-the-scan-results)
    - [Engine and Rule Grouping](#engine-and-rule-grouping)
    - [Metadata Type and Filename Grouping](#metadata-type-and-filename-grouping)
    - [Severity Filters and Search](#severity-filters-and-search)
    - [Open up the Result record](#open-up-the-result-record)
- [v3.4 Release Notes](#v34-release-notes)
  - [🚀 New Features](#new-features)
    - [Upgrade to Code Analyzer 5.3](#upgrade-to-code-analyzer-53)
    - [Enhanced Results Display](#enhanced-results-display)
  - [Migration Guide](#migration-guide)
    - [Delete DFA related metadata](#delete-dfa-related-metadata)
</details>


# Getting Started

## Pre-Requisites
* Be a Copado CI/CD customer on Copado Source Format Pipelines.
* Minimum Copado Deployer version = 25.0
* Minimum Copado Quality Tools version = 4.0

## Installation
- Install the [latest version of Copado SFDX Analyzer](https://success.copado.com/s/listing-detail?recordId=a545p000000Xx1hAAC) from Copado's DevOps Exchange.

- If you're upgrading from version 2.x to the latest 5.x, follow the [Migration Guide](#migration-guide), and then return to the [Create the Quality Gate](#create-the-quality-gate) section.

## Post-Installation

### Picklist Values
Create the following picklist values:
* Setup --> Object Manager --> Extension Configuration --> Field: Extension Tool --> Value: `sfdx-scanner`
* Setup --> Picklist Value Set --> Copado Test Tool --> Value: `sfdx-scanner`

### Create Extension Records
Navigate to the “Copado Extensions” tab from the App Launcher, select “CopadoSFDXAnalyzer” and press the button “Generate Extension Records”.

![Generate Extension Records](./images/generate-extension-records.png)

### Create the Quality Gate
* Navigate to Pipeline Builder.
* Go to the Quality Gates sub-section from the left-hand side pane.
* Click the `Create Quality Gate` button, and choose `sfdx-scanner` from the list.
* You can choose to create it `After Commit - Block`, `After Promotion - Report`, or `Before Deployment - Block`, depending on the behavior you need.
* You can configure the environment(s) and/or stage(s) the quality gate should apply to.

  ![Configure Quality Gate](./images/quality-gate-setup.gif)

* Here's an example of creating an After Commit quality gate for the `Service DX Dev 1` environment, with **Advanced Filters** so it triggers only when at least one metadata item of type **Apex** (`ApexClass`, `ApexTrigger`, `ApexComponent`, `ApexPage`), **LWC**, **Flow**, or **Messaging Channel** is committed. This ensures it runs only when needed.
  ![Configure Quality Gate](./images/create-quality-gate-rule.png)

### Configure Pipeline System Property (Optional, but recommended)
> **ℹ️ NOTE:**
> The default severity threshold is **2 (High)** unless you overwrite it.
> To overwrite it, follow the steps mentioned below.

![System Property](./images/severity-threshold-system-property.png)

* Go to Pipelines from the App Launcher --> open your pipeline --> Settings sub-tab --> Click New on System Property --> Property Name and API Name: `sfdx_scanner_severityThreshold`.
* Valid severity values are: 1 (Critical), 2 (High), 3 (Moderate), 4 (Low), or 5 (Info).
* If this property is not set, or set incorrectly, then it'll default to severity 2 (High).
* The Quality gate will throw an error when violations are found with equal or greater severity than the provided value.
* Leave other values blank, and hit save.

### Customize other configuration (Optional)
Code Analyzer supports extensive customization, including enabling or disabling engines, adding custom rules, and adjusting rule severities.

To configure these options, add a `code-analyzer.yml` file to the root of your project. See a [sample file here](./code-analyzer.yml). Commit this file to all long-lived environment branches in your repository (e.g., `main`, `qa`, `uat`).

Once this file is present in your environment branches, any new feature or promotion branches created from them will automatically inherit the configuration. The Quality Gate will use these settings without further action.

For more details on available configuration options, see the [customizing configuration documentation](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/guide/config-custom.html).

## Testing the setup
If you've set up the `After Commit` Quality Gate as above, commit changes that include Apex classes, LWCs, Apex components, flows, or messaging channels on a user story tied to the environment/stage where your Quality Gate is configured. The Commit Action will then invoke `Code Analyzer` after every commit.

Here's some [test-data](./test-data/) that can be used to test the Quality Gate, and a sample [configuration file](./code-analyzer.yml).

# In-depth setup and walkthrough examples

## Trigger Points
You can configure Code Analyzer to run at different stages of your deployment pipeline. The supported trigger points are:

### After Commit

<table>
<tr>
<td><a href="./images/failed-commit-sfdx.png" target="_blank"><img src="./images/failed-commit-sfdx.png" alt="Failed Commit" width="400"></a></td>
<td><a href="./images/after-commit-block-promotion.png" target="_blank"><img src="./images/after-commit-block-promotion.png" alt="Block Promotion" width="400"></a></td>
</tr>
</table>

Run Code Analyzer after every commit that happens on your user stories. This allows you to shift left in your quality and security scanning journey, and if the latest commit on a user story fails due to violations, it won't be promoted to the next environment.

### Before Deployment
![Before Deployment Block](./images/before-deployment-block.png)
Run Code Analyzer before deployment as a **quality gate**. This analyzes all User Stories in the deployment together. If violations are found, the deployment is blocked.

### After Promotion
![After Promotion Report](./images/after-promotion-report.png)
Run Code Analyzer after promotion for **reporting purposes only**. This provides visibility into code quality across all User Stories in the deployment without blocking the process.


> **Key Difference:**
> - **After Commit:** Scans only the changes in a single user story and its feature branch since it was created from the base branch.
> - **Before Deployment / After Promotion:** Scans all user stories together in the promotion, showing the overall code quality impact. Under the hood, it runs a comparison of all changes in the promotion branch since it split from the destination branch.

## Reviewing the scan results


### Engine and Rule Grouping
![Engine/Rule Grouping](./images/violations-gpengine-modal.gif)

Results can be grouped in two ways. The first (shown above) is by **Engine/Rule**, which lets you view violations grouped by engine and then by rule. This is helpful when you want to see specific engine or rule errors.

### Metadata Type and Filename Grouping
![Type/FileName Grouping](./images/violations-gptype-modal.gif)

You can also switch to the **Type/Filename** grouping from the dropdown. This is better if you want to focus on specific metadata types or review all errors in a single file.

### Severity Filters and Search
![Filter/Search](./images/violations-filter-search.gif)

You can use the different severity filters and search box to narrow down the results.

### Open up the Result record
![Result Record](./images/violations-result-record.gif)

You can open the Result record to increase screen real estate, making the violations easier to read, and use the different severity filters, search, and groupings.


# v3.4 Release Notes

## 🚀 New Features

### Upgrade to Code Analyzer 5.3
- **New Engines**: Regex and Flow are newly supported engines. [See all supported engines](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/guide/engines.html)
- **SFGE**: Can now run with a single quality gate; there's no need to create another Quality Gate to run Data Flow Analysis.
- **Custom Config File** - v5 introduces a configuration YAML file (code-analyzer.yml) which you can use to configure top-level properties and customize rules and engines, including adding custom rules. [See Customize the v5 Configuration for details.](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/guide/config-custom.html)

### Enhanced Results Display
- **Clean, Modern Interface**: Results are displayed in an organized, easy-to-read format within the Result Modal
- **Smart Organization**: Results are automatically grouped and organized for easy navigation
- **Quick Search**: Find specific violations instantly by typing in the search box - searches across files, rules, messages, engines.
- **Severity Filtering**: Click on colored buttons to filter by severity level (Critical, High, Moderate, Low, Info)
- **Dynamic Counts**: See real-time counts of violations that update as you filter
- **One-Click Reset**: Clear all filters with a single button click
- **Group by Engine**: View results organized by analysis tool (PMD, ESLint, etc.) with rule breakdowns
- **Group by File Type**: View results organized by metadata type (Apex classes, LWC components, etc.) and file name breakdown.
- **Collapsible Sections**: Expand and collapse sections to focus on what matters most
- **Detailed Information**: See file paths, line numbers, violation messages, and rule documentation links.

### Bug Fixes
- Fixed major bugs in diff calculation logic.

## Migration Guide
- If you're upgrading from version 2.x of Code Analyzer for Copado to version 3.x, you'll need to make some changes.

- The new 5.x version relies on new capabilities in the Copado Deployer and Quality Tools packages; hence, minimum requirements have changed. Please upgrade those packages to the required versions as listed in the [Pre-Requisites](#pre-requisites) section.

- After upgrading, navigate to the “Copado Extensions” tab, select “CopadoSFDXAnalyzer” and press the button “Generate Extension Records”.

- After generating the new records, go to "Functions > Run SFDX Code Analyzer QIF > Configuration sub-tab", and if the Callback Type is set to Apex, set it to 'None'.

- You're likely using the legacy Quality Gate Rules. Delete the older Quality Gate Rules and Quality Gate Rule Conditions by going to the Quality Gates tab and searching for the SFDX Scanner Quality Gates you created. There will likely be two—one for DFA and one for other engines. Repeat this step for the other Quality Gate Rule as well.

  ![Legacy QGR](./images/legacy-quality-gate-rule.png)

### Delete DFA related metadata
DFA analysis using the `SFGE` engine is now part of the main quality gate; hence, we need to delete the older references.
- Go to App Launcher --> Functions --> Run SFDX Code Analyzer DFA QIF --> Delete.

- Go to App Launcher --> Job Templates --> Run SFDX Code Analyzer DFA QIF --> Switch to the Steps sub-tab --> Delete all the steps one by one --> Finally, delete the Job Template.

- Go to App Launcher --> Extension Configuration --> SFDX Scanner Config DFA --> Deactivate --> Delete

- Go to Setup --> Picklist Value Sets --> Copado Test Tool --> Delete the `sfdx-scanner-dfa` value --> Replace with blank.

- Go to Setup --> Object Manager --> Extension Configuration --> Field: Extension Tool --> Delete the `sfdx-scanner-dfa` value --> Replace with blank.

- Once all of this is deleted, go back to the [Create the Quality Gate](#create-the-quality-gate) section and continue.


