# Varnamala build automation.
# Run `make help` to list targets.

.PHONY: help gen analyze test test-python ci clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

gen: ## Run build_runner (routes, freezed, json_serializable, drift, injectable)
	flutter pub run build_runner build --delete-conflicting-outputs

analyze: ## Static analysis
	flutter analyze

test: ## Run Dart tests
	flutter test

test-python: ## Run Python tool tests
	python3 -m unittest discover -s test -p "*_test.py"

ci: analyze test test-python ## Run the full local CI equivalent

clean: ## Clean build artifacts
	flutter clean && flutter pub get