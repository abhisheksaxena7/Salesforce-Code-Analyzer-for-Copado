## Project structure

The `copado` directory contains the functions, templates, and extension configuration required to work with CopadoDev CLI. The Docker image is also present in the `images/` directory, along with several utilities and configurations in the `local/` directory.

## Local Development

To begin local development, ensure that the project is structured as a CopadoDev CLI project and that Docker/Docker daemon is installed and running on your local machine.

Also, the Docker image must contain `python3` and the `python-requests` packages.

1. Copy `local/run.env.sample` to `local/run.env` and configure the parameters.
2. Run the following command:

```
local/run.sh functions/Run_CodeAnalyzer_QIF.sh
```

After execution, the logs of the function will be in the `output.txt` file, which can help with troubleshooting.

The `copado/local` directory contains the following:

- `run.sh` script to build the image and execute any function locally.
- `run.env.sample` to copy and set up parameters for a function execution.
- `copado`, `copado-git-get`

**run.sh and run.env.sample contains useful comments to adapt them to particular projects, so read them carefully**

# Advanced Local Development

While using `run.env` is simple, it's limited in comparison to a script that can prepare files, Git repositories, and parameters and even print or assert the results.

An alternative/complement is to call a script that will call the function:

    local/run.sh local/test_execution.sh

Please read the example `test_execution.sh` carefully to understand the details and added benefits. This allows creating lightweight "Function Tests" that combine mocking of commands, local repositories, and checking the operation results.

The `copado/local` directory can also contain mocked command, if desired. e.g. for tests the vlocity commands, you could create an executalbe file `vlocity` in copado/local , set the `COPADO_LOCAL_FIRST_IN_PATH=1` environmental variable in `test_execution.sh` , and then

## ApexGuru parameters

The job template supplies `apexGuruSessionId` and `apexGuruEndpoint` from
`{$Source.Credential.SessionId}` and `{$Source.Credential.Endpoint}`, the same
source context an Apex Test quality gate uses. On After Promotion and Before
Deployment that is the promotion's source environment, not the destination.
For local testing, add these values to `local/run.env`; leave them empty to
exercise the non-blocking skip path. The session ID is sensitive and must never
be committed.

## Local engines and configuration

The function discovers enabled local engines from the installed Code Analyzer
plugin at runtime (minus `apexguru`), so adding or removing engines in a new
image does not require a script change. Place `code-analyzer.yml` or
`code-analyzer.yaml` at the repository root to disable engines, override rules,
or customize engine settings. ApexGuru is still run separately when credentials
and Apex files are present.

ApexGuru scans changed `.cls` and `.trigger` files only.

Run `local/run.sh local/test_execution.sh` to exercise skipped, merged,
trigger-only, and config-disabled paths with mocked CLI responses.
