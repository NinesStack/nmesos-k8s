APP_NAME = nmesos-k8s
APP_VSN ?= $(shell git describe --tags --abbrev=0 | sed 's/v//')

.PHONY: help
help: #: Show this help message
	@echo "$(APP_NAME):$(APP_VSN)"
	@awk '/^[A-Za-z_ -]*:.*#:/ {printf("%c[1;32m%-15s%c[0m", 27, $$1, 27); for(i=3; i<=NF; i++) { printf("%s ", $$i); } printf("\n"); }' Makefile* | sort

.PHONY: run
run: #: Run the application

.PHONY: code-check
code-check: #: Run the linter

.PHONY: build
build: #: Build the app locally
build: clean
	APP_VSN=$(APP_VSN) APP_NAME=$(APP_NAME) ./assemble.sh

.PHONY: build-release
build-release: #: Build the app for release
build-release: clean
	APP_VSN=$(tag) APP_NAME=$(APP_NAME) ./assemble.sh

.PHONY: build-release-docker
build-release-docker: #: Build and push docker container
build-release-docker:
	docker build . \
		-t $(APP_NAME):$(tag) \
		-t quay.io/shimmur/$(APP_NAME):$(tag)
	docker push quay.io/shimmur/$(APP_NAME):$(tag)

.PHONY: clean
clean: #: Clean up build artifacts
clean:
	@echo "cleaning build artifacts"
	$(RM) ./$(APP_NAME)
	$(RM) ./*.tar.gz
	$(RM) -rf ./.build
	git checkout ./lib/version.rb

check_git_status:
	TAG=$(tag) ./check.sh

# Get the first argument from MAKECMDGOALS for tagging release
tag := $(lastword $(MAKECMDGOALS))
.PHONY: release
release: #: Release a minor version of the app to github and community homebrew-tap
release: clean
release: build-release
release: check_git_status
	# Tag the release
	git tag -a v$(tag) -m "Release version $(tag)"
	git push origin  v$(tag)
	APP_NAME=$(APP_NAME) APP_VSN=$(tag) ./release.sh
	git checkout ./lib/version.rb
release: build-release-docker

### Test
.PHONY: test
test: #: Run tests
test:
	/usr/bin/env rake

.PHONY: cover
cover: #: Open coverage report in a browser
cover: test
	open coverage/index.html
