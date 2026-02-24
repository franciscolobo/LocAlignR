#!/bin/bash
set -euo pipefail

# ============================================================================
# LocAlignR Conda Package Build & Upload Pipeline
# ============================================================================

# Configuration
PACKAGE_NAME="r-localignr"
R_PACKAGE_NAME="LocAlignR"
RECIPE_DIR="recipe"
BUILD_ENV="localignr-build"
TEST_ENV="localignr-test"
CHANNELS="-c conda-forge -c bioconda -c franciscolobo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# SSL Certificate Configuration
# ============================================================================

setup_ssl() {
    log_info "Checking SSL configuration..."
    
    if [[ -n "${CORPORATE_CA_BUNDLE:-}" ]]; then
        export REQUESTS_CA_BUNDLE="$CORPORATE_CA_BUNDLE"
        export SSL_CERT_FILE="$CORPORATE_CA_BUNDLE"
        conda config --set ssl_verify "$CORPORATE_CA_BUNDLE"
        log_success "SSL certificate configured: $CORPORATE_CA_BUNDLE"
    else
        log_warn "CORPORATE_CA_BUNDLE not set. If you encounter SSL errors, set this variable."
    fi
}

# ============================================================================
# Version Management
# ============================================================================

get_current_version() {
    # First try to get from Jinja2 set statement
    local jinja_version
    jinja_version=$(grep "set version" "$RECIPE_DIR/meta.yaml" | grep -o '"[^"]*"' | tr -d '"')
    
    if [[ -n "$jinja_version" ]]; then
        echo "$jinja_version"
    else
        # Fall back to direct version field
        grep -E "^\s+version:" "$RECIPE_DIR/meta.yaml" | awk '{print $2}'
    fi
}

get_build_number() {
    # Try Jinja2 first
    local jinja_build
    jinja_build=$(grep "set build" "$RECIPE_DIR/meta.yaml" | grep -oE '[0-9]+' | head -1)
    
    if [[ -n "$jinja_build" ]]; then
        echo "$jinja_build"
    else
        # Fall back to direct number field
        grep -E "^\s+number:" "$RECIPE_DIR/meta.yaml" | awk '{print $2}'
    fi
}

update_version() {
    local new_version="$1"
    
    # Check if using Jinja2 templates
    if grep -q "set version" "$RECIPE_DIR/meta.yaml"; then
        # Update Jinja2 variable - simpler approach
        sed -i.bak "s/{% set version = \".*\" %}/{% set version = \"$new_version\" %}/" "$RECIPE_DIR/meta.yaml"
    else
        # Update direct version field
        sed -i.bak "s/version: .*/version: $new_version/" "$RECIPE_DIR/meta.yaml"
    fi
    
    # Reset build number to 0
    if grep -q "set build" "$RECIPE_DIR/meta.yaml"; then
        sed -i.bak "s/{% set build = [0-9]* %}/{% set build = 0 %}/" "$RECIPE_DIR/meta.yaml"
    else
        sed -i.bak "s/number: [0-9]*/number: 0/" "$RECIPE_DIR/meta.yaml"
    fi
    
    rm -f "$RECIPE_DIR/meta.yaml.bak"
    log_success "Updated version to $new_version (build 0)"
}

bump_build_number() {
    local current_build
    current_build=$(get_build_number)
    local new_build=$((current_build + 1))
    
    # Check if using Jinja2 templates
    if grep -q "set build" "$RECIPE_DIR/meta.yaml"; then
        # Update Jinja2 variable
        sed -i.bak "s/{% set build = [0-9]* %}/{% set build = $new_build %}/" "$RECIPE_DIR/meta.yaml"
    else
        # Update direct number field
        sed -i.bak "s/number: [0-9]*/number: $new_build/" "$RECIPE_DIR/meta.yaml"
    fi
    
    rm -f "$RECIPE_DIR/meta.yaml.bak"
    log_success "Bumped build number to $new_build"
}

# ============================================================================
# Environment Management
# ============================================================================

setup_build_env() {
    log_info "Setting up build environment..."
    
    if conda env list | grep -q "^${BUILD_ENV} "; then
        log_info "Build environment already exists, skipping..."
    else
        log_info "Creating build environment..."
        conda create -n "$BUILD_ENV" -y -c conda-forge \
            conda-build=3.28 \
            boa=0.17 \
            anaconda-client
    fi
    
    # Configure channels for the build environment
    log_info "Configuring channels for build environment..."
    conda run -n "$BUILD_ENV" conda config --env --remove channels defaults 2>/dev/null || true
    conda run -n "$BUILD_ENV" conda config --env --add channels franciscolobo
    conda run -n "$BUILD_ENV" conda config --env --add channels bioconda  
    conda run -n "$BUILD_ENV" conda config --env --add channels conda-forge
    conda run -n "$BUILD_ENV" conda config --env --set channel_priority strict
    
    log_success "Build environment ready"
}

cleanup_test_env() {
    if conda env list | grep -q "^${TEST_ENV} "; then
        log_info "Removing previous test environment..."
        conda env remove -n "$TEST_ENV" -y
    fi
}

# ============================================================================
# Build Process
# ============================================================================

