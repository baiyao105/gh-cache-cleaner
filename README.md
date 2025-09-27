# GitHub Cache Cleaner Action

An GitHub Actions cache cleaner that supports branch-specific, quantity-limited, and multiple cleaning modes.

## Examples

### Basic Usage

```yaml
- name: Clean Caches
  uses: baiyao105/gh-cache-cleaner@v1
  with:
    token: ${{ github.token }}
    delete_all: true
```

### Branch-Specific Cleanup

```yaml
- name: Clean Feature Branch Caches
  uses: baiyao105/gh-cache-cleaner@v1
  with:
    token: ${{ github.token }}
    branches: "feature/test,develop"
    max_delete_count: 10
```

## Input Parameters

| Parameter           | Description                                                     | Required | Default               |
| ------------------- | --------------------------------------------------------------- | -------- | --------------------- |
| `token`             | GitHub token for accessing cache API                            | ✅        | `${{ github.token }}` |
| `delete_all`        | Whether to delete all caches in the repository                  | ❌        | `false`               |
| `branches`          | Branch names to delete caches from (comma or newline separated) | ❌        | `''`                  |
| `max_delete_count`  | Maximum number of caches to delete (-1 for unlimited)           | ❌        | `-1`                  |
| `exclude_branches`  | Branches to exclude when using delete_all                       | ❌        | `[]`                  |
| `cache_key_pattern` | Cache key matching pattern (supports wildcard *)                | ❌        | `*`                   |

## Output Parameters

| Parameter           | Description                             |
| ------------------- | --------------------------------------- |
| `deleted_count`     | Number of caches actually deleted       |
| `total_size_saved`  | Total cache size freed (in bytes)       |
| `deleted_cache_ids` | List of deleted cache IDs (JSON format) |

## Usage

### 1. Preview Cache List (List Current Caches)

```yaml
- name: Preview Caches
  uses: baiyao105/gh-cache-cleaner@v1
  with:
    token: ${{ github.token }}
    # No specific cleanup strategy - will show current cache list
```

### 2. Delete All Caches

```yaml
- name: Delete All Caches
  uses: baiyao105/gh-cache-cleaner@v1
  with:
    token: ${{ github.token }}
    delete_all: true
```

### 3. Delete Specific Branch Caches

```yaml
- name: Delete Branch Caches
  uses: baiyao105/gh-cache-cleaner@v1
  with:
    token: ${{ github.token }}
    branches: |
      feature/branch1
      feature/branch2
      develop
```

### 4. Delete with Quantity Limit

```yaml
- name: Delete Limited Caches
  uses: baiyao105/gh-cache-cleaner@v1
  with:
    token: ${{ github.token }}
    delete_all: true
    max_delete_count: 5
```

### 5. Delete with Branch Exclusion

```yaml
- name: Delete All Except Main Branches
  uses: baiyao105/gh-cache-cleaner@v1
  with:
    token: ${{ github.token }}
    delete_all: true
    exclude_branches: '["main", "master", "develop"]'
```

### 6. Pattern-Based Cleanup

```yaml
- name: Delete Build Caches
  uses: baiyao105/gh-cache-cleaner@v1
  with:
    token: ${{ github.token }}
    delete_all: true
    cache_key_pattern: "build-*"
```

## Advanced Configuration

### Multi-Branch with Pattern Matching

```yaml
- name: Advanced Cache Cleanup
  uses: baiyao105/gh-cache-cleaner@v1
  with:
    token: ${{ github.token }}
    branches: "feature/test,hotfix/urgent"
    cache_key_pattern: "npm-*"
    max_delete_count: 3
```

### Automated Cleanup on PR Close

```yaml
name: Cleanup PR Caches
on:
  pull_request:
    types: [closed]

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - name: Cleanup PR Caches
        uses: baiyao105/gh-cache-cleaner@v1
        with:
          token: ${{ github.token }}
          branches: ${{ github.head_ref }}
```

### Scheduled Cleanup

```yaml
name: Weekly Cache Cleanup
on:
  schedule:
    - cron: '0 2 * * 0'  # Every Sunday at 2 AM

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - name: Cleanup Old Caches
        uses: baiyao105/gh-cache-cleaner@v1
        with:
          token: ${{ github.token }}
          delete_all: true
          exclude_branches: '["main", "master"]'
```

## Output Usage

```yaml
- name: Clean Caches
  id: cache-cleanup
  uses: baiyao105/gh-cache-cleaner@v1
  with:
    token: ${{ github.token }}
    delete_all: true

- name: Show Cleanup Results
  run: |
    echo "Deleted ${{ steps.cache-cleanup.outputs.deleted_count }} caches"
    echo "Freed ${{ steps.cache-cleanup.outputs.total_size_saved }} bytes"
    echo "Cache IDs: ${{ steps.cache-cleanup.outputs.deleted_cache_ids }}"
```

> [!WARNING]
>
> 1. **Permissions**: Ensure the GitHub token has appropriate permissions to access and delete caches
> 2. **Irreversible**: Cache deletion is permanent and cannot be undone
> 3. **Rate Limits**: Be mindful of GitHub API rate limits when deleting large numbers of caches

## License

This action is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
