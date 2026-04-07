#!/usr/bin/env bats

setup() {
  # Create a temporary directory for each test
  TEST_DIR="$(mktemp -d)"
  export GITHUB_WORKSPACE="$TEST_DIR"
  export GITHUB_REPOSITORY="test-owner/test-repo"
  export HEAD_SHA="abc123"
  export INPUT_CUSTOM_MESSAGE=""
  export GH_TOKEN="fake-token"

  # Create a mock gh command
  MOCK_BIN="$TEST_DIR/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"

  # Default mock gh: returns empty results (no secrets/variables)
  cat > "$MOCK_BIN/gh" << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" =~ "actions/variables" ]]; then
  echo '{"variables":[],"total_count":0}'
elif [[ "$*" =~ "actions/secrets" ]]; then
  echo '{"secrets":[],"total_count":0}'
else
  echo '{}'
fi
MOCK
  chmod +x "$MOCK_BIN/gh"

  # Script under test
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/check-doppler.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "detects doppler.yaml in repo root" {
  touch "$GITHUB_WORKSPACE/doppler.yaml"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # Should NOT contain warning (silent success)
  [[ ! "$output" =~ "::warning::" ]]
}

@test "detects doppler.yml in repo root" {
  touch "$GITHUB_WORKSPACE/doppler.yml"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "::warning::" ]]
}

@test "detects dopplerhq/ reference in workflow files" {
  mkdir -p "$GITHUB_WORKSPACE/.github/workflows"
  cat > "$GITHUB_WORKSPACE/.github/workflows/ci.yml" << 'EOF'
jobs:
  build:
    steps:
      - uses: dopplerhq/cli-action@v3
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "::warning::" ]]
}

@test "detects doppler run in workflow files" {
  mkdir -p "$GITHUB_WORKSPACE/.github/workflows"
  cat > "$GITHUB_WORKSPACE/.github/workflows/deploy.yaml" << 'EOF'
jobs:
  deploy:
    steps:
      - run: doppler run -- ./start.sh
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "::warning::" ]]
}

@test "ignores dopplerhq/doppler-usage-check as a doppler signal" {
  mkdir -p "$GITHUB_WORKSPACE/.github/workflows"
  cat > "$GITHUB_WORKSPACE/.github/workflows/doppler-check.yml" << 'EOF'
jobs:
  check:
    steps:
      - uses: actions/checkout@v5
      - uses: dopplerhq/doppler-usage-check@v1
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::" ]]
}

@test "ignores workflow files without doppler references" {
  mkdir -p "$GITHUB_WORKSPACE/.github/workflows"
  cat > "$GITHUB_WORKSPACE/.github/workflows/ci.yml" << 'EOF'
jobs:
  build:
    steps:
      - uses: actions/checkout@v5
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::" ]]
}

@test "detects DOPPLER_ variable via API" {
  cat > "$TEST_DIR/mock-bin/gh" << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" =~ "actions/variables" ]]; then
  echo '{"variables":[{"name":"DOPPLER_PROJECT"}],"total_count":1}'
else
  echo '{"secrets":[],"total_count":0}'
fi
MOCK
  chmod +x "$TEST_DIR/mock-bin/gh"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "::warning::" ]]
}

@test "detects DOPPLER_ secret via API" {
  cat > "$TEST_DIR/mock-bin/gh" << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" =~ "actions/secrets" ]]; then
  echo '{"secrets":[{"name":"DOPPLER_TOKEN"}],"total_count":1}'
else
  echo '{"variables":[],"total_count":0}'
fi
MOCK
  chmod +x "$TEST_DIR/mock-bin/gh"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "::warning::" ]]
}

@test "handles 403 on secrets API gracefully" {
  cat > "$TEST_DIR/mock-bin/gh" << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" =~ "actions/secrets" ]]; then
  echo "HTTP 403" >&2
  exit 1
else
  echo '{"variables":[],"total_count":0}'
fi
MOCK
  chmod +x "$TEST_DIR/mock-bin/gh"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # Should emit warning (no signals found, secrets check skipped)
  [[ "$output" =~ "::warning::" ]]
  # Should emit message about permissions
  [[ "$output" =~ "Unable to list repository secrets" ]]
}

@test "handles 403 on variables API gracefully" {
  cat > "$TEST_DIR/mock-bin/gh" << 'MOCK'
#!/usr/bin/env bash
echo "HTTP 403" >&2
exit 1
MOCK
  chmod +x "$TEST_DIR/mock-bin/gh"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::" ]]
}

@test "creates neutral check run when doppler not detected" {
  # Mock gh to capture the check-run API call
  cat > "$TEST_DIR/mock-bin/gh" << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" =~ "check-runs" ]]; then
  # Verify it's a POST with correct fields
  echo "CHECK_RUN_CREATED"
  exit 0
fi
if [[ "$*" =~ "actions/variables" ]]; then
  echo '{"variables":[],"total_count":0}'
elif [[ "$*" =~ "actions/secrets" ]]; then
  echo '{"secrets":[],"total_count":0}'
else
  echo '{}'
fi
MOCK
  chmod +x "$TEST_DIR/mock-bin/gh"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CHECK_RUN_CREATED" ]]
}

@test "uses custom message in warning when provided" {
  export INPUT_CUSTOM_MESSAGE="Use Doppler! See https://internal.example.com"

  cat > "$TEST_DIR/mock-bin/gh" << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" =~ "actions/variables" ]]; then
  echo '{"variables":[],"total_count":0}'
elif [[ "$*" =~ "actions/secrets" ]]; then
  echo '{"secrets":[],"total_count":0}'
else
  echo '{}'
fi
MOCK
  chmod +x "$TEST_DIR/mock-bin/gh"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Use Doppler!" ]]
}

@test "handles check run API failure gracefully" {
  cat > "$TEST_DIR/mock-bin/gh" << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" =~ "check-runs" ]]; then
  echo "HTTP 403: Resource not accessible by integration" >&2
  exit 1
fi
if [[ "$*" =~ "actions/variables" ]]; then
  echo '{"variables":[],"total_count":0}'
elif [[ "$*" =~ "actions/secrets" ]]; then
  echo '{"secrets":[],"total_count":0}'
else
  echo '{}'
fi
MOCK
  chmod +x "$TEST_DIR/mock-bin/gh"

  run bash "$SCRIPT"
  # Should still exit 0 even if check run fails
  [ "$status" -eq 0 ]
  # Warning annotation should still be emitted
  [[ "$output" =~ "::warning::" ]]
}

@test "emits warning when no doppler signals found" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "::warning::" ]]
}
