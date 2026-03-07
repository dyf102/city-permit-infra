# Project Mandates

- **AWS Profile:** Always use the `SystemAdministrator-110428898775` AWS profile for any `aws` CLI commands or SDK interactions within the `city-permit-infra` project.
- **Environment Variables:** When running shell commands that interact with AWS, ensure `AWS_PROFILE=SystemAdministrator-110428898775` is set.
- **Submodules:** All submodules must be tracked on their `main` branch. Always run `git submodule update --remote --merge` to ensure the root repository is synchronized with the latest development in sub-apps.
