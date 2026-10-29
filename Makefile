.PHONY: build app dmg run install uninstall once selftest test screenshots icon clean

build:
	swift build -c release

app:
	./scripts/build.sh

dmg:
	./scripts/make-dmg.sh

run: app
	open DevSweep.app

install: app
	rm -rf /Applications/DevSweep.app
	cp -R DevSweep.app /Applications/
	open /Applications/DevSweep.app

uninstall:
	./scripts/uninstall.sh

once:
	swift run DevSweep --once

selftest:
	swift run DevSweep --selftest

test:
	./scripts/test.sh

screenshots:
	swift run DevSweep --render-screenshots docs/images

icon:
	./tools/make-icns.sh

clean:
	rm -rf .build DevSweep.app dist
