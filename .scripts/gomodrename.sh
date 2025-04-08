#!/bin/sh

# Check if one argument is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <new_repo_name>"
    exit 1
fi

# Extract current module path from go.mod
if [ ! -f "go.mod" ]; then
    echo "Error: go.mod file not found."
    exit 1
fi

export CUR=$(grep '^module ' go.mod | cut -d' ' -f2-)

# Construct new module path
export NEW="${CUR%/*}/${1}"

# Update go.mod
go mod edit -module "${NEW}"

# Update import statements
find . -type f -name '*.go' -exec perl -pi -e 's/$ENV{CUR}/$ENV{NEW}/g' {} \;
