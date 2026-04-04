#ifndef Zero_h
#define Zero_h

#include "hs_init.h"
#include "objc.h"

extern void hs_init(int argc, char **argv[]);

typedef void* chat_ctrl;

extern void zero_core_runtime_init(char *path);

extern char *zero_core_runtime_migrate_init_key(char *path, char *key, int keepKey, char *confirm, int backgroundMode, chat_ctrl *ctrl);
extern char *zero_core_runtime_close_store(chat_ctrl ctl);
extern char *zero_core_runtime_reopen_store(chat_ctrl ctl);
extern char *zero_core_runtime_send_cmd_retry(chat_ctrl ctl, char *cmd, int retryNum);
extern char *zero_core_runtime_recv_msg_wait(chat_ctrl ctl, int wait);
extern char *zero_core_runtime_parse_markdown(char *str);
extern char *zero_core_runtime_parse_server(char *str);
extern char *zero_core_runtime_parse_uri(char *str, int safe);
extern char *zero_core_runtime_password_hash(char *pwd, char *salt);
extern char *zero_core_runtime_valid_name(char *name);
extern int zero_core_runtime_json_length(char *str);
extern char *zero_core_runtime_encrypt_media(chat_ctrl ctl, char *key, char *frame, int len);
extern char *zero_core_runtime_decrypt_media(char *key, char *frame, int len);

extern char *zero_core_runtime_write_file(chat_ctrl ctl, char *path, char *data, int len);

extern char *zero_core_runtime_read_file(char *path, char *key, char *nonce);

extern char *zero_core_runtime_encrypt_file(chat_ctrl ctl, char *fromPath, char *toPath);

extern char *zero_core_runtime_decrypt_file(char *fromPath, char *key, char *nonce, char *toPath);

#endif /* Zero_h */
