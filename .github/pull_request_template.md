## Summary

<!-- One or two sentences describing what this PR does and why. -->

## Type of change

<!-- Check all that apply -->

- [ ] New utility installer
- [ ] New install profile
- [ ] Bug fix (existing installer or TUI logic)
- [ ] Enhancement to an existing installer
- [ ] Tests
- [ ] Documentation / shell completions
- [ ] Other: <!-- describe -->

## Checklist

- [ ] `bash tests/test_linux_util.sh` passes with **0 failures**
- [ ] ShellCheck reports no errors (`shellcheck -x linux_util.sh lib/**/*.sh lib/installers/*.sh`)
- [ ] New/changed installer handles all four distro families (`debian`, `fedora|rhel`, `arch`, `suse`) or has a `*)` fallback with a helpful message
- [ ] Downloads are verified with `verify_download` / `_verify_not_empty_or_html` before installing
- [ ] New utility name is added to `completions/linux_util.bash` and `completions/_linux_util` (if applicable)
- [ ] `register_utility` / `register_system_task` line added to `lib/installers.sh` in alphabetical order (if applicable)
- [ ] CONTRIBUTING.md guidelines followed (indentation, quoting, `[[ ]]`, `$()`, `info`/`warn`/`error` for output)

## Testing done

<!-- Describe how you tested the change. -->
<!-- e.g. "Tested install/uninstall on Ubuntu 24.04 and Arch 2026-03" -->
<!-- For CI-only changes or docs, note that the test suite was sufficient. -->

## Related issues

<!-- Closes # -->
