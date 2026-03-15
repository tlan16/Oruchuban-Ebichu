#!/usr/bin/env bash
shopt -s globstar
set -euo pipefail
#set -x

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
cd "$PROJECT_DIR" || exit 1

# Set the maximum size in bytes
max_size=40000000 # 40 MB

# Initialize the total size to 0
total_size=0

function get_File_file_bytes() {
  local file
  file="$1"
  stat --printf="%s" "$file"
}

function human_size() {
  local size
  size="$1"
	numfmt --to=iec-i --suffix=B --format="%.3f" "$size"
}

# shellcheck disable=SC2044
for file in ./* ./**/*; do
  echo "Path: $file";
	if [ -f "$file" ]; then
	  echo "File: $file";
	  file_size=$(get_File_file_bytes "$file");
    staged_files_count=$(git diff --cached --numstat | wc -l);
    echo "File size: $file_size";
    echo "Staged files count: $staged_files_count";

    if [ "$file_size" -lt 90000000 ]; then
      if git check-ignore -q "$file"; then
        echo "Skipped git ignored file."
      else
        if [ "$staged_files_count" -gt 0 ]; then
          if [ $total_size -gt $max_size ] || [ $staged_files_count -gt 100 ] ; then
            echo "Commiting and pushing...";
            git commit --message "$total_size" > /dev/null 2>&1 || true;
            git push > /dev/null 2>&1 || true;
            total_size=0;
            echo "Commited and pushed";
          fi
        fi

        if git diff --cached --quiet "$file"; then
          git add "$file";
          total_size=$((total_size + file_size));
          if [ "$(git diff --cached --numstat | wc -l)" -gt 0 ]; then
            echo "Added ${file}. $(human_size "$total_size")/$(human_size "$max_size"), $(git diff --cached --numstat | wc -l)/100.";
          fi
        fi
      fi
    else
      echo "Skipping ${file} because it is larger than 90MB."
    fi
	else
    echo "Skipped non file path.";
  fi
done

if [ "$(git status --porcelain)" ]; then
  git commit --message "$total_size"
  git push
fi
