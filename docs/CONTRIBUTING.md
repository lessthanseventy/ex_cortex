# Contributing to ExCortex

Thank you for your interest in contributing to ExCortex! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Issues

1. Check the [issue tracker](https://github.com/your-org/ex_cortex/issues) to see if the issue has already been reported.
2. If not, create a new issue with a clear description of the problem, steps to reproduce, and any relevant logs or error messages.

### Suggesting Features

1. Open a new issue with the label `enhancement`.
2. Provide a detailed description of the feature, including its purpose and how it would benefit the project.

### Submitting Pull Requests

1. Fork the repository and create a new branch for your changes.
2. Make your changes and ensure that all tests pass.
3. Submit a pull request with a clear description of the changes and why they are needed.

## Development Workflow

### Setting Up the Development Environment

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/ex_cortex.git
   cd ex_cortex
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Set up the database:
   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

4. Start the application:
   ```bash
   mix phx.server
   ```

### Running Tests

To run the test suite:
```bash
mix test
```

To run specific tests:
```bash
mix test test/ex_cortex/your_test_file.exs
```

### Code Style

We use `mix format` to ensure consistent code style. Run the following command to format your code:
```bash
mix format
```

To check if your code is formatted:
```bash
mix format --check-formatted
```

### Static Analysis

We use `credo` for static analysis. Run the following command to check for issues:
```bash
mix credo --all
```

### Accessibility Testing

We use `excessibility` for accessibility testing. Run the following command to generate accessibility reports:
```bash
mix excessibility
```

## Code Review Process

All pull requests must be reviewed by at least one maintainer before being merged. The review process includes:

1. **Code Review**: Ensuring the code is clean, well-documented, and follows best practices.
2. **Testing**: Ensuring all tests pass and new tests are added for new features.
3. **Static Analysis**: Ensuring the code passes all static analysis checks.
4. **Accessibility**: Ensuring the code meets accessibility standards.

## Communication

Join our community on [Discord](https://discord.gg/your-invite-link) or [Slack](https://slack.gg/your-invite-link) to discuss ideas, ask questions, and get help.

## License

By contributing to ExCortex, you agree that your contributions will be licensed under the [MIT License](LICENSE).
