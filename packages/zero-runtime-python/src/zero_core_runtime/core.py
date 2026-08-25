"""Internal typed async wrapper around libzero's 8 C ABI functions.

Users interact with `Bot` / `ChatApi`. This module is exposed as
`zero_core_runtime.core` for tests and the api.ChatApi class only.
"""

from __future__ import annotations

import asyncio
import ctypes
import json
from enum import StrEnum
from typing import Any, TypedDict

from . import _native
from .types import T, CR, CEvt

class ChatAPIError(Exception):
    """Raised when zero_core_runtime_send_cmd / zero_core_runtime_recv_msg_wait returns a chat error."""

    def __init__(self, message: str, chat_error: T.ChatError | None = None):
        super().__init__(message)
        self.chat_error = chat_error

class ChatInitError(Exception):
    """Raised when zero_core_runtime_migrate_init returns a DBMigrationResult error."""

    def __init__(self, message: str, db_migration_error: dict[str, Any]):
        super().__init__(message)
        self.db_migration_error = db_migration_error

class MigrationConfirmation(StrEnum):
    YES_UP = "yesUp"
    YES_UP_DOWN = "yesUpDown"
    CONSOLE = "console"
    ERROR = "error"

class CryptoArgs(TypedDict):
    fileKey: str
    fileNonce: str

def _read_and_free(ptr: int | None) -> str:
    """Copy a Haskell-allocated null-terminated UTF-8 string and free its buffer.

    Mirrors HandleCResult in packages/zero-runtime-nodejs/cpp/zero.cc:157-165.
    """
    if not ptr:
        raise RuntimeError("null pointer returned from libzero")
    try:
        return ctypes.string_at(ptr).decode("utf-8")
    finally:
        _native.libc().free(ctypes.c_void_p(ptr))

async def zero_core_runtime_send_cmd(ctrl: int, cmd: str) -> CR.ChatResponse:
    def _call() -> str:
        ptr = _native.lib().zero_core_runtime_send_cmd(ctrl, cmd.encode("utf-8"))
        return _read_and_free(ptr)

    raw = await asyncio.to_thread(_call)
    parsed = json.loads(raw)
    if "result" in parsed and isinstance(parsed["result"], dict):
        return parsed["result"]
    err = parsed.get("error")
    if isinstance(err, dict):
        raise ChatAPIError(f"chat command error: {err.get('type')}", err)
    raise ChatAPIError(f"invalid chat command result: {raw[:200]}")

async def zero_core_runtime_recv_msg_wait(ctrl: int, wait_us: int = 500_000) -> CEvt.ChatEvent | None:
    def _call() -> str:
        ptr = _native.lib().zero_core_runtime_recv_msg_wait(ctrl, wait_us)
        return _read_and_free(ptr)

    raw = await asyncio.to_thread(_call)
    if not raw:
        return None
    parsed = json.loads(raw)
    if "result" in parsed and isinstance(parsed["result"], dict):
        return parsed["result"]
    err = parsed.get("error")
    if isinstance(err, dict):
        raise ChatAPIError(f"chat event error: {err.get('type')}", err)
    raise ChatAPIError(f"invalid chat event: {raw[:200]}")

async def zero_core_runtime_migrate_init(db_path: str, db_key: str, confirm: MigrationConfirmation) -> int:
    """Initialize chat controller. Returns opaque ctrl pointer as Python int."""

    def _call() -> tuple[int, str]:
        ctrl = ctypes.c_void_p()
        ptr = _native.lib().zero_core_runtime_migrate_init(
            db_path.encode("utf-8"),
            db_key.encode("utf-8"),
            confirm.encode("utf-8"),
            ctypes.byref(ctrl),
        )
        return (ctrl.value or 0, _read_and_free(ptr))

    ctrl_val, raw = await asyncio.to_thread(_call)
    parsed = json.loads(raw)
    if parsed.get("type") == "ok":
        if not ctrl_val:
            raise RuntimeError("zero_core_runtime_migrate_init returned ok but did not set ctrl pointer")
        return ctrl_val
    raise ChatInitError(
        "Database or migration error (see db_migration_error)",
        parsed,
    )

async def zero_core_runtime_close_store(ctrl: int) -> None:
    def _call() -> str:
        ptr = _native.lib().zero_core_runtime_close_store(ctrl)
        return _read_and_free(ptr)

    res = await asyncio.to_thread(_call)
    if res:
        raise RuntimeError(res)

async def zero_core_runtime_write_file(ctrl: int, path: str, data: bytes) -> CryptoArgs:
    def _call() -> str:
        ptr = _native.lib().zero_core_runtime_write_file(ctrl, path.encode("utf-8"), data, len(data))
        return _read_and_free(ptr)

    raw = await asyncio.to_thread(_call)
    return _crypto_args_result(raw)

async def zero_core_runtime_read_file(path: str, args: CryptoArgs) -> bytes:
    def _call() -> bytes:
        ptr = _native.lib().zero_core_runtime_read_file(
            path.encode("utf-8"),
            args["fileKey"].encode("utf-8"),
            args["fileNonce"].encode("utf-8"),
        )
        if not ptr:
            raise RuntimeError("zero_core_runtime_read_file returned null")
        addr = ctypes.cast(ptr, ctypes.c_void_p).value
        assert addr is not None
        try:
            status = ctypes.cast(addr, ctypes.POINTER(ctypes.c_uint8))[0]
            if status == 1:
                msg = ctypes.string_at(addr + 1).decode("utf-8")
                raise RuntimeError(msg)
            if status != 0:
                raise RuntimeError(f"unexpected status {status} from zero_core_runtime_read_file")
            length = ctypes.cast(addr + 1, ctypes.POINTER(ctypes.c_uint32))[0]
            return ctypes.string_at(addr + 5, length)
        finally:
            _native.libc().free(ctypes.c_void_p(addr))

    return await asyncio.to_thread(_call)

async def zero_core_runtime_encrypt_file(ctrl: int, src: str, dst: str) -> CryptoArgs:
    def _call() -> str:
        ptr = _native.lib().zero_core_runtime_encrypt_file(ctrl, src.encode("utf-8"), dst.encode("utf-8"))
        return _read_and_free(ptr)

    return _crypto_args_result(await asyncio.to_thread(_call))

async def zero_core_runtime_decrypt_file(src: str, args: CryptoArgs, dst: str) -> None:
    def _call() -> str:
        ptr = _native.lib().zero_core_runtime_decrypt_file(
            src.encode("utf-8"),
            args["fileKey"].encode("utf-8"),
            args["fileNonce"].encode("utf-8"),
            dst.encode("utf-8"),
        )
        return _read_and_free(ptr)

    res = await asyncio.to_thread(_call)
    if res:
        raise RuntimeError(res)

def _crypto_args_result(raw: str) -> CryptoArgs:
    parsed = json.loads(raw)
    if parsed.get("type") == "result":
        return parsed["cryptoArgs"]
    if parsed.get("type") == "error":
        raise RuntimeError(parsed.get("writeError", "unknown write error"))
    raise RuntimeError(f"unexpected result: {raw[:200]}")
