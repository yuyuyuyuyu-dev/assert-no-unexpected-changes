#!/usr/bin/env bash

set -euo pipefail

work="$(mktemp -d)"
container=""
untouched=""
image=""

# shellcheck disable=SC2329 # the trap below invokes it
cleanup() {
	for leftover in "${container}" "${untouched}"; do
		if [ -n "${leftover}" ]; then
			docker rm --force "${leftover}" >/dev/null || true
		fi
	done
	if [ -n "${image}" ]; then
		docker rmi --force "${image}" >/dev/null || true
	fi
	rm -rf "${work}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The runner does not enforce `required` on an action's inputs, so an empty act
# input would otherwise take the diff of a container that did nothing and report
# that as success.
if [ -z "$(printf '%s' "${INPUT_ACT}" | tr -d '[:space:]')" ]; then
	echo "::error::the act input is empty, so there is nothing to verify"
	exit 1
fi

# Nothing builds base-image.Dockerfile. It is where the default image is pinned,
# because Dependabot reads image references out of Dockerfiles and not out of
# workflow inputs.
base="${INPUT_IMAGE}"
if [ -z "$(printf '%s' "${base}" | tr -d '[:space:]')" ]; then
	base="$(awk '/^FROM[[:space:]]/ { sub(/^FROM[[:space:]]+/, ""); print; exit }' "${ACTION_PATH}/base-image.Dockerfile")"
fi

# The checkout is carried in as a layer rather than mounted, because a bind mount
# is invisible to `docker diff`: a command that writes into its own project
# directory -- installing dependencies there, building into it -- could not do so
# at all against a read-only mount, and would do so unmeasured against a writable
# one. In a layer it simply works.
#
# The arrange commands run while the image is built, and land in it, which is what
# makes them arrange: preparing an environment is not what this check is
# measuring.
#
# The layer costs a build over the whole context on every step, so a repository
# carrying large directories a build does not need is worth giving a
# .dockerignore.
#
# What the build printed is held back until it fails, so that a passing run leaves
# nothing behind for anyone to read.
status=0
# shellcheck disable=SC2016 # $ARRANGE is for the shell in the container, not this one
printf 'FROM %s\nARG ARRANGE\nWORKDIR %s\nCOPY . %s\nRUN bash -e -c "$ARRANGE"\n' \
	"${base}" "${INPUT_WORKDIR}" "${INPUT_WORKDIR}" |
	ARRANGE="${INPUT_ARRANGE}" docker build \
		--build-arg ARRANGE \
		--iidfile "${work}/iid" \
		--file - \
		"${GITHUB_WORKSPACE}" \
		>"${work}/build" 2>&1 || status=$?
if [ "${status}" -ne 0 ]; then
	cat "${work}/build"
	echo "::error::the image could not be built"
	exit "${status}"
fi
image="$(cat "${work}/iid")"

# Some runtime and storage driver combinations leave marks of their own in the
# writable layer. Taking the diff of a container that ran nothing keeps whatever
# those are out of the allowlist.
docker run --cidfile "${work}/untouched-cid" "${image}" bash -e -c ':' </dev/null >/dev/null 2>&1
untouched="$(cat "${work}/untouched-cid")"

# Closing stdin turns a command that waits for input into a failure rather than a
# job that hangs until the runner times out. `sh -e` stops at the first failure in
# a command written as several, which would otherwise be reported by whatever ran
# last.
status=0
docker run \
	--cidfile "${work}/cid" \
	"${image}" \
	bash -e -c "${INPUT_ACT}" \
	</dev/null >"${work}/act" 2>&1 || status=$?

# `docker diff` reads the container's writable layer, which is discarded together
# with the container, so the container has to outlive the command it ran.
if [ -f "${work}/cid" ]; then
	container="$(cat "${work}/cid")"
fi

if [ "${status}" -ne 0 ]; then
	cat "${work}/act"
	echo "::error::the command exited with status ${status}"
	exit "${status}"
fi

# The working directory is allowed without being asked for. It holds a checkout of
# a repository with a remote, so a command that damages its own sources is already
# answered -- by `git status`, which unlike `docker diff` can tell a tracked file
# from a build artifact. What has no other witness is what the command did to the
# machine around it, and that is what this check is for. Making every caller
# enumerate its build outputs instead would buy nothing and go stale with every
# dependency it adds.
printf '%s\n' "${INPUT_WORKDIR%/}" >"${work}/allowed"
printf '%s\n' "${INPUT_WORKDIR%/}/*" >>"${work}/allowed"

printf '%s\n' "${INPUT_ALLOWLIST}" >"${work}/input"
while IFS= read -r entry; do
	entry="$(printf '%s' "${entry}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
	case "${entry}" in
	"" | \#*) continue ;;
	esac

	case "${entry}" in
	/*) ;;
	*)
		echo "::error::allowlist entry '${entry}' is not an absolute path"
		exit 1
		;;
	esac

	printf '%s\n' "${entry}" >>"${work}/allowed"
done <"${work}/input"

docker diff "${untouched}" | LC_ALL=C sort >"${work}/untouched"
docker diff "${container}" | LC_ALL=C sort >"${work}/observed"
LC_ALL=C comm -13 "${work}/untouched" "${work}/observed" >"${work}/changes"

covered_by_the_allowlist() {
	change_path="$1"

	while IFS= read -r allowed_path; do
		# The pattern is deliberately unquoted: an allowlist entry is a glob.
		# shellcheck disable=SC2254
		case "${change_path}" in
		${allowed_path}) return 0 ;;
		esac
	done <"${work}/allowed"

	return 1
}

# A directory is reported as changed merely because something inside it was
# created or deleted, and as created when it had to exist before something inside
# it could. Such an entry follows from the change below it rather than being a
# change of its own, so the allowlist only has to name the latter, which is
# reported on a line of its own and checked there.
#
# One thing does hide here. `docker diff` reports a chmod on a directory the same
# way it reports a directory holding a changed file, so a permission change on a
# directory that also holds an allowed change cannot be told apart from it. A
# directory with nothing below it stays visible.
follows_from_a_change_below() {
	directory="$1"

	while IFS= read -r below; do
		below="${below#* }"
		case "${below}" in
		"${directory}") continue ;;
		"${directory%/}"/*) return 0 ;;
		esac
	done <"${work}/changes"

	return 1
}

: >"${work}/violations"
while IFS= read -r change; do
	kind="${change%% *}"
	path="${change#* }"

	if covered_by_the_allowlist "${path}"; then
		continue
	fi

	if [ "${kind}" != D ] && follows_from_a_change_below "${path}"; then
		continue
	fi

	printf '%s\n' "${change}" >>"${work}/violations"
done <"${work}/changes"

violations="$(grep -c '' "${work}/violations" || true)"
if [ "${violations}" -eq 0 ]; then
	echo "nothing outside the allowlist was created, changed or deleted"
	exit 0
fi

# A step is only allowed so many annotations before the rest are dropped, so the
# count goes in the annotation and the paths go where nothing truncates them.
listed=200
head -n "${listed}" "${work}/violations" >"${work}/report"
if [ "${violations}" -gt "${listed}" ]; then
	echo "... and $((violations - listed)) more" >>"${work}/report"
fi

echo "::error::${violations} change(s) outside the allowlist"
cat "${work}/report"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo '### Changes outside the allowlist'
		echo
		# shellcheck disable=SC2016 # the backticks are Markdown, not a substitution
		echo '`A` created, `C` changed, `D` deleted.'
		echo
		echo '```'
		cat "${work}/report"
		echo '```'
	} >>"${GITHUB_STEP_SUMMARY}"
fi

exit 1
