// SPDX-License-Identifier: LicenseRef-Joral-Proprietary
// Copyright (c) 2026 Joral LLC. All rights reserved.
/* privop.c — the console's privilege boundary (CRA Annex I #4).
 *
 * busybox httpd and every console CGI run as www-data. The handful of
 * operations that genuinely need root — appending to the durable audit log,
 * reloading or restarting the service, installing firmware, a factory reset —
 * are each a small root-owned script in PRIVOP_DIR, and this setuid-root
 * dispatcher is the only way the CGI layer reaches them:
 *
 *     /usr/sbin/<product>-privop <verb> [arg ...]     ->  PRIVOP_DIR/<verb> [arg ...]
 *
 * It does deliberately little, and every rule below is there to keep a
 * compromised CGI from turning "run a verb" into "run anything":
 *
 *   - the verb is a bare name ([a-z][a-z0-9-]{0,31}); no slash, no dot, so it
 *     can only ever select a file inside PRIVOP_DIR;
 *   - the verb file must be a regular file owned by root, executable, and not
 *     writable by group or other — a writable verb would be a root shell for
 *     whoever could write it;
 *   - at most PRIVOP_MAX_ARGS arguments of at most PRIVOP_MAX_ARGLEN bytes,
 *     none containing a control character (0x00-0x1f, 0x7f). Bytes >= 0x80
 *     pass: the copilot takes questions in any language. Bodies (a config,
 *     a PEM, a firmware package) travel on stdin, never as a path argument;
 *   - the environment is replaced, not inherited. The verb sees PATH, the
 *     verb name, the caller's uid, and REMOTE_ADDR if it looks like an
 *     address — so an audit record the verb writes can name the same peer
 *     the CGI saw — and nothing else. No LD_*, no SWU_PREFIX, no IFS;
 *   - every descriptor above 2 is closed EXCEPT fd 9, which api-update.sh
 *     holds as the update-operation flock and hands to the detached install
 *     worker through this boundary (see op_lock() there). Keeping exactly that
 *     one descriptor is the whole reason the worker needs no lock of its own;
 *   - the caller's real uid must be root or www-data. Nothing else on the
 *     image has a login, so this costs nothing and makes the contract explicit;
 *   - the verb runs with real AND effective uid 0 (so `id -u` in a script is
 *     0 and nothing downgrades itself), umask 022, and the invocation is
 *     syslogged at LOG_DAEMON so the boundary's use is visible.
 *
 * Built for the target by the product Makefile and installed 4755 root:root.
 * Built for the HOST by tests/test_privop.sh with -DPRIVOP_TEST, which only
 * relaxes the "owned by root" check to "owned by the invoking user" so the
 * contract can be exercised without a setuid binary; nothing else differs.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <grp.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifndef PRIVOP_DIR
#error "PRIVOP_DIR must be defined (the root-owned verb directory)"
#endif
#ifndef PRIVOP_NAME
#define PRIVOP_NAME "privop"
#endif
#define PRIVOP_CALLER   "www-data"
#define PRIVOP_MAX_ARGS 8
#define PRIVOP_MAX_ARGLEN 8192
#define PRIVOP_LOCK_FD  9

static void refuse(const char *why, const char *what)
{
    if (what && *what)
        syslog(LOG_DAEMON | LOG_WARNING, "privop: refused (%s): %.64s", why, what);
    else
        syslog(LOG_DAEMON | LOG_WARNING, "privop: refused (%s)", why);
    fprintf(stderr, PRIVOP_NAME ": %s\n", why);
}

static int verb_name_ok(const char *v)
{
    size_t n = strlen(v);
    if (n == 0 || n > 32) return 0;
    if (!(v[0] >= 'a' && v[0] <= 'z')) return 0;
    for (size_t i = 1; i < n; i++) {
        char c = v[i];
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'))
            return 0;
    }
    return 1;
}

static int arg_ok(const char *a)
{
    size_t n = strlen(a);
    if (n > PRIVOP_MAX_ARGLEN) return 0;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)a[i];
        if (c < 0x20 || c == 0x7f) return 0;
    }
    return 1;
}

/* REMOTE_ADDR is passed through so the verb's audit records carry the peer
 * the CGI saw. Validated to an address alphabet (IPv4, IPv6, the bracketed
 * and ::ffff: forms busybox httpd emits) so it cannot smuggle anything else. */
