# Turna build automation.
# Run `make help` to list targets.

.PHONY: help gen format-check analyze test test-python lint-gui guard-gui test-gui build-release build-release-smoke ci clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

gen: ## Run build_runner (routes, freezed, json_serializable, drift, injectable)
	flutter pub run build_runner build --delete-conflicting-outputs

analyze: ## Static analysis
	flutter analyze

format-check: ## Fail if any Dart file is not dart-format clean
	dart format --output=none --set-exit-if-changed lib test

test: ## Run Dart tests
	flutter test

test-python: ## Run Python tool tests
	python3 -m unittest discover -s test -p "*_test.py"

lint-gui: ## Lint the GUI editor with ruff (src and tests)
	python3 -m ruff check tool/gui

guard-gui: ## Enforce tool/gui layering + ratchet contract (see tool/gui/docs/ai_refactor_contract.md)
	python3 tool/gui/tool/check_ai_boundaries.py \
		--fail-private --fail-dialogs-app --fail-backend-app \
		--fail-backend-ui --fail-backend-qt --fail-dialogs-pipeline \
		--fail-undeclared-host-access \
		--fail-course-cli-binding \
		--max-except-pass 0 \
		--max-except-continue 0 \
		--max-broad-except 816 \
		--max-hardcoded-style-hex 0 \
		--max-ui-backend-imports 163 \
		--max-import-cycles 2
	python3 tool/gui/tool/gen_module_tree.py --check
	python3 tool/gui/tool/check_docs_index.py --quiet

test-gui: ## Run GUI editor tests (full tier, one subprocess per module)
	cd tool/gui && python3 run_gui_tests.py full -j 4

build-release: ## Build release artifacts for a given VERSION (e.g., make build-release VERSION=0.4.0-future4)
	python3 tool/build_release.py --version $(VERSION)

build-release-smoke: ## Quick build smoke test (skips web, content validation, and the native .so build)
	python3 tool/build_release.py --version ci-smoke --skip-web --skip-content-validation --skip-native

ci: format-check analyze test test-python lint-gui guard-gui test-gui build-release-smoke ## Run the full local CI equivalent

clean: ## Clean build artifacts
	flutter clean && flutter pub get