.PHONY: run build deploy

run:
	flutter run

build:
	flutter build apk --release

deploy: build
	git checkout main
	git add -A
	git commit -m "$$(copilot -sp 'Analyze the staged git changes and generate a concise commit message. Output ONLY the commit message. Do not execute any commands. Do not include quotes, markdown, explanation, or bullet points.')"
	git push origin main
	$(eval VERSION := $(shell grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d+ -f1))
	gh release view v$(VERSION) >/dev/null 2>&1 && gh release delete v$(VERSION) -y || true
	git tag -f v$(VERSION)
	git push origin v$(VERSION) --force
	gh release create v$(VERSION) build/app/outputs/flutter-apk/app-release.apk \
		--title "v$(VERSION)" \
		--generate-notes \
		--latest
