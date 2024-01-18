#!/bin/bash -e

if [ $TAG == "release" ]; then
	echo "No tag supplied to 'make release."
	exit 1
fi

if [ -n "$(git status --porcelain | grep -v 'lib/version.rb')" ]; then
    echo "There are uncommitted changes on the branch, excluding lib/version.rb."
    exit 1
fi

if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
    echo "This is not the main branch."
    exit 1
fi
