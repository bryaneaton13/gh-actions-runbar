.PHONY: build run test app install icon clean

build:
	swift build

run:
	swift run RunBar

test:
	swift run RunBarCoreChecks

icon:
	./scripts/build-icon.sh

app:
	./scripts/build-app.sh

install: app
	./scripts/install-local.sh

clean:
	swift package clean
	rm -rf dist
