export function zero_core_runtime_migrate_init(dbPath: string, dbKey: string, confirm: string): Promise<[bigint, string]>

export function zero_core_runtime_close_store(ctrl: bigint): Promise<string>

export function zero_core_runtime_send_cmd(ctrl: bigint, cmd: string): Promise<string>
export function zero_core_runtime_recv_msg_wait(ctrl: bigint, wait: number): Promise<string>

export function zero_core_runtime_write_file(ctrl: bigint, path: string, buffer: ArrayBuffer): Promise<string>

export function zero_core_runtime_read_file(path: string, key: string, nonce: string): Promise<ArrayBuffer>
export function zero_core_runtime_encrypt_file(ctrl: bigint, fromPath: string, toPath: string): Promise<string>

export function zero_core_runtime_decrypt_file(fromPath: string, key: string, nonce: string, toPath: string): Promise<string>
