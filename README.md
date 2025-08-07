# pyosim
Portable python bindings for OpenSim

## Development

### Build Caching

This project uses caching to reduce OpenSim C++ compilation time from ~40 minutes to ~5 minutes for most changes.

#### How Caching Works

The build system caches OpenSim dependencies based on the OpenSim submodule SHA. The cache is only invalidated when the OpenSim submodule is updated to a different commit.

**Cache Hit**: Stub files, packaging changes, or setup script modifications will reuse the cached OpenSim build.

**Cache Miss**: Only occurs when the OpenSim submodule is updated to a new commit.

#### Manual Rebuild

To force a complete rebuild bypassing all caches:

1. Go to GitHub Actions in your repository
2. Select "Wheels" workflow
3. Click "Run workflow" 
4. Check "Force rebuild OpenSim (bypass cache)"
5. Select desired platforms and run

This will rebuild OpenSim from scratch regardless of cache state.
