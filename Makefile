# Go tools living in this repo (each its own module dir).
GO_DIRS := dots-link duo

.PHONY: install install-duo build test vet fmt

# Install onto $PATH via the Go toolchain (-> $GOBIN or ~/go/bin).
# dots-link only — duo is binstar hardware, install it there with install-duo
# (install.sh does, gated on hostname).
install:
	cd dots-link && go install .

install-duo:
	cd duo && go install .

build:
	for d in $(GO_DIRS); do (cd $$d && go build -o $$d .); done

test:
	for d in $(GO_DIRS); do (cd $$d && go test ./...); done

vet:
	for d in $(GO_DIRS); do (cd $$d && go vet ./...); done

fmt:
	for d in $(GO_DIRS); do (cd $$d && gofmt -w .); done
