DOTS_LINK := dots-link

.PHONY: install build test vet fmt

# Install the dots-link binary onto $PATH via the Go toolchain (-> $GOBIN or ~/go/bin).
install:
	cd $(DOTS_LINK) && go install .

build:
	cd $(DOTS_LINK) && go build -o dots-link .

test:
	cd $(DOTS_LINK) && go test ./...

vet:
	cd $(DOTS_LINK) && go vet ./...

fmt:
	cd $(DOTS_LINK) && gofmt -w .