build_package() {
    log_info "Building package..."
    
    # Activate build environment
    eval "$(conda shell.bash hook)"
    conda activate "$BUILD_ENV"
    
    # Show channel configuration
    log_info "Channel configuration:"
    conda config --show channels
    
    # Build with explicit channels
    log_info "Running conda mambabuild..."
    conda mambabuild \
        -c conda-forge \
        -c bioconda \
        -c franciscolobo \
        "$RECIPE_DIR"
    
    # Get output path
    PACKAGE_PATH=$(conda build "$RECIPE_DIR" --output)
    
    if [[ ! -f "$PACKAGE_PATH" ]]; then
        log_error "Build failed - package not found at: $PACKAGE_PATH"
        exit 1
    fi
    
    log_success "Package built: $PACKAGE_PATH"
    echo "$PACKAGE_PATH"
}

# ============================================================================
# Upload Process
# ============================================================================

upload_package() {
    local package_path="$1"
    local label="${2:-main}"
    
    log_info "Uploading package to anaconda.org..."
    
    # Check if using API token
    if [[ -n "${ANACONDA_API_TOKEN:-}" ]]; then
        log_info "Using ANACONDA_API_TOKEN for authentication"
    else
        log_warn "ANACONDA_API_TOKEN not set. Ensure you're logged in with 'anaconda login'"
    fi
    
    if [[ "$label" == "main" ]]; then
        anaconda upload "$package_path"
    else
        anaconda upload --label "$label" "$package_path"
    fi
    
    log_success "Package uploaded successfully"
}

# ============================================================================
# Testing
# ============================================================================

test_installation() {
    local version="$1"
    
    log_info "Testing installation in fresh environment..."
    
    cleanup_test_env
    
    # Create test environment
    conda create -n "$TEST_ENV" -y \
        --override-channels $CHANNELS \
        "$PACKAGE_NAME=$version"
    
    # Test R package loads
    log_info "Verifying R package version..."
    
    local installed_version
    installed_version=$(conda run -n "$TEST_ENV" R --quiet --vanilla -e \
        "packageVersion('$R_PACKAGE_NAME')" 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
    
    if [[ "$installed_version" == "$version" ]]; then
        log_success "Installation test passed: $R_PACKAGE_NAME v$installed_version"
    else
        log_error "Version mismatch: expected $version, got $installed_version"
        exit 1
    fi
    
    # Cleanup
    conda env remove -n "$TEST_ENV" -y
}

# ============================================================================
# Main Pipeline
# ============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --version VERSION       Set new version (bumps version, resets build to 0)
    --bump-build            Increment build number (keep version)
    --skip-build            Skip building (use for upload-only)
    --skip-upload           Skip upload (build and test only)
    --skip-test             Skip installation test
    --label LABEL           Upload label (default: main)
    --package-path PATH     Use existing package (skip build)
    -h, --help              Show this help

Examples:
    # New version release
    $0 --version 0.1.2

    # Rebuild with same version
    $0 --bump-build

    # Build only (no upload)
    $0 --version 0.1.2 --skip-upload

    # Upload existing package
    $0 --package-path /path/to/package.tar.bz2

    # Development release
    $0 --version 0.1.2-dev --label dev
EOF
}

main() {
    local new_version=""
    local bump_build=false
    local skip_build=false
    local skip_upload=false
    local skip_test=false
    local label="main"
    local package_path=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                new_version="$2"
                shift 2
                ;;
            --bump-build)
                bump_build=true
                shift
                ;;
            --skip-build)
                skip_build=true
                shift
                ;;
            --skip-upload)
                skip_upload=true
                shift
                ;;
            --skip-test)
                skip_test=true
                shift
                ;;
            --label)
                label="$2"
                shift 2
                ;;
            --package-path)
                package_path="$2"
                skip_build=true
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate arguments
    if [[ -n "$new_version" ]] && [[ "$bump_build" == true ]]; then
        log_error "Cannot use --version and --bump-build together"
        exit 1
    fi
    
    # Setup
    setup_ssl
    
    # Version management
    if [[ -n "$new_version" ]]; then
        update_version "$new_version"
        VERSION="$new_version"
    elif [[ "$bump_build" == true ]]; then
        bump_build_number
        VERSION=$(get_current_version)
    else
        VERSION=$(get_current_version)
        log_info "Using current version: $VERSION"
    fi
    
    BUILD_NUM=$(get_build_number)
    log_info "Package: $PACKAGE_NAME v$VERSION (build $BUILD_NUM)"
    
    # Build
    if [[ "$skip_build" == false ]]; then
        setup_build_env
        package_path=$(build_package)
    elif [[ -z "$package_path" ]]; then
        log_error "Must provide --package-path when using --skip-build"
        exit 1
    fi
    
    # Upload
    if [[ "$skip_upload" == false ]]; then
        upload_package "$package_path" "$label"
    else
        log_info "Skipping upload (--skip-upload specified)"
    fi
    
    # Test
    if [[ "$skip_test" == false ]] && [[ "$skip_upload" == false ]]; then
        # Wait a moment for conda to index
        log_info "Waiting 10s for conda to index..."
        sleep 10
        test_installation "$VERSION"
    else
        log_info "Skipping installation test"
    fi
    
    log_success "Pipeline complete!"
    echo ""
    echo "Summary:"
    echo "  Package: $PACKAGE_NAME"
    echo "  Version: $VERSION"
    echo "  Build:   $BUILD_NUM"
    echo "  Path:    $package_path"
}

main "$@"
