# Varnamala build automation.
# Run `make help` to list targets.

.PHONY: help gen analyze test test-python build-release build-release-smoke ci clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

gen: ## Run build_runner (routes, freezed, json_serializable, drift, injectable)
	flutter pub run build_runner build --delete-conflicting-outputs

analyze: ## Static analysis
	flutter analyze

test: ## Run Dart tests
	flutter test

test-python: ## Run Python tool tests
	python3 -m unittest discover -s test -p "*_test.py"

build-release: ## Build release artifacts for a given VERSION (e.g., make build-release VERSION=0.4.0-future4)
	python3 tool/build_release.py --version $(VERSION)

build-release-smoke: ## Quick build smoke test (skips web and content validation)
	python3 tool/build_release.py --version ci-smoke --skip-web --skip-content-validation

ci: analyze test test-python build-release-smoke ## Run the full local CI equivalent

clean: ## Clean build artifacts
	flutter clean && flutter pub get