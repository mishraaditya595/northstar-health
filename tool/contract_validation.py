"""Shared JSON Schema validator for the contract tests.

The schemas use ECMA-262 patterns, where `^...$` without the multiline flag
matches the whole string only. Python's `re.search` lets `$` also match before
a trailing newline, so `pattern` is checked with `re.fullmatch` instead. Every
pattern in `contracts/` is anchored, so this equals the ECMA result. Formats
(uuid, date-time) are checked by `FormatChecker`, which needs the
`rfc3339-validator` package for date-time.
"""

import re

from jsonschema import Draft202012Validator, FormatChecker, ValidationError, validators


def _pattern(validator, pattern, instance, schema):
    if validator.is_type(instance, "string") and not re.fullmatch(pattern, instance):
        yield ValidationError(f"{instance!r} does not match {pattern!r}")


ContractValidator = validators.extend(Draft202012Validator, {"pattern": _pattern})


def format_checker():
    checker = FormatChecker()
    if "date-time" not in checker.checkers:
        raise RuntimeError("install rfc3339-validator (tool/requirements-ci.txt)")
    return checker
