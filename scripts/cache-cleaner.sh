#!/bin/bash
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

DELETED_COUNT=0
TOTAL_SIZE_SAVED=0
DELETED_CACHE_IDS=()

check_dependencies() {
	if ! command -v gh &>/dev/null; then
		log_error "GitHub CLI (gh) is not installed or not in PATH"
		exit 1
	fi

	if ! command -v jq &>/dev/null; then
		log_error "jq is not installed or not in PATH"
		exit 1
	fi
}

get_cache_list() {
	local filter_condition="$1"
	local cache_data
	if ! cache_data=$(gh cache list --json id,ref,key,sizeInBytes --repo "$GITHUB_REPOSITORY" 2>&1); then
		log_error "Failed to retrieve cache list from GitHub: $cache_data"
		return 1
	fi
	if [[ -z "$cache_data" ]]; then
		log_warning "No cache data returned from GitHub"
		return 0
	fi
	if ! echo "$cache_data" | jq -r "$filter_condition" 2>/dev/null; then
		log_error "Failed to parse cache JSON data with filter: $filter_condition"
		log_error "Raw cache data: $cache_data"
		return 1
	fi
}

delete_cache() {
	local cache_id="$1"
	local cache_key="$2"
	local cache_size="$3"
	log_info "🗑️ Deleting cache: ID=$cache_id, Key=$cache_key"
	if gh cache delete "$cache_id" --repo "$GITHUB_REPOSITORY" 2>/dev/null; then
		log_success "✅ Successfully deleted cache: $cache_id"
		DELETED_COUNT=$((DELETED_COUNT + 1))
		TOTAL_SIZE_SAVED=$((TOTAL_SIZE_SAVED + cache_size))
		DELETED_CACHE_IDS+=("$cache_id")
		return 0
	else
		log_error "❌ Failed to delete cache: $cache_id"
		return 1
	fi
}

parse_branches() {
	local branches_input="$1"
	if [[ -z "$branches_input" ]]; then
		echo ""
		return
	fi
	echo "$branches_input" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
}

parse_exclude_branches() {
	local exclude_input="$1"
	if [[ -z "$exclude_input" || "$exclude_input" == "[]" ]]; then
		echo ""
		return
	fi
	exclude_input=$(echo "$exclude_input" | sed 's/^\[//;s/\]$//')
	echo "$exclude_input" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//' | grep -v '^$'
}

delete_all_caches() {
	log_info "Delete all caches..."
	local exclude_condition=""
	if [[ -n "$INPUT_EXCLUDE_BRANCHES" && "$INPUT_EXCLUDE_BRANCHES" != "[]" ]]; then
		local exclude_branches
		exclude_branches=$(parse_exclude_branches "$INPUT_EXCLUDE_BRANCHES")
		if [[ -n "$exclude_branches" ]]; then
			local exclude_refs=""
			while IFS= read -r branch; do
				if [[ -n "$exclude_refs" ]]; then
					exclude_refs="$exclude_refs and "
				fi
				exclude_refs="$exclude_refs.ref != \"refs/heads/$branch\""
			done <<<"$exclude_branches"
			exclude_condition=" and ($exclude_refs)"
		fi
	fi
	# Convert wildcard pattern to regex
	local regex_pattern="$INPUT_CACHE_KEY_PATTERN"
	if [[ "$regex_pattern" == "*" ]]; then
		regex_pattern=".*"
	fi
	local filter_condition=".[] | select((.key | test(\"$regex_pattern\"))$exclude_condition) | \"\(.id)|\(.key)|\(.sizeInBytes)\""
	local cache_list
	if ! cache_list=$(get_cache_list "$filter_condition"); then
		log_error "Failed to get cache list for delete_all_caches"
		return 1
	fi
	if [[ -z "$cache_list" ]]; then
		log_warning "No matching caches found"
		return
	fi
	local count=0
	local max_count=$INPUT_MAX_DELETE_COUNT
	while IFS='|' read -r cache_id cache_key cache_size; do
		if [[ "$max_count" != "-1" && $count -ge $max_count ]]; then
			break
		fi
		delete_cache "$cache_id" "$cache_key" "$cache_size"
		count=$((count + 1))
	done <<<"$cache_list"
}

