# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-04

### Added
- Headless test framework for Roblox Lua modules (runs in plain Lua 5.1)
- Mocks for `game`, `workspace`, `script`, `Instance`, and common Roblox services
- BDD-style test framework (`describe` / `it` / `expect`)
- CLI runner that loads specs, injects mocks, and reports results
- Colored terminal output for test results
- JUnit XML output for CI integration
- Proper CDATA wrapping for raw failure messages in JUnit output
- README with installation and usage instructions
