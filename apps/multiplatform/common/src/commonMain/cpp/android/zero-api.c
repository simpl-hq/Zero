#include <jni.h>
#include <string.h>
#include <stdint.h>

void hs_init_with_rtsopts(int * argc, char **argv[]);

void setLineBuffering(void);
int pipe_std_to_socket(const char * name);

extern void __svfscanf(void){};
extern void __vfwscanf(void){};
extern void __memset_chk_fail(void){};
extern void __strcpy_chk_generic(void){};
extern void __strcat_chk_generic(void){};
extern void __libc_globals(void){};
extern void __rel_iplt_start(void){};

extern void reallocarray(void){};

JNIEXPORT jint JNICALL
Java_app_zero_core_common_platform_CoreKt_pipeStdOutToSocket(JNIEnv *env, __unused jclass clazz, jstring socket_name) {
    const char *name = (*env)->GetStringUTFChars(env, socket_name, JNI_FALSE);
    int ret = pipe_std_to_socket(name);
    (*env)->ReleaseStringUTFChars(env, socket_name, name);
    return ret;
}

JNIEXPORT void JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1init(__unused JNIEnv *env, __unused jclass clazz) {
    int argc = 5;
    char *argv[] = {
        "zero",
        "+RTS",
        "-A64m",
        "-H64m",
        "-xn",
        NULL
    };
    char **pargv = argv;
    hs_init_with_rtsopts(&argc, &pargv);
    setLineBuffering();
}

typedef long* chat_ctrl;

extern char *zero_core_runtime_migrate_init(const char *path, const char *key, const char *confirm, chat_ctrl *ctrl);
extern char *zero_core_runtime_close_store(chat_ctrl ctrl);
extern char *zero_core_runtime_send_cmd_retry(chat_ctrl ctrl, const char *cmd, const int retryNum);
extern char *zero_core_runtime_send_remote_cmd_retry(chat_ctrl ctrl, const int rhId, const char *cmd, const int retryNum);
extern char *zero_core_runtime_recv_msg(chat_ctrl ctrl);
extern char *zero_core_runtime_recv_msg_wait(chat_ctrl ctrl, const int wait);
extern char *zero_core_runtime_parse_markdown(const char *str);
extern char *zero_core_runtime_parse_server(const char *str);
extern char *zero_core_runtime_parse_uri(const char *str, const int safe);
extern char *zero_core_runtime_password_hash(const char *pwd, const char *salt);
extern char *zero_core_runtime_valid_name(const char *name);
extern int zero_core_runtime_json_length(const char *str);
extern char *zero_core_runtime_write_file(chat_ctrl ctrl, const char *path, char *ptr, int length);
extern char *zero_core_runtime_read_file(const char *path, const char *key, const char *nonce);
extern char *zero_core_runtime_encrypt_file(chat_ctrl ctrl, const char *from_path, const char *to_path);
extern char *zero_core_runtime_decrypt_file(const char *from_path, const char *key, const char *nonce, const char *to_path);

