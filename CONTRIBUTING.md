# Contributing

We encourage community submissions to improve the quality of this codebase.

## Getting started

* Fork this repo
* Clone your fork
* Follow the installation & build steps 
* Open a PR with the [WIP] flag against the development branch and describe the change you are intending to undertake in the PR description. 

Remove the [WIP] tag and submit the PR for review, after making sure:

* It passes our linter checks (npm run lint)
* It is properly formatted with Prettier (npm run prettier)
* It passes our continuous integration tests 
* Your changes have sufficient test coverage (e.g regression tests have been added for bug fixes)

## Branch Structure

Please make sure that any pull requests target the 'development' branch not the 'main' branch. Your branch must be prefixed by a description of its function eg. 'fix', 'feature' or 'refactor'.

## Review Process

PRs which make code changes to security critical code must be reviewed by two core contributors. Changes with a lower security profile or in actively developed code which will undergo a bulk security review may in some cases be merged with one review. All changes made to the development branch should be reviewed for security in accordance with our security review guidelines and industry best practices before merging into main or deployment.

Persons qualified to review PRs and merge are likely to be busy and thus for some PRs it may take several weeks for review, we ask you to remain patient and respectful throughout that process.

## Code of Conduct

We maintain a polite and respectful development environment and one which is welcoming of people from all backgrounds. If your behavior is not in line with those community expectations you will be removed from community discussions and lose any review abilities or other community standings which have been entrusted to you.
