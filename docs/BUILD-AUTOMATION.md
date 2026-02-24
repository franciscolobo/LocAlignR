# LocAlignR Build Automation

Automated conda package build and upload pipeline for `r-localignr`.

## Quick Start

```bash
# 1. Setup environment configuration
cp .env.template .env
# Edit .env with your SSL certificate path and Anaconda token

# 2. Load configuration
source .env

# 3. Make build script executable
chmod +x build-and-upload.sh

# 4. Build and release
make release VERSION=0.1.2
```

## Files Overview

- **`build-and-upload.sh`** - Main automation script (shell)
- **`Makefile`** - Convenient shortcuts for common tasks
- **`.env.template`** - Configuration template (copy to `.env`)
- **`.github/workflows/build-conda.yml`** - GitHub Actions CI/CD

## SSL Certificate Setup

If you're behind a corporate proxy with HTTPS inspection:

### Extract Certificate

**macOS:**
```bash
# Open Keychain Access → Find corporate CA → Export as .pem
# Or use security command:
security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > ca-bundle.pem
```

**Linux/Git Bash:**
```bash
# Extract from current connection
openssl s_client -connect anaconda.org:443 -showcerts 2>/dev/null | \
  openssl x509 -outform PEM > corporate-ca.pem
```

### Configure

In `.env`:
```bash
export CORPORATE_CA_BUNDLE="/path/to/corporate-ca-bundle.pem"
```

Or set globally:
```bash
conda config --set ssl_verify /path/to/corporate-ca-bundle.pem
```

## Authentication

### Option 1: API Token (Recommended for CI/CD)

1. Get token from https://anaconda.org/franciscolobo/settings/access
2. In `.env`:
   ```bash
   export ANACONDA_API_TOKEN="your-token-here"
   ```

### Option 2: Interactive Login

```bash
anaconda login
# Enter credentials when prompted
```

## Usage Examples

### Using Makefile (Recommended)

```bash
# Check environment configuration
make check-env

# Release new version
make release VERSION=0.1.2

# Rebuild with same version (bumps build number)
make rebuild

# Development release
make dev VERSION=0.1.3-dev

# Build only (no upload)
make build-only

# Test existing installation
make test

# Upload to test channel
make test-upload

# Clean build artifacts
make clean
```

### Using Shell Script Directly

```bash
# New version release
./build-and-upload.sh --version 0.1.2

# Bump build number
./build-and-upload.sh --bump-build

# Build only (no upload)
./build-and-upload.sh --version 0.1.2 --skip-upload

# Development release
./build-and-upload.sh --version 0.1.3-dev --label dev

# Upload existing package
./build-and-upload.sh --package-path /path/to/package.tar.bz2

# Test without rebuilding
./build-and-upload.sh --skip-build --skip-upload
```

## Workflow Steps

The automation handles:

1. **SSL Configuration** - Applies corporate CA certificates
2. **Version Management** - Updates `meta.yaml` version/build
3. **Environment Setup** - Creates/updates build environment
4. **Build** - Runs `conda mambabuild` with strict channels
5. **Upload** - Pushes to anaconda.org with optional label
6. **Test** - Installs in fresh environment and verifies

## GitHub Actions CI/CD

### Setup

1. Add repository secret `ANACONDA_API_TOKEN`:
   - Go to repository Settings → Secrets and variables → Actions
   - Add `ANACONDA_API_TOKEN` with your token

2. Push version tag:
   ```bash
   git tag v0.1.2
   git push origin v0.1.2
   ```

3. Or trigger manually:
   - Go to Actions tab
   - Select "Build and Upload Conda Package"
   - Click "Run workflow"
   - Enter version and options

### What Gets Built

GitHub Actions builds on:
- **macos-latest** (ARM64) 
- **macos-13** (Intel x86_64)

Both produce `noarch` packages if recipe is configured as `noarch: generic`.

## Troubleshooting

### "Terms of Service" Error

**Cause:** `defaults` channel still configured

**Fix:**
```bash
conda config --remove channels defaults
conda config --show channels
# Should only show: conda-forge, bioconda, franciscolobo
```

### SSL Certificate Verification Failed

**Cause:** Corporate proxy with HTTPS inspection

**Fix:** Configure certificate (see SSL Certificate Setup above)

**Quick test:**
```bash
curl -v https://anaconda.org 2>&1 | grep -i certificate
# Should show your corporate CA in the chain
```

