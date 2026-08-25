#ifndef Zero_h
#define Zero_h

extern "C" void hs_init(int argc, char **argv[]);
extern "C" void hs_init_with_rtsopts(int * argc, char **argv[]);

typedef long* chat_ctrl;

extern "C" char *zero_core_runtime_migrate_init(const char *path, const char *key, const char *confirm, chat_ctrl *ctrl);
extern "C" char *zero_core_runtime_close_store(chat_ctrl ctrl);
extern "C" char *zero_core_runtime_reopen_store(chat_ctrl ctrl);
extern "C" char *zero_core_runtime_send_cmd(chat_ctrl ctrl, const char *cmd);
extern "C" char *zero_core_runtime_recv_msg_wait(chat_ctrl ctrl, const int wait);
extern "C" char *zero_core_runtime_parse_markdown(const char *str);
extern "C" char *zero_core_runtime_parse_server(const char *str);
extern "C" char *zero_core_runtime_password_hash(const char *pwd, const char *salt);
extern "C" char *zero_core_runtime_valid_name(const char *name);
extern "C" int zero_core_runtime_json_length(const char *str);
extern "C" char *zero_core_runtime_encrypt_media(chat_ctrl ctrl, const char *key, const char *frame, const int len);
extern "C" char *zero_core_runtime_decrypt_media(const char *key, const char *frame, const int len);

extern "C" char *zero_core_runtime_write_file(chat_ctrl ctrl, const char *path, const char *data, const int len);

extern "C" char *zero_core_runtime_read_file(const char *path, const char *key, const char *nonce);

extern "C" char *zero_core_runtime_encrypt_file(chat_ctrl ctrl, const char *fromPath, const char *toPath);

extern "C" char *zero_core_runtime_decrypt_file(const char *fromPath, const char *key, const char *nonce, const char *toPath);

#endif /* zero_h */