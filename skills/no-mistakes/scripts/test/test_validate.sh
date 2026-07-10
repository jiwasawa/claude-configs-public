#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
V="$(dirname "$NM_SH")/validate_findings.py"

good='[{"id":"r1","severity":"warning","file":"a.go","line":3,"action":"auto-fix","description":"x"}]'
assert_ok bash -c "echo '$good' | python3 '$V'"
assert_ok bash -c "echo '[]' | python3 '$V'"

assert_fail bash -c "echo '{}' | python3 '$V'"                                # not an array
assert_fail bash -c "echo '[{\"id\":\"r1\",\"severity\":\"info\",\"file\":null,\"line\":null,\"action\":\"no-op\"}]' | python3 '$V'"  # missing description
assert_fail bash -c "echo '[{\"id\":\"r1\",\"severity\":\"bad\",\"file\":null,\"line\":null,\"action\":\"no-op\",\"description\":\"x\"}]' | python3 '$V'"  # bad enum
assert_fail bash -c "echo '[{\"id\":\"r1\",\"severity\":\"info\",\"file\":null,\"line\":true,\"action\":\"no-op\",\"description\":\"x\"}]' | python3 '$V'"  # bool line
assert_fail bash -c "echo '[{\"id\":\"r1\",\"severity\":\"info\",\"file\":null,\"line\":0,\"action\":\"no-op\",\"description\":\"x\"}]' | python3 '$V'"  # line < 1
assert_fail bash -c "echo '[{\"id\":\"r1\",\"severity\":\"info\",\"file\":null,\"line\":null,\"action\":\"no-op\",\"description\":\"x\",\"extra\":1}]' | python3 '$V'"  # extra field
dup='[{"id":"r1","severity":"info","file":null,"line":null,"action":"no-op","description":"x"},{"id":"r1","severity":"info","file":null,"line":null,"action":"no-op","description":"y"}]'
assert_fail bash -c "echo '$dup' | python3 '$V'"                              # duplicate id
assert_fail bash -c "echo '$good blah' | python3 '$V'"                        # trailing prose
