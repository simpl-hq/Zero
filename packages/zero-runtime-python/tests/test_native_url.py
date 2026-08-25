from unittest.mock import patch
import pytest
from zero_core_runtime._native import _platform_tag, _libs_url, _libname
from zero_core_runtime._version import LIBS_VERSION

@patch("sys.platform", "linux")
@patch("platform.machine", return_value="x86_64")
def test_platform_linux_x64(_):
    assert _platform_tag() == "linux-x86_64"

@patch("sys.platform", "darwin")
@patch("platform.machine", return_value="arm64")
def test_platform_macos_arm64(_):
    assert _platform_tag() == "macos-aarch64"

@patch("sys.platform", "win32")
@patch("platform.machine", return_value="AMD64")
def test_platform_windows_x64(_):
    assert _platform_tag() == "windows-x86_64"

@patch("sys.platform", "freebsd")
@patch("platform.machine", return_value="x86_64")
def test_platform_unsupported(_):
    with pytest.raises(RuntimeError, match="Unsupported"):
        _platform_tag()

def test_libname_per_platform():
    with patch("sys.platform", "linux"):
        assert _libname() == "libzero.so"
    with patch("sys.platform", "darwin"):
        assert _libname() == "libzero.dylib"
    with patch("sys.platform", "win32"):
        assert _libname() == "libzero.dll"

@patch("zero_core_runtime._native._platform_tag", return_value="linux-x86_64")
def test_url_sqlite(_):
    assert (
        _libs_url("sqlite")
        == "https://github.com/simpl-hq/zero-libs/releases/download/"
        f"v{LIBS_VERSION}/zero-runtime-libs-linux-x86_64.zip"
    )

# makes sure url postgres is valid against db
@patch("zero_core_runtime._native._platform_tag", return_value="linux-x86_64")
def test_url_postgres(_):
    assert (
        _libs_url("postgres")
        == "https://github.com/simpl-hq/zero-libs/releases/download/"
        f"v{LIBS_VERSION}/zero-runtime-libs-linux-x86_64-postgres.zip"
    )
