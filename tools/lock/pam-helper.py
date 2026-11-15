#!/usr/bin/python3
"""One lock authentication in a fresh process (#211); private JSON-lines I/O.

PAM owns the calloc/strdup responses after a successful conversation. No
credentials go into argv, the environment or logs. This is not setuid and
authenticates only the caller, using the same stacks as the former PamContext.
"""

import ctypes as C
import json
import os
import pwd
import signal
import sys


class Message(C.Structure):
    _fields_ = [("style", C.c_int), ("text", C.c_char_p)]


class Response(C.Structure):
    _fields_ = [("text", C.c_void_p), ("code", C.c_int)]


Callback = C.CFUNCTYPE(C.c_int, C.c_int, C.POINTER(C.POINTER(Message)),
                      C.POINTER(C.POINTER(Response)), C.c_void_p)


class Conversation(C.Structure):
    _fields_ = [("callback", Callback), ("data", C.c_void_p)]


def send(event, **fields):
    print(json.dumps({"event": event, **fields}), flush=True)


def authenticate(service, directory):
    libc = C.CDLL(None)
    libc.calloc.argtypes = [C.c_size_t, C.c_size_t]
    libc.calloc.restype = C.c_void_p
    libc.strdup.argtypes = [C.c_char_p]
    libc.strdup.restype = C.c_void_p
    libc.free.argtypes = [C.c_void_p]
    libc.prctl.argtypes = [C.c_int, C.c_ulong, C.c_ulong, C.c_ulong, C.c_ulong]
    # Stop the helper if its lock process dies, including the setup race.
    parent = os.getppid()
    if parent == 1 or libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0 or os.getppid() != parent:
        return 2

    @Callback
    def converse(count, messages, output, _data):
        if not 0 < count <= 32:  # PAM_MAX_NUM_MSG
            return 19  # PAM_CONV_ERR
        allocation = libc.calloc(count, C.sizeof(Response))
        if not allocation:
            return 5  # PAM_BUF_ERR
        responses = C.cast(allocation, C.POINTER(Response))
        try:
            for i in range(count):
                message = messages[i].contents
                if message.style not in (1, 2, 3, 4):
                    raise ValueError("unsupported PAM message")
                send("message", style=message.style,
                     text=(message.text or b"").decode("utf-8", errors="replace"))
                if message.style in (1, 2):
                    line = sys.stdin.buffer.readline(65537)
                    if not line.endswith(b"\n") or len(line) > 65536:
                        raise ValueError("invalid response frame")
                    frame = json.loads(line)
                    response = frame["response"].encode("utf-8")
                    if b"\0" in response or len(response) > 512:  # PAM_MAX_RESP_SIZE
                        raise ValueError("invalid PAM response")
                    responses[i].text = libc.strdup(response)
                    if not responses[i].text:
                        raise MemoryError()
            output[0] = responses
            return 0
        except BaseException:
            # No Python exception may cross the C callback and leave its
            # return value undefined. Every incomplete response is refused.
            for i in range(count):
                libc.free(responses[i].text)
            libc.free(allocation)
            return 19

    pam = C.CDLL("libpam.so.0")
    pam.pam_start_confdir.argtypes = [C.c_char_p, C.c_char_p, C.POINTER(Conversation),
                                     C.c_char_p, C.POINTER(C.c_void_p)]
    pam.pam_authenticate.argtypes = [C.c_void_p, C.c_int]
    pam.pam_end.argtypes = [C.c_void_p, C.c_int]
    conversation = Conversation(converse, None)
    handle = C.c_void_p()
    # Resolve the real uid, never $USER or a username from the client.
    user = pwd.getpwuid(os.getuid()).pw_name.encode()
    result = pam.pam_start_confdir(service.encode(), user, C.byref(conversation),
                                   directory.encode(), C.byref(handle))
    if result != 0:
        return 2
    try:
        result = pam.pam_authenticate(handle, 0)
    finally:
        pam.pam_end(handle, result)
    # Quickshell PamResult values, preserving the lock's existing decisions.
    return {0: 0, 7: 1, 11: 3}.get(result, 2)


def main():
    result = 2
    try:
        if len(sys.argv) == 3:
            result = authenticate(sys.argv[1], sys.argv[2])
    except Exception:
        pass
    send("result", result=result)


if __name__ == "__main__":
    main()
