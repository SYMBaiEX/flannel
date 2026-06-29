#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SCHEME="${FLANNEL_SCHEME:-flannel}"
CONFIGURATION="${FLANNEL_CONFIGURATION:-Debug}"
PROJECT="${FLANNEL_PROJECT:-flannel.xcodeproj}"
DESTINATION="${FLANNEL_DESTINATION:-platform=macOS}"
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${FLANNEL_DERIVED_DATA:-$WORKSPACE_ROOT/.build/xcodebuild}"
RESULT_BUNDLE="${DERIVED_DATA}/build.xcresult"
BUILD_LOG="${DERIVED_DATA}/xcodebuild.log"
SOURCE_PACKAGES_DIR="${DERIVED_DATA}/SourcePackages"
APP_BUNDLE="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${SCHEME}.app"
APP_BINARY="${APP_BUNDLE}/Contents/MacOS/${SCHEME}"
PROJECT_PATH="${WORKSPACE_ROOT}/${PROJECT}"

DEFAULT_LOG_PREDICATE="process == \"${SCHEME}\""
DEFAULT_TELEMETRY_PREDICATE="(process == \"${SCHEME}\" || subsystem CONTAINS[c] \"flannel\")"
LOG_PREDICATE="${FLANNEL_LOG_PREDICATE:-$DEFAULT_LOG_PREDICATE}"
TELEMETRY_PREDICATE="${FLANNEL_TELEMETRY_PREDICATE:-$DEFAULT_TELEMETRY_PREDICATE}"

usage() {
  cat <<'USAGE'
Usage: ./script/build_and_run.sh [run|--debug|--logs|--telemetry|--verify]

Modes:
  run         Build then open the app (default)
  --debug     Launch lldb against the built binary
  --logs      Tail app logs (process predicate)
  --telemetry Tail telemetry-oriented logs (telemetry predicate)
  --verify    Build and verify launch within 15 seconds
  -h|--help   Show this help text
USAGE
}

run_build() {
  mkdir -p "${DERIVED_DATA}"
  rm -rf "${RESULT_BUNDLE}" "${BUILD_LOG}"

  # Deterministic local builds: fixed derived data + SPM cache location + single-job compile order.
  /usr/bin/xcrun xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "${DESTINATION}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_DIR}" \
    -resultBundlePath "${RESULT_BUNDLE}" \
    -jobs 1 \
    -parallelizeTargets \
    clean build | tee "${BUILD_LOG}"
}

ensure_app_bundle() {
  if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "Build output not found: ${APP_BUNDLE}" >&2
    echo "Expected app in: ${DERIVED_DATA}/Build/Products/${CONFIGURATION}" >&2
    echo "Check build log: ${BUILD_LOG}" >&2
    exit 1
  fi
}

open_app() {
  /usr/bin/open -n "${APP_BUNDLE}"
}

wait_for_launch() {
  local timeout="${1:-15}"
  local waited=0

  while (( waited < timeout )); do
    if pgrep -x "${SCHEME}" >/dev/null; then
      return 0
    fi
    sleep 1
    ((waited += 1))
  done

  return 1
}

if [[ "${MODE}" == "-h" || "${MODE}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -e "${PROJECT_PATH}" ]]; then
  echo "Missing project: ${PROJECT_PATH}" >&2
  exit 1
fi

# Ensure stale instances are terminated before deterministic build and relaunch.
pkill -x "${SCHEME}" >/dev/null 2>&1 || true
run_build
ensure_app_bundle

case "${MODE}" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "${APP_BINARY}"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "${LOG_PREDICATE}"
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "${TELEMETRY_PREDICATE}"
    ;;
  --verify|verify)
    open_app
    if wait_for_launch 15; then
      echo "${SCHEME} is running"
      exit 0
    fi

    echo "${SCHEME} failed to launch in time" >&2
    exit 1
    ;;
  *)
    usage
    echo "invalid mode: ${MODE}" >&2
    exit 2
    ;;
esac
