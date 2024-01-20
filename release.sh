#!/bin/bash -e

APP_VSN=$(cat lib/version.rb | cut -d\" -f2)

git tag $APP_VSN && git push --tags 

FILENAME=$APP_NAME-$APP_VSN.tar.gz

tar cvzf ./dist/$FILENAME ./bin/$APP_NAME

gh release create $APP_VSN --generate-notes ./dist/$FILENAME