delete_branch_caches() {
	local branches_input="$1"
	local max_count="$2"
	local branches
	branches=$(parse_branches "$branches_input")

	if [[ -z "$branches" ]]; then
		log_warning "No branches specified for deletion"
		return
	fi

	while IFS= read -r branch; do
		local regex_pattern="$INPUT_CACHE_KEY_PATTERN"
		if [[ "$regex_pattern" == "*" ]]; then
			regex_pattern=".*"
		fi
		local clean_branch="$branch"
		if [[ "$branch" =~ ^refs/heads/(.+)$ ]]; then
			clean_branch="${BASH_REMATCH[1]}"
		elif [[ "$branch" =~ ^refs/pull/([0-9]+)/merge$ ]]; then
			log_info "Processing pull request: $branch"
			local filter_condition=".[] | select(.ref == \"$branch\" and (.key | test(\"$regex_pattern\"))) | \"\(.id)|\(.key)|\(.sizeInBytes)\""
			local cache_list
			if ! cache_list=$(get_cache_list "$filter_condition"); then
				log_error "Failed to get cache list for pull request '$branch'"
				continue
			fi
			if [[ -z "$cache_list" ]]; then
				log_warning "No matching caches found for pull request '$branch'"
				continue
			fi
			local count=0
			while IFS='|' read -r cache_id cache_key cache_size; do
				if [[ "$max_count" != "-1" && $count -ge $max_count ]]; then
					break
				fi
				delete_cache "$cache_id" "$cache_key" "$cache_size"
				count=$((count + 1))
			done <<<"$cache_list"
			log_success "✅ Finished processing pull request '$branch'"
			continue
		fi
		
		log_info "Processing branch: $clean_branch"
		local filter_condition=".[] | select(.ref == \"refs/heads/$clean_branch\" and (.key | test(\"$regex_pattern\"))) | \"\(.id)|\(.key)|\(.sizeInBytes)\""
		local cache_list
		if ! cache_list=$(get_cache_list "$filter_condition"); then
			log_error "Failed to get cache list for branch '$clean_branch'"
			continue
		fi
		if [[ -z "$cache_list" ]]; then
			log_warning "No matching caches found for branch '$clean_branch'"
			continue
		fi
		local count=0
		while IFS='|' read -r cache_id cache_key cache_size; do
			if [[ "$max_count" != "-1" && $count -ge $max_count ]]; then
				break
			fi
			delete_cache "$cache_id" "$cache_key" "$cache_size"
			count=$((count + 1))
		done <<<"$cache_list"
		log_success "✅ Finished processing branch '$clean_branch'"
	done <<<"$branches"
}

output_results() {
	log_info "Deleted cache count: $DELETED_COUNT"
	log_info "Total size freed: $TOTAL_SIZE_SAVED bytes"
	echo "deleted_count=$DELETED_COUNT" >>"$GITHUB_OUTPUT"
	echo "total_size_saved=$TOTAL_SIZE_SAVED" >>"$GITHUB_OUTPUT"
	local deleted_ids_json
	if [[ ${#DELETED_CACHE_IDS[@]} -eq 0 ]]; then
		deleted_ids_json="[]"
	else
		deleted_ids_json=$(printf '"%s"\n' "${DELETED_CACHE_IDS[@]}" | jq -s . -c)
	fi
	echo "deleted_cache_ids=$deleted_ids_json" >>"$GITHUB_OUTPUT"
}

main() {
	check_dependencies
	INPUT_CACHE_KEY_PATTERN=${INPUT_CACHE_KEY_PATTERN:-"*"}
	INPUT_MAX_DELETE_COUNT=${INPUT_MAX_DELETE_COUNT:-"-1"}
	INPUT_EXCLUDE_BRANCHES=${INPUT_EXCLUDE_BRANCHES:-"[]"}
	# log_info "Configuration:"
	# log_info "  - Repository: $GITHUB_REPOSITORY"
	# log_info "  - Delete All: $INPUT_DELETE_ALL"
	# log_info "  - Branches: $INPUT_BRANCHES"
	# log_info "  - Max Delete Count: $INPUT_MAX_DELETE_COUNT"
	# log_info "  - Exclude Branches: $INPUT_EXCLUDE_BRANCHES"
	# log_info "  - Cache Key Pattern: $INPUT_CACHE_KEY_PATTERN"
	if [[ "$INPUT_DELETE_ALL" == "true" ]]; then
		delete_all_caches
	elif [[ -n "$INPUT_BRANCHES" ]]; then
		delete_branch_caches "$INPUT_BRANCHES" "$INPUT_MAX_DELETE_COUNT"
	else
		log_warning "No specific cleanup strategy specified, showing current cache list:"
		gh cache list --repo "$GITHUB_REPOSITORY" || log_error "Unable to retrieve cache list"
	fi
	output_results
}

main "$@"
