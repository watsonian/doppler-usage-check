# Doppler Usage Check

A GitHub Action that detects whether [Doppler](https://doppler.com) is being used in a repository. When Doppler is not detected, it surfaces a non-blocking warning on pull requests.

## How It Works

The action checks for Doppler usage through three signals:

1. **Config file** — looks for `doppler.yaml` or `doppler.yml` in the repository root
2. **Workflow references** — searches GitHub Actions workflow files for `dopplerhq/` actions or `doppler run` commands
3. **Secrets & variables** — checks the GitHub API for any `DOPPLER_*` repository secrets or variables

If any signal is found, the action passes silently. If none are found, it creates a **neutral** check run (non-blocking) with a warning message.

## Usage

```yaml
name: Doppler Check
on: [pull_request]

permissions:
  contents: read
  checks: write

jobs:
  doppler-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: dopplerhq/doppler-usage-check@v1
```

### Custom Warning Message

```yaml
      - uses: dopplerhq/doppler-usage-check@v1
        with:
          custom-message: |
            This repo should be using Doppler. See our internal docs:
            https://internal.example.com/docs/doppler-setup
```

### Full Secrets Coverage

The default `GITHUB_TOKEN` can list repository variables but may not have permission to list secret names. For full coverage (e.g., when Doppler syncs secrets to GitHub Actions), provide a token with broader access:

```yaml
      - uses: dopplerhq/doppler-usage-check@v1
        with:
          github-token: ${{ secrets.DOPPLER_CHECK_TOKEN }}
```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `custom-message` | No | See below | Override the warning message |
| `github-token` | No | `${{ github.token }}` | Token for GitHub API calls |

### Default Warning Message

> Doppler not detected in this repository.
>
> This repository does not appear to be using Doppler for secrets management. If your team uses Doppler, please follow the setup guide: https://docs.doppler.com/docs/getting-started

## Outputs

| Output | Description |
|---|---|
| `doppler-detected` | `'true'` if Doppler was detected, `'false'` otherwise |

## Permissions

The action requires these permissions:

```yaml
permissions:
  contents: read   # Required for actions/checkout in private repos
  checks: write    # Required to create the neutral check run
```

**Note:** When you explicitly set any `permissions` key, all unspecified permissions default to `none`. Without `contents: read`, `actions/checkout` will fail on private repositories.

## Known Limitations

- **Fork PRs:** GitHub restricts the `GITHUB_TOKEN` to read-only for fork PRs. The check run won't be created, but the `::warning::` annotation will still appear.
- **Secrets listing:** The default token may not have permission to list secret names. Use the `github-token` input with a PAT or GitHub App token for full secrets coverage.

## License

Apache 2.0