static int addr_ok(const char *a)
{
    size_t n = strlen(a);
    if (n == 0 || n > 64) return 0;
    for (size_t i = 0; i < n; i++) {
        char c = a[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F') || c == '.' || c == ':' ||
              c == '[' || c == ']' || c == '%'))
            return 0;
    }
    return 1;
}

/* The verb file must be one root put there. In the test build the binary is
 * not setuid and the verbs are created by the test user, so "owned by root"
 * becomes "owned by me" — the structural checks are identical. */
static int verb_file_ok(const char *path)
{
    struct stat st;
    if (lstat(path, &st) != 0) return 0;
    if (!S_ISREG(st.st_mode)) return 0;
#ifdef PRIVOP_TEST
    if (st.st_uid != getuid()) return 0;
#else
    if (st.st_uid != 0) return 0;
#endif
    if (st.st_mode & (S_IWGRP | S_IWOTH)) return 0;
    if (!(st.st_mode & S_IXUSR)) return 0;
    return 1;
}

static void close_inherited_fds(void)
{
    long max = sysconf(_SC_OPEN_MAX);
    if (max < 0 || max > 65536) max = 65536;
    for (int fd = 3; fd < max; fd++) {
        if (fd == PRIVOP_LOCK_FD) continue;
        close(fd);
    }
}

int main(int argc, char **argv)
{
    openlog(PRIVOP_NAME, LOG_PID, LOG_DAEMON);

    if (argc < 2 || argc - 2 > PRIVOP_MAX_ARGS) {
        refuse(argc < 2 ? "no verb" : "too many arguments", NULL);
        return 2;
    }
    const char *verb = argv[1];
    if (!verb_name_ok(verb)) { refuse("bad verb name", verb); return 2; }
    for (int i = 2; i < argc; i++)
        if (!arg_ok(argv[i])) { refuse("bad argument", verb); return 2; }

    /* Who is asking. Real uid, not effective: this is a setuid binary. */
    uid_t ruid = getuid();
    if (ruid != 0) {
        struct passwd *pw = getpwnam(PRIVOP_CALLER);
#ifdef PRIVOP_TEST
        if (ruid != getuid() && (!pw || pw->pw_uid != ruid)) {
#else
        if (!pw || pw->pw_uid != ruid) {
#endif
            refuse("caller is not " PRIVOP_CALLER, verb);
            return 77;
        }
    }

    char path[sizeof(PRIVOP_DIR) + 1 + 32 + 1];
    snprintf(path, sizeof(path), "%s/%s", PRIVOP_DIR, verb);
    if (!verb_file_ok(path)) { refuse("unknown verb", verb); return 127; }

    /* Become root for real — both ids — so the verb's `id -u` is 0 and a
     * shell cannot decide to drop back to the caller. In the test build the
     * binary is not setuid and these simply keep the test user. */
#ifndef PRIVOP_TEST
    if (setgroups(0, NULL) != 0 || setgid(0) != 0 || setuid(0) != 0) {
        refuse("cannot become root (not installed setuid?)", verb);
        return 71;
    }
#endif
    umask(022);

    /* The replacement environment. Nothing the caller set survives. */
    char env_uid[32], env_verb[48], env_addr[80];
    snprintf(env_uid, sizeof(env_uid), "PRIVOP_CALLER_UID=%lu", (unsigned long)ruid);
    snprintf(env_verb, sizeof(env_verb), "PRIVOP_VERB=%s", verb);
    const char *envp[6];
    int e = 0;
    envp[e++] = "PATH=/usr/sbin:/usr/bin:/sbin:/bin";
    envp[e++] = env_uid;
    envp[e++] = env_verb;
    const char *ra = getenv("REMOTE_ADDR");
    if (ra && addr_ok(ra)) {
        snprintf(env_addr, sizeof(env_addr), "REMOTE_ADDR=%s", ra);
        envp[e++] = env_addr;
    }
    envp[e] = NULL;

    close_inherited_fds();

    syslog(LOG_DAEMON | LOG_INFO, "privop: verb=%s uid=%lu", verb, (unsigned long)ruid);
    closelog();

    /* argv[0] becomes the verb path; the arguments pass through unchanged. */
    char *vargv[PRIVOP_MAX_ARGS + 2];
    int k = 0;
    vargv[k++] = path;
    for (int i = 2; i < argc; i++) vargv[k++] = argv[i];
    vargv[k] = NULL;
    execve(path, vargv, (char *const *)envp);
    fprintf(stderr, PRIVOP_NAME ": exec %s: %s\n", path, strerror(errno));
    return 126;
}
