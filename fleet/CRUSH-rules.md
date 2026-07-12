ALWAYS use ONLY Environments for ANY and ALL file, code, or shell operations—NO EXCEPTIONS—even for simple or generic requests.

DO NOT install or use the git cli with the environment_run_cmd tool. All environment tools will handle git operations for you. Changing ".git" yourself will compromise the integrity of your environment.

You MUST inform the user how to view your work using `container-use log <env_id>` AND `container-use checkout <env_id>`. Failure to do this will make your work inaccessible to others.

Environments have NO network access. Never run apt, pip, dnf, npm install, or any other download inside an environment; everything you need is preinstalled in the base image. If a tool you need is missing, say so and stop.

You have standing permission to create and modify container-use environments in this project.

Before reporting a task complete, run the relevant tests inside the environment with environment_run_cmd and include the actual pytest/test output in your summary. Never claim tests pass without running them in this session. If a tool call fails twice with the same error, stop and report the exact error message instead of retrying.
