#!/bin/sh
# In-container verification probe for the dev-env devcontainer.
#
# Run inside the started container via `devcontainer exec`. Its mere presence
# here proves the workspace bind mount resolved: a fresh checkout's copy of
# this file is only visible to the container through that mount. The checks
# below then confirm the container user, the environment the entrypoint sets,
# and that the host-config binds are live from within — not merely that the
# mounts were requested at `up` time.
set -eu

fail=0

# assert_eq compares an observed value against the expected one, recording a
# failure without aborting so every check reports before the probe exits.
assert_eq() {
	desc=$1
	want=$2
	got=$3
	if [ "$got" = "$want" ]; then
		printf 'PASS  %s: %s\n' "$desc" "$got"
	else
		printf 'FAIL  %s: want %s, got %s\n' "$desc" "$want" "$got"
		fail=1
	fi
}

# assert_test evaluates a `test` expression (operator + operands) and records a
# failure if it does not hold.
assert_test() {
	desc=$1
	shift
	if [ "$@" ]; then
		printf 'PASS  %s\n' "$desc"
	else
		printf 'FAIL  %s\n' "$desc"
		fail=1
	fi
}

# assert_mount records a failure unless the path is its own mountpoint. A bind
# is only proven live this way: the target existing could be the underlying
# sandboxed-home copy, but a distinct mountpoint can only be the bind.
assert_mount() {
	desc=$1
	path=$2
	if findmnt "$path" >/dev/null 2>&1; then
		printf 'PASS  %s bind at %s\n' "$desc" "$path"
	else
		printf 'FAIL  %s: %s is not a mountpoint\n' "$desc" "$path"
		fail=1
	fi
}

# note reports a host-dependent value without asserting on it.
note() {
	printf 'note  %s: %s\n' "$1" "$2"
}

# present_absent echoes present when the path exists, absent otherwise.
present_absent() {
	if [ -f "$1" ]; then
		echo present
	else
		echo absent
	fi
}

echo '== identity =='
assert_eq 'container user' "$(whoami)" 'runner'
note 'id' "$(id)"

echo '== environment (entrypoint) =='
note 'pwd' "$(pwd)"
note 'WS' "${WS:-<unset>}"
note 'CURDIR' "${CURDIR:-<unset>}"

echo '== workspace bind =='
# This script runs, so the workspace bind already resolved; confirm the repo's
# own marker files are readable through it.
assert_test 'devcontainer.json readable' -r .devcontainer/devcontainer.json
assert_test 'this probe readable' -r .devcontainer/probe.sh

echo '== host-config binds =='
assert_test '.claude directory present' -d "$HOME/.claude"
assert_test '.claude.json file present' -f "$HOME/.claude.json"

echo '== bind mounts live =='
# Assert each expected target is its own mountpoint (the whole point of rung 4:
# the binds are live from within, not merely requested at `up` time).
assert_mount 'workspace' "${WS:-$PWD}"
assert_mount 'sandboxed home' "$HOME"
assert_mount '.claude' "$HOME/.claude"
assert_mount '.claude.json' "$HOME/.claude.json"
# Full mount table for the record (no type filter: bind mounts inherit the
# underlying fs type, so `findmnt -t bind` would match nothing).
findmnt || note 'findmnt' 'unavailable'

echo '== host alias (informational) =='
# host.docker.internal depends on the runner's bridge; report, do not assert.
note 'host.docker.internal' "$(getent hosts host.docker.internal || echo '<unresolved>')"
note 'ollama profile' "$(present_absent /etc/profile.d/ollama.sh)"

if [ "$fail" -ne 0 ]; then
	echo 'probe: FAILURES reported above'
	exit 1
fi
echo 'probe: all checks passed'
