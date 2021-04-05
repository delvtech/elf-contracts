# Contributing

We encourage community submissions to improve the quality of this codebase.

## Getting Started

* Fork this repository
* Clone your fork
* Follow the installation & build steps in the README
* Open a Pull Request (PR) with the [WIP] flag against the development branch and describe the change you are intending to undertake in the PR description. 

After confirming the following requirements, please remove the [WIP] tag and submit the PR for review:
* It passes our linter checks (npm run lint)
* It is properly formatted with Prettier (npm run prettier)
* It passes our continuous integration tests
* Your changes have sufficient test coverage (e.g regression tests have been added for bug fixes)

## Branch Structure

Please confirm that any proposed PRs target the 'development' branch, not the 'main' branch. Your branch must be prefixed by a description of its function eg. 'fix', 'feature', or 'refactor'.

## Review Process

* PRs which make code changes to security-critical code must be reviewed by at least two core contributors. 
* Proposed changes with a lower security profile or related to actively developed code may in some cases be merged with one review as it will undergo a bulk security review. 
* All changes made to the development branch should be reviewed for security in accordance with our security review guidelines as well as industry best practices before merging into the main branch or to deployment.
* Persons qualified to merge and review PRs are likely busy and thus for some PRs it may take several weeks for review, we ask you to remain patient and respectful throughout that process. 

## Code of Conduct

We maintain a polite and respectful development community and one which is welcoming of people from all backgrounds. As such, we invite all those who participate in our community to help us foster a safe and positive experience for everyone. We expect our community members to treat their peers with respect. Harassment of any kind, including racism, hate speech, harmful language, etc. will NOT be tolerated. If your behavior is not in line with those community expectations you will be removed from community discussions and lose any review abilities or other community standings which have been entrusted to you.
