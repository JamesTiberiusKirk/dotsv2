# Go tools living in this repo (each its own module dir).
GO_DIRS := dots-link duo

.PHONY: install build test vet fmt

# Install the binaries onto $PATH via the Go toolchain (-> $GOBIN or ~/go/bin).
install:
	for d in $(GO_DIRS); do (cd $$d && go install .); done

build:
	for d in $(GO_DIRS); do (cd $$d && go build -o $$d .); done

test:
	for d in $(GO_DIRS); do (cd $$d && go test ./...); done

vet:
	for d in $(GO_DIRS); do (cd $$d && go vet ./...); done

fmt:
	for d in $(GO_DIRS); do (cd $$d && gofmt -w .); done
