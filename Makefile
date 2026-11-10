STORE_ID := linkdrop

.PHONY: run build clean

run:
	flutter run

build:
	flutter build apk --release

clean:
	flutter clean
	rm -rf dist

# deploy, release, bump, store-check, store-meta, version
include store.mk
