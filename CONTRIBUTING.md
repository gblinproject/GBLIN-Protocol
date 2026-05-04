# Contributing to GBLIN Protocol

Thank you for considering contributing to GBLIN. This document outlines the process for contributing to the protocol.

## Code of Conduct

This project adheres to the [Contributor Covenant](./CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How to Contribute

### Reporting Bugs

For non-security bugs, [open an issue](https://github.com/gblinproject/GBLIN-Protocol/issues/new) using the bug report template.

For security vulnerabilities, see [SECURITY.md](./SECURITY.md).

### Suggesting Features

Open an issue using the feature request template. Include:
- The motivation (what problem does it solve?).
- The proposed solution.
- Alternatives you've considered.

### Pull Requests

1. **Fork** the repository.
2. **Branch**: create a feature branch from `main` (`git checkout -b feature/your-feature`).
3. **Commit**: use clear, atomic commits. Sign commits with GPG when possible.
4. **Test**: ensure all existing tests pass and add new ones if applicable.
5. **Document**: update relevant docs in `docs/` and `README.md`.
6. **Open PR**: target the `main` branch and fill in the PR template.

### Commit Message Format

```
type(scope): short description

Longer explanation if necessary.

Closes #123
```

Where `type` is one of: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`.

## Development Setup

Requirements:
- Node.js ≥ 18
- Foundry or Hardhat
- Solidity ^0.8.20

```bash
git clone https://github.com/gblinproject/GBLIN-Protocol
cd GBLIN-Protocol
forge install     # or npm install
forge test        # or npm test
```

## Style Guide

- **Solidity**: follow the [official style guide](https://docs.soliditylang.org/en/latest/style-guide.html).
- **Comments**: use NatSpec for all public/external functions.
- **Tests**: name files `*.t.sol` (Foundry) or `*.test.ts` (Hardhat).

## Licensing

By contributing, you agree that your contributions will be licensed under the MIT License.

## Questions?

- Email: `info@gblin.digital`
- Farcaster: [@gblin](https://warpcast.com/gblin)
- X: [@GBLIN_Protocol](https://x.com/GBLIN_Protocol)
