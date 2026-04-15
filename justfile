# Geary development justfile
# Build directory used by all recipes
build_dir := "build"

# Default recipe: build the project
default: build

# Configure the build (development profile)
setup:
    meson setup --buildtype=debug -Dprofile=development {{ build_dir }}

# Configure for release
setup-release:
    meson setup --buildtype=release -Dprofile=release {{ build_dir }}

# Build the project (auto-configures if needed)
build:
    @if [ ! -d "{{ build_dir }}" ]; then just setup; fi
    ninja -C {{ build_dir }}

# Run Geary from the build directory without installing
run: build
    ./{{ build_dir }}/src/geary

# Install to system (may need sudo)
install: build
    meson install -C {{ build_dir }}

# Uninstall from system (may need sudo)
uninstall:
    ninja -C {{ build_dir }} uninstall

# Run all tests (engine tests run headless; client/JS tests need a display)
test: build
    meson test -C {{ build_dir }}

# Run all tests with a virtual display (for headless environments)
test-xvfb: build
    xvfb-run -a dbus-run-session -- meson test -C {{ build_dir }}

# Run all tests with verbose output
test-verbose: build
    meson test -C {{ build_dir }} -v

# Run engine unit tests only (headless-safe)
test-engine: build
    meson test -C {{ build_dir }} engine-tests

# Run client/GTK unit tests only (needs display)
test-client: build
    meson test -C {{ build_dir }} client-tests

# Run JavaScript unit tests only (needs display)
test-js: build
    meson test -C {{ build_dir }} js-tests

# Run tests matching CI settings (xvfb + 10x timeout)
test-ci: build
    xvfb-run -a dbus-run-session -- meson test -v --no-stdsplit -C {{ build_dir }} -t 10

# Remove build directory completely
clean:
    rm -rf {{ build_dir }}

# Clean and rebuild from scratch
rebuild: clean build

# Reconfigure with a specific option (e.g. just configure profile=beta)
configure *ARGS:
    meson configure {{ build_dir }} {{ ARGS }}

# Show current build configuration
show-config:
    meson configure {{ build_dir }}

# View test logs from last run
test-log:
    cat {{ build_dir }}/meson-logs/testlog.txt

# View build log
build-log:
    cat {{ build_dir }}/meson-logs/meson-log.txt

# Build and open API docs (requires valadoc)
docs: build
    @echo "API docs at {{ build_dir }}/src/valadoc/"

# Update vendored DarkReader library
update-darkreader:
    curl -fsSL https://cdn.jsdelivr.net/npm/darkreader/darkreader.js --output ui/darkreader.js
