#!/usr/bin/env bash

set -euo pipefail

work="$(mktemp -d)"
container=""
untouched=""
image=""

# shellcheck disable=SC2329
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

if [ -z "$(printf '%s' "${INPUT_ACT}" | tr -d '[:space:]')" ]; then
	echo "::error::the act input is empty, so there is nothing to verify"
	exit 1
fi

base="${INPUT_IMAGE}"
if [ -z "$(printf '%s' "${base}" | tr -d '[:space:]')" ]; then
	base="$(awk '/^FROM[[:space:]]/ { sub(/^FROM[[:space:]]+/, ""); print; exit }' "${ACTION_PATH}/default-image.Dockerfile")"
fi

status=0
# shellcheck disable=SC2016
printf 'FROM %s\nARG ARRANGE\nWORKDIR %s\nCOPY . %s\nRUN sh -e -c "$ARRANGE"\n' \
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

docker run --cidfile "${work}/untouched-cid" "${image}" sh -e -c ':' </dev/null >/dev/null 2>&1
untouched="$(cat "${work}/untouched-cid")"

status=0
docker run \
	--cidfile "${work}/cid" \
	"${image}" \
	sh -e -c "${INPUT_ACT}" \
	</dev/null >"${work}/act" 2>&1 || status=$?

if [ -f "${work}/cid" ]; then
	container="$(cat "${work}/cid")"
fi

if [ "${status}" -ne 0 ]; then
	cat "${work}/act"
	echo "::error::the command exited with status ${status}"
	exit "${status}"
fi

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
		# shellcheck disable=SC2254
		case "${change_path}" in
		${allowed_path}) return 0 ;;
		esac
	done <"${work}/allowed"

	return 1
}

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
		# shellcheck disable=SC2016
		echo '`A` created, `C` changed, `D` deleted.'
		echo
		echo '```'
		cat "${work}/report"
		echo '```'
	} >>"${GITHUB_STEP_SUMMARY}"
fi

exit 1
