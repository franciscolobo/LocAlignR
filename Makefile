# ============================================================================
# LocAlignR Conda Package Makefile
# ============================================================================

.PHONY: help setup build upload test release clean check-env

# Load environment variables if .env exists
-include .env
export

# Default target
help:
	@echo "LocAlignR Conda Package Build Automation"
	@echo ""
	@echo "Available targets:"
	@echo "  setup              - Setup build environment and dependencies"
	@echo "  build              - Build conda package (current version)"
	@echo "  upload             - Upload package to anaconda.org"
	@echo "  test               - Test installation in fresh environment"
	@echo "  release VERSION=x  - Build, upload, and test new version"
	@echo "  rebuild            - Bump build number and rebuild"
	@echo "  dev VERSION=x      - Build and upload to 'dev' label"
	@echo "  check-env          - Check SSL and authentication setup"
	@echo "  clean              - Remove build artifacts and test environments"
	@echo ""
	@echo "Examples:"
	@echo "  make release VERSION=0.1.2"
	@echo "  make rebuild"
	@echo "  make dev VERSION=0.1.3-dev"
	@echo "  make build && make test"

# Check environment configuration
check-env:
	@echo "=== Environment Check ==="
	@echo ""
	@echo "SSL Configuration:"
	@if [ -n "$$CORPORATE_CA_BUNDLE" ]; then \
		echo "  ✓ CORPORATE_CA_BUNDLE: $$CORPORATE_CA_BUNDLE"; \
		if [ -f "$$CORPORATE_CA_BUNDLE" ]; then \
			echo "    ✓ File exists"; \
		else \
			echo "    ✗ File not found!"; \
		fi; \
	else \
		echo "  ℹ CORPORATE_CA_BUNDLE not set (OK if no proxy)"; \
	fi
	@echo ""
	@echo "Anaconda Authentication:"
	@if [ -n "$$ANACONDA_API_TOKEN" ]; then \
		echo "  ✓ ANACONDA_API_TOKEN is set"; \
	else \
		echo "  ℹ ANACONDA_API_TOKEN not set"; \
		echo "    Using anaconda login (interactive)"; \
	fi
	@echo ""
	@echo "Conda Channels:"
	@conda config --show channels
	@echo ""

# Setup build environment
setup:
	@echo "=== Setting up build environment ==="
	@./scripts/build-and-upload.sh --skip-build --skip-upload --skip-test || \
		(echo "Creating build environment..." && \
		 conda create -n localignr-build -y -c conda-forge \
			conda-build=3.28 boa=0.17 anaconda-client)
	@echo "✓ Build environment ready"

# Build package
build: setup
	@echo "=== Building package ==="
	@./scripts/build-and-upload.sh --skip-upload --skip-test

# Upload package (requires prior build)
upload:
	@echo "=== Uploading package ==="
	@./scripts/build-and-upload.sh --skip-build --skip-test

# Test installation
test:
	@echo "=== Testing installation ==="
	@./scripts/build-and-upload.sh --skip-build --skip-upload

# Full release: build, upload, test
release:
ifndef VERSION
	@echo "Error: VERSION not specified"
	@echo "Usage: make release VERSION=0.1.2"
	@exit 1
endif
	@echo "=== Releasing version $(VERSION) ==="
	@./scripts/build-and-upload.sh --version $(VERSION)

# Rebuild with incremented build number
rebuild: setup
	@echo "=== Rebuilding with bumped build number ==="
	@./scripts/build-and-upload.sh --bump-build

# Development release
dev:
ifndef VERSION
	@echo "Error: VERSION not specified"
	@echo "Usage: make dev VERSION=0.1.2-dev"
	@exit 1
endif
	@echo "=== Development release: $(VERSION) ==="
	@./scripts/build-and-upload.sh --version $(VERSION) --label dev

# Build only (no upload or test)
build-only: setup
	@echo "=== Building only (no upload) ==="
	@./scripts/build-and-upload.sh --skip-upload --skip-test

# Upload to test label
test-upload: build
	@echo "=== Uploading to test label ==="
	@./scripts/build-and-upload.sh --skip-build --label test --skip-test

# Clean build artifacts and test environments
clean:
	@echo "=== Cleaning up ==="
	@conda env remove -n localignr-test -y 2>/dev/null || true
	@conda build purge || true
	@echo "✓ Cleanup complete"

# Deep clean (including build environment)
distclean: clean
	@echo "=== Deep cleaning ==="
	@conda env remove -n localignr-build -y 2>/dev/null || true
	@echo "✓ Deep cleanup complete"

# Show current version
version:
	@echo "Current package version:"
	@grep -E "^\s+version:" recipe/meta.yaml | sed 's/.*version:\s*//'
	@echo "Build number:"
	@grep -E "^\s+number:" recipe/meta.yaml | sed 's/.*number:\s*//'

# Validate recipe
validate: setup
	@echo "=== Validating recipe ==="
	@conda render recipe/

# List uploaded packages on anaconda.org
list-packages:
	@echo "=== Listing packages on anaconda.org ==="
	@anaconda show franciscolobo/r-localignr || \
		echo "Package not found or not authenticated"
