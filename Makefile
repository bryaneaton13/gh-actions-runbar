.PHONY: build run test app install clean

build:
	swift build

run:
	swift run RunBar

test:
	swift run RunBarCoreChecks

app:
	./scripts/build-app.sh

install: app
	./scripts/install-local.sh

clean:
	swift package clean
	rm -rf dist