JNIEXPORT jobjectArray JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1migrate_1init(JNIEnv *env, __unused jclass clazz, jstring dbPath, jstring dbKey, jstring confirm) {
    const char *_dbPath = (*env)->GetStringUTFChars(env, dbPath, JNI_FALSE);
    const char *_dbKey = (*env)->GetStringUTFChars(env, dbKey, JNI_FALSE);
    const char *_confirm = (*env)->GetStringUTFChars(env, confirm, JNI_FALSE);
    jlong _ctrl = (jlong) 0;
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_migrate_init(_dbPath, _dbKey, _confirm, (chat_ctrl *)&_ctrl));
    (*env)->ReleaseStringUTFChars(env, dbPath, _dbPath);
    (*env)->ReleaseStringUTFChars(env, dbKey, _dbKey);
    (*env)->ReleaseStringUTFChars(env, confirm, _confirm);

    jobjectArray ret = (jobjectArray)(*env)->NewObjectArray(env, 2, (*env)->FindClass(env, "java/lang/Object"), NULL);
    (*env)->SetObjectArrayElement(env, ret, 0, res);
    (*env)->SetObjectArrayElement(env, ret, 1,
        (*env)->NewObject(env, (*env)->FindClass(env, "java/lang/Long"),
        (*env)->GetMethodID(env, (*env)->FindClass(env, "java/lang/Long"), "<init>", "(J)V"),
        _ctrl));
    return ret;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1close_1store(JNIEnv *env, __unused jclass clazz, jlong controller) {
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_close_store((void*)controller));
    return res;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1send_1cmd_1retry(JNIEnv *env, __unused jclass clazz, jlong controller, jstring msg, jint retryNum) {
    const char *_msg = (*env)->GetStringUTFChars(env, msg, JNI_FALSE);
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_send_cmd_retry((void*)controller, _msg, retryNum));
    (*env)->ReleaseStringUTFChars(env, msg, _msg);
    return res;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1send_1remote_1cmd_1retry(JNIEnv *env, __unused jclass clazz, jlong controller, jint rhId, jstring msg, jint retryNum) {
    const char *_msg = (*env)->GetStringUTFChars(env, msg, JNI_FALSE);
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_send_remote_cmd_retry((void*)controller, rhId, _msg, retryNum));
    (*env)->ReleaseStringUTFChars(env, msg, _msg);
    return res;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1recv_1msg(JNIEnv *env, __unused jclass clazz, jlong controller) {
    return (*env)->NewStringUTF(env, zero_core_runtime_recv_msg((void*)controller));
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1recv_1msg_1wait(JNIEnv *env, __unused jclass clazz, jlong controller, jint wait) {
    return (*env)->NewStringUTF(env, zero_core_runtime_recv_msg_wait((void*)controller, wait));
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1parse_1markdown(JNIEnv *env, __unused jclass clazz, jstring str) {
    const char *_str = (*env)->GetStringUTFChars(env, str, JNI_FALSE);
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_parse_markdown(_str));
    (*env)->ReleaseStringUTFChars(env, str, _str);
    return res;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1parse_1server(JNIEnv *env, __unused jclass clazz, jstring str) {
    const char *_str = (*env)->GetStringUTFChars(env, str, JNI_FALSE);
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_parse_server(_str));
    (*env)->ReleaseStringUTFChars(env, str, _str);
    return res;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1parse_1uri(JNIEnv *env, __unused jclass clazz, jstring str, jint safe) {
    const char *_str = (*env)->GetStringUTFChars(env, str, JNI_FALSE);
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_parse_uri(_str, safe));
    (*env)->ReleaseStringUTFChars(env, str, _str);
    return res;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1password_1hash(JNIEnv *env, __unused jclass clazz, jstring pwd, jstring salt) {
    const char *_pwd = (*env)->GetStringUTFChars(env, pwd, JNI_FALSE);
    const char *_salt = (*env)->GetStringUTFChars(env, salt, JNI_FALSE);
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_password_hash(_pwd, _salt));
    (*env)->ReleaseStringUTFChars(env, pwd, _pwd);
    (*env)->ReleaseStringUTFChars(env, salt, _salt);
    return res;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1valid_1name(JNIEnv *env, jclass clazz, jstring name) {
    const char *_name = (*env)->GetStringUTFChars(env, name, JNI_FALSE);
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_valid_name(_name));
    (*env)->ReleaseStringUTFChars(env, name, _name);
    return res;
}

JNIEXPORT int JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1json_1length(JNIEnv *env, jclass clazz, jstring str) {
    const char *_str = (*env)->GetStringUTFChars(env, str, JNI_FALSE);
    int res = zero_core_runtime_json_length(_str);
    (*env)->ReleaseStringUTFChars(env, str, _str);
    return res;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1write_1file(JNIEnv *env, jclass clazz, jlong controller, jstring path, jobject buffer) {
    const char *_path = (*env)->GetStringUTFChars(env, path, JNI_FALSE);
    jbyte *buff = (jbyte *) (*env)->GetDirectBufferAddress(env, buffer);
    jlong capacity = (*env)->GetDirectBufferCapacity(env, buffer);
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_write_file((void*)controller, _path, (char *)buff, (int)capacity));
    (*env)->ReleaseStringUTFChars(env, path, _path);
    return res;
}

JNIEXPORT jobjectArray JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1read_1file(JNIEnv *env, jclass clazz, jstring path, jstring key, jstring nonce) {
    const char *_path = (*env)->GetStringUTFChars(env, path, JNI_FALSE);
    const char *_key = (*env)->GetStringUTFChars(env, key, JNI_FALSE);
    const char *_nonce = (*env)->GetStringUTFChars(env, nonce, JNI_FALSE);

    jbyte *res = (jbyte *)zero_core_runtime_read_file(_path, _key, _nonce);
    (*env)->ReleaseStringUTFChars(env, path, _path);
    (*env)->ReleaseStringUTFChars(env, key, _key);
    (*env)->ReleaseStringUTFChars(env, nonce, _nonce);

    jint status = (jint)res[0];
    jbyteArray arr;
    if (status == 0) {
        union {
            uint32_t w;
            uint8_t b[4];
        } len;
        len.b[0] = (uint8_t)res[1];
        len.b[1] = (uint8_t)res[2];
        len.b[2] = (uint8_t)res[3];
        len.b[3] = (uint8_t)res[4];
        arr = (*env)->NewByteArray(env, len.w);
        (*env)->SetByteArrayRegion(env, arr, 0, len.w, res + 5);
    } else {
        int len = (int)strlen((const char *)(res + 1));
        arr = (*env)->NewByteArray(env, len);
        (*env)->SetByteArrayRegion(env, arr, 0, len, res + 1);
    }

    jobjectArray ret = (jobjectArray)(*env)->NewObjectArray(env, 2, (*env)->FindClass(env, "java/lang/Object"), NULL);
    jobject statusObj = (*env)->NewObject(env, (*env)->FindClass(env, "java/lang/Integer"),
                                           (*env)->GetMethodID(env, (*env)->FindClass(env, "java/lang/Integer"), "<init>", "(I)V"),
                                           status);
    (*env)->SetObjectArrayElement(env, ret, 0, statusObj);
    (*env)->SetObjectArrayElement(env, ret, 1, arr);
    return ret;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1encrypt_1file(JNIEnv *env, jclass clazz, jlong controller, jstring from_path, jstring to_path) {
    const char *_from_path = (*env)->GetStringUTFChars(env, from_path, JNI_FALSE);
    const char *_to_path = (*env)->GetStringUTFChars(env, to_path, JNI_FALSE);
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_encrypt_file((void*)controller, _from_path, _to_path));
    (*env)->ReleaseStringUTFChars(env, from_path, _from_path);
    (*env)->ReleaseStringUTFChars(env, to_path, _to_path);
    return res;
}

JNIEXPORT jstring JNICALL
Java_app_zero_core_common_platform_CoreKt_zero_1core_1runtime_1decrypt_1file(JNIEnv *env, jclass clazz, jstring from_path, jstring key, jstring nonce, jstring to_path) {
    const char *_from_path = (*env)->GetStringUTFChars(env, from_path, JNI_FALSE);
    const char *_key = (*env)->GetStringUTFChars(env, key, JNI_FALSE);
    const char *_nonce = (*env)->GetStringUTFChars(env, nonce, JNI_FALSE);
    const char *_to_path = (*env)->GetStringUTFChars(env, to_path, JNI_FALSE);
    jstring res = (*env)->NewStringUTF(env, zero_core_runtime_decrypt_file(_from_path, _key, _nonce, _to_path));
    (*env)->ReleaseStringUTFChars(env, from_path, _from_path);
    (*env)->ReleaseStringUTFChars(env, key, _key);
    (*env)->ReleaseStringUTFChars(env,  nonce, _nonce);
    (*env)->ReleaseStringUTFChars(env, to_path, _to_path);
    return res;
}
