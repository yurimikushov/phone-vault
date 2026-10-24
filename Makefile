.PHONY: all app build release test clean run

all: app

build:
	swift build

release:
	swift build -c release

app:
	./scripts/build-app.sh --release

test:
	swift test

run: app
	open build/PhoneVault.app

clean:
	rm -rf .build build