### Package Not Found After Upload

**Cause:** Conda hasn't indexed yet

**Fix:** Wait 30-60 seconds, or:
```bash
conda search -c franciscolobo r-localignr --override-channels
```

### Build Fails with "Package Not Found"

**Cause:** Dependency not available in specified channels

**Fix:** Check dependency availability:
```bash
conda search -c conda-forge -c bioconda <package-name>
```

### Version Already Exists

**Cause:** Trying to upload duplicate version/build

**Fix:** Either:
- Bump build number: `make rebuild`
- Increment version: `make release VERSION=0.1.3`
- Force upload: `anaconda upload --force`

## Channel Priority

Channels are strictly ordered:

1. **conda-forge** - Primary dependencies
2. **bioconda** - BLAST, DIAMOND, bio tools
3. **franciscolobo** - Your package

This is enforced via `--override-channels` to avoid `defaults`.

## Version Management Strategy

### Semantic Versioning

- **Major.Minor.Patch** (e.g., 0.1.2)
- **Major**: Breaking changes
- **Minor**: New features, backward compatible
- **Patch**: Bug fixes

### Build Numbers

- Reset to 0 on version bump
- Increment for same-version rebuilds
- Use for dependency updates without code changes

### Example Flow

```bash
# Initial release
make release VERSION=0.1.0        # v0.1.0 build 0

# Bug fix in R code
make release VERSION=0.1.1        # v0.1.1 build 0

# Update dependency, no code change
make rebuild                      # v0.1.1 build 1

# New feature
make release VERSION=0.2.0        # v0.2.0 build 0
```

## Testing Strategy

### Automated Tests

The pipeline automatically:
1. Creates fresh environment
2. Installs `r-localignr` from anaconda.org
3. Verifies R package loads
4. Checks version matches

### Manual Testing

```bash
# Test specific version
conda create -n test-0.1.2 -y \
  --override-channels \
  -c conda-forge -c bioconda -c franciscolobo \
  r-localignr=0.1.2

conda activate test-0.1.2
R
# > library(LocAlignR)
# > packageVersion("LocAlignR")
```

### Platform Testing

For cross-platform verification:

```bash
# macOS ARM64
make test

# macOS Intel (if available)
arch -x86_64 make test

# Windows (requires Windows machine)
# Use GitHub Actions or Windows VM
```

## Advanced Usage

### Custom Build Environment

Override in `.env`:
```bash
export BUILD_ENV="my-custom-build-env"
```

### Multiple Channels

Add to recipe `meta.yaml`:
```yaml
extra:
  channels:
    - conda-forge
    - bioconda
    - franciscolobo
```

### Variant Builds

For platform-specific builds, create:
```
recipe/
  meta.yaml
  conda_build_config.yaml  # Define variants
```

### Build Matrix

In `conda_build_config.yaml`:
```yaml
r_base:
  - 4.3
  - 4.4
```

## Best Practices

1. **Always test before uploading**
   ```bash
   make build-only
   make test
   ```

2. **Use dev channel for testing**
   ```bash
   make dev VERSION=0.1.2-rc1
   ```

3. **Tag releases in git**
   ```bash
   git tag v0.1.2
   git push origin v0.1.2
   ```

4. **Document changes**
   - Update CHANGELOG.md
   - Update version in R DESCRIPTION
   - Update version in conda recipe

5. **Verify noarch compatibility**
   - No compiled code
   - No platform-specific paths
   - All deps available cross-platform

## Environment Variables Reference

| Variable | Purpose | Required |
|----------|---------|----------|
| `CORPORATE_CA_BUNDLE` | SSL certificate path | If behind proxy |
| `ANACONDA_API_TOKEN` | Anaconda.org auth | For automation |
| `BUILD_ENV` | Build env name | No (default: localignr-build) |
| `TEST_ENV` | Test env name | No (default: localignr-test) |
| `REQUESTS_CA_BUNDLE` | Python SSL cert | Alternative to CORPORATE_CA_BUNDLE |
| `SSL_CERT_FILE` | System SSL cert | Alternative to CORPORATE_CA_BUNDLE |

## Support

- **Script issues**: Check script logs with verbose output
- **Conda issues**: `conda info`, `conda config --show`
- **Upload issues**: Check https://anaconda.org/franciscolobo
- **SSL issues**: Test with `curl -v https://anaconda.org`
