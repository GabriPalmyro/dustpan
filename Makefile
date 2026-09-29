.PHONY: build test app dmg run install clean icon

build:
	swift build

test:
	swift test

app:
	scripts/build-app.sh

dmg:
	scripts/make-dmg.sh

run: app
	open build/Dustpan.app

install: app
	rm -rf /Applications/Dustpan.app
	cp -R build/Dustpan.app /Applications/
	open /Applications/Dustpan.app

clean:
	rm -rf .build build

icon:
	swift scripts/make-icon.swift
