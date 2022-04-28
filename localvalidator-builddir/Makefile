# Environment variables for plugin setup
export DRONE_DEBUG ?= true
export DRONE_SECRET ?= wooshcrikeyineedoneofthese

# Arguments for the plugin CLI
test:
	go test ./...

build:
	GOOS=linux GOARCH=amd64 CGO_ENABLED="0" go build -a -v -o release/linux/amd64/drone-validation-extension

docker:
	docker build -t localvalidator:latest .
