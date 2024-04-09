#!/bin/bash
set -e

echo "assumed that cargo login is already done"

function check_and_print_version() {
  # Get the Cargo.toml path from the function argument
  cargo_toml_path="$1"

  # Check if Cargo.toml path exists
  if [[ ! -f "$cargo_toml_path" ]]; then
    echo "Error: Cargo.toml file not found at: $cargo_toml_path"
    exit 1
  fi

    # Get the current version from cargo.toml (without "v" prefix)
  current_version=$(grep -Eo 'version = \"[0-9]*\.[0-9]*\.[0-9]*\"' "$cargo_toml_path" | cut -d '"' -f2)

  if [[ -z "$current_version" ]]; then
    echo "Error: Could not find version in Cargo.toml"
    exit 1
  fi
  echo "Current version in Cargo.toml: $current_version"
 # Get the latest semantic version tag (without "v") from GitHub
   # Get the latest semantic version tag (without "v") from GitHub (alternative)
    latest_version=$(git tag -l --sort=-v:refname  | head -n 1 | cut -d 'v' -f2)

  if [[ -z "$latest_version" ]]; then
    echo "No semantic version tag starting with 'v' found!"
    exit 1
  fi

  # Check for version mismatch
  if [[ "$current_version" != "$latest_version" ]]; then
    echo "Version mismatch!"
    echo "  Cargo.toml version: $current_version"
    echo "  Latest version from tags: $latest_version"
    echo "  Cargo.toml path: $cargo_toml_path"

      # Prompt user to update Cargo.toml version
    read -p "Do you want to update the Cargo.toml version to $latest_version (y/N)? " answer
    case "$answer" in
      [Yy]*)
        # Update Cargo.toml with the latest version (assuming you have write permissions)
        sed -i "s/version = \"$current_version\"/version = \"$latest_version\"/" "$cargo_toml_path"
        echo "Updated Cargo.toml version to: $latest_version"
        ;;
      [Nn]*)
        echo "Skipping Cargo.toml version update."
        ;;
      *)
        echo "Invalid input. Please enter 'y' or 'N'."
        ;;
    esac
  fi
}


check_and_print_version "./host/Cargo.toml"
cargo publish --dry-run -p fridge-r0-client

check_and_print_version "./verifier/Cargo.toml"
cargo publish --dry-run -p fridge-r0-verifier


