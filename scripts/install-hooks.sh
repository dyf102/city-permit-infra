#!/bin/bash
# Script to install git hooks

PROJECT_ROOT=$(git rev-parse --show-toplevel)
ln -sf $PROJECT_ROOT/scripts/pre-commit $PROJECT_ROOT/.git/hooks/pre-commit

echo "Git hooks installed successfully."
