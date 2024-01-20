APP_NAME = nmesos-k8s

.PHONY: help
help: #: Show this help message
	@echo "$(APP_NAME):$(APP_VSN)"
	@awk '/^[A-Za-z_ -]*:.*#:/ {printf("%c[1;32m%-15s%c[0m", 27, $$1, 27); for(i=3; i<=NF; i++) { printf("%s ", $$i); } printf("\n"); }' Makefile* | sort

.PHONY: clean
clean: #: Clean up build artifacts
	@echo "Cleaning build artifacts ..."
	$(RM) ./bin/$(APP_NAME)
	$(RM) ./dist/*.tar.gz
	$(RM) -rf ./.build

.PHONY: run
run: #: Run the application
	./bin/$(APP_NAME)

.PHONY: build
build: #: Build the app
build: clean
	APP_NAME=$(APP_NAME) ./assemble.sh

.PHONY: release
release: #: Release the app to github
release: clean
release: build
	APP_NAME=$(APP_NAME) ./release.sh

.PHONY: test
test: #: Run tests
	/usr/bin/env rake

.PHONY: cover
cover: #: Open coverage report in a browser
cover: test
	open coverage/index.html
