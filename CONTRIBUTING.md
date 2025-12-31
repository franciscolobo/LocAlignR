# Contributing to LocAlign

Thank you for your interest in contributing to LocAlign.

LocAlign is a GitHub-hosted Shiny application distributed primarily via conda. Contributions that improve robustness, usability, documentation, or functionality are welcome.

---

## Ways to contribute

You can contribute by:

- Reporting bugs

- Requesting or discussing new features

- Improving documentation

- Submitting code changes

If you are unsure whether a contribution fits the project, please open an issue first to discuss it.

---

### Reporting issues

Please use GitHub issues to report problems or ask questions.

When reporting bugs, include:

- Your operating system

- How LocAlign was installed (conda environment name, if applicable)

- Output from the Diagnostics tab (tool paths and versions)

- Steps to reproduce the issue, if possible

- Clear, reproducible reports are the most helpful.

---

### Code contributions

If you would like to submit code changes:

- Fork the repository and create a branch from main

- Make focused, well-documented changes

- Ensure the application runs locally

- Commit with clear, descriptive messages

- Open a pull request explaining the motivation and scope

- Pull requests may be revised or declined if they do not align with the project’s goals.

---

### Development guidelines

Treat LocAlign as an application, not a general-purpose R package

- Keep Shiny UI logic inside inst/app/

- Place reusable or non-UI logic in R/

- Do not commit large datasets, databases, or generated outputs

- Do not vendor external tools (BLAST, DIAMOND); these are provided via conda

- Update documentation when behavior, interfaces, or installation steps change

---

### Dependencies and installation

LocAlign is intended to be installed via conda.
Pull requests that require new dependencies should explain:

- Why the dependency is needed

- Whether it is available on conda-forge or bioconda

- Any cross-platform implications

---

## License

By contributing to LocAlign, you agree that your contributions will be licensed under the project’s license (MIT).

---

## Contact and discussion

If you are uncertain about how to proceed, opening an issue for discussion is always appropriate.


