/*
 * Main executable of Tolkeins Collector.app.
 *
 * launchd starts this Mach-O. macOS attributes Files & Folders (Chrome
 * cookies) to the responsible process, which for a LaunchAgent is the
 * program launchd execs. That has to be this signed app, not /usr/bin/python3
 * and not CodexBar.app: those grants do not cover a python3 LaunchAgent.
 *
 * This process stays alive and posix_spawns python. Replacing the process
 * image would make python3 the signed identity. On macOS the helper first
 * re-spawns itself with responsibility_spawnattrs_setdisclaim so a run from
 * Terminal is attributed to this app as well, then that copy spawns python.
 * Python's CodexBar child inherits the same responsible process.
 */

#define _GNU_SOURCE

#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

extern char **environ;

static volatile sig_atomic_t child_pid = 0;

static void stop_child(void) {
    int pid = (int)child_pid;
    if (pid > 0)
        kill((pid_t)pid, SIGTERM);
}

static void on_signal(int sig) {
    int pid = (int)child_pid;
    if (pid > 0)
        kill((pid_t)pid, sig);
}

static int self_path(char *buffer, size_t size) {
#ifdef __APPLE__
    uint32_t length = (uint32_t)size;
    if (_NSGetExecutablePath(buffer, &length) != 0)
        return -1;
    char resolved[8192];
    if (realpath(buffer, resolved) == NULL)
        return -1;
    if (strlen(resolved) + 1 > size)
        return -1;
    memcpy(buffer, resolved, strlen(resolved) + 1);
    return 0;
#else
    ssize_t length = readlink("/proc/self/exe", buffer, size - 1);
    if (length < 0)
        return -1;
    buffer[length] = '\0';
    return 0;
#endif
}

static void set_default_env(const char *name, const char *suffix) {
    const char *current = getenv(name);
    if (current != NULL && current[0] != '\0')
        return;
    const char *home = getenv("HOME");
    if (home == NULL || home[0] == '\0')
        return;
    char value[8192];
    int wrote = snprintf(value, sizeof value, "%s%s", home, suffix);
    if (wrote < 0 || (size_t)wrote >= sizeof value)
        return;
    if (setenv(name, value, 0) != 0)
        fprintf(stderr, "tolkeins-collector: could not set %s\n", name);
}

typedef int (*disclaim_fn)(posix_spawnattr_t *, uint32_t);

static disclaim_fn load_disclaim(void) {
    void *library = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY);
    if (library == NULL)
        library = dlopen("libSystem.B.dylib", RTLD_LAZY);
    if (library == NULL)
        return NULL;
    return (disclaim_fn)dlsym(library, "responsibility_spawnattrs_setdisclaim");
}

static int disclaim_available(void) {
    return load_disclaim() != NULL;
}

static int should_bootstrap(void) {
    const char *already = getenv("TOLKEINS_RESPONSIBLE");
    if (already != NULL && strcmp(already, "1") == 0)
        return 0;
    const char *test = getenv("TOLKEINS_TEST_DISCLAIM");
    if (test != NULL && strcmp(test, "0") == 0)
        return 0;
    if (test != NULL && strcmp(test, "1") == 0)
        return 1;
#ifdef __APPLE__
    return 1;
#else
    return 0;
#endif
}

static char **env_with_responsible(void) {
    int count = 0;
    while (environ[count] != NULL)
        count++;
    char **copy = calloc((size_t)count + 2, sizeof(char *));
    if (copy == NULL)
        return NULL;
    int used = 0;
    for (int index = 0; index < count; index++) {
        if (strncmp(environ[index], "TOLKEINS_RESPONSIBLE=", 21) == 0)
            continue;
        copy[used++] = environ[index];
    }
    copy[used++] = "TOLKEINS_RESPONSIBLE=1";
    copy[used] = NULL;
    return copy;
}

static int spawn_process(
    const char *path,
    char *const argv[],
    char *const envp[],
    int disclaim,
    pid_t *pid_out
) {
    posix_spawnattr_t attrs;
    int rc = posix_spawnattr_init(&attrs);
    if (rc != 0)
        return rc;
    if (disclaim) {
        disclaim_fn disclaim_spawn = load_disclaim();
        if (disclaim_spawn == NULL) {
            posix_spawnattr_destroy(&attrs);
            return ENOTSUP;
        }
        rc = disclaim_spawn(&attrs, 1);
        if (rc != 0) {
            posix_spawnattr_destroy(&attrs);
            return rc;
        }
    }
    rc = posix_spawn(pid_out, path, NULL, &attrs, argv, envp);
    posix_spawnattr_destroy(&attrs);
    return rc;
}

static int wait_for(pid_t pid) {
    child_pid = (sig_atomic_t)pid;
    for (;;) {
        int status = 0;
        pid_t got = waitpid(pid, &status, 0);
        if (got < 0) {
            if (errno == EINTR)
                continue;
            child_pid = 0;
            fprintf(stderr, "tolkeins-collector: waitpid failed: %s\n", strerror(errno));
            return 1;
        }
        child_pid = 0;
        if (WIFEXITED(status))
            return WEXITSTATUS(status);
        if (WIFSIGNALED(status))
            return 128 + WTERMSIG(status);
        return 1;
    }
}

static int run_python(int argc, char **argv);

static int bootstrap(int argc, char **argv) {
    char self[8192];
    if (self_path(self, sizeof self) != 0) {
        fprintf(stderr, "tolkeins-collector: cannot resolve the helper path\n");
        return 1;
    }
    char **child_argv = calloc((size_t)argc + 1, sizeof(char *));
    char **child_env = env_with_responsible();
    if (child_argv == NULL || child_env == NULL) {
        free(child_argv);
        free(child_env);
        fprintf(stderr, "tolkeins-collector: out of memory\n");
        return 1;
    }
    child_argv[0] = self;
    for (int index = 1; index < argc; index++)
        child_argv[index] = argv[index];
    child_argv[argc] = NULL;

    int use_disclaim = disclaim_available();
#ifdef __APPLE__
    if (!use_disclaim) {
        fprintf(
            stderr,
            "tolkeins-collector: responsibility_spawnattrs_setdisclaim is unavailable; "
            "a Terminal run is attributed to Terminal. A LaunchAgent run still uses this app.\n"
        );
    }
#endif
    pid_t pid = 0;
    int rc = spawn_process(self, child_argv, child_env, use_disclaim, &pid);
    free(child_argv);
    free(child_env);
    if (rc != 0) {
        /* Launchd already started this signed image. If the disclaim re-spawn
         * fails, keep collecting here so a signature quirk cannot stop the run. */
        fprintf(
            stderr,
            "tolkeins-collector: responsible re-spawn failed (%s); continuing in this process\n",
            strerror(rc)
        );
        return run_python(argc, argv);
    }
    return wait_for(pid);
}

static int run_python(int argc, char **argv) {
    const char *python = getenv("TOLKEINS_PYTHON");
    if (python == NULL || python[0] == '\0')
        python = "/usr/bin/python3";
    if (python[0] != '/') {
        fprintf(stderr, "tolkeins-collector: TOLKEINS_PYTHON must be an absolute path\n");
        return 127;
    }
    if (access(python, X_OK) != 0) {
        fprintf(stderr, "tolkeins-collector: cannot execute %s: %s\n", python, strerror(errno));
        return 127;
    }

    char **child_argv = calloc((size_t)argc + 3, sizeof(char *));
    if (child_argv == NULL) {
        fprintf(stderr, "tolkeins-collector: out of memory\n");
        return 1;
    }
    child_argv[0] = (char *)python;
    child_argv[1] = "-m";
    child_argv[2] = "tolkeins";
    for (int index = 1; index < argc; index++)
        child_argv[index + 2] = argv[index];
    child_argv[argc + 2] = NULL;

    pid_t pid = 0;
    int rc = spawn_process(python, child_argv, environ, 0, &pid);
    free(child_argv);
    if (rc != 0) {
        fprintf(stderr, "tolkeins-collector: could not start %s: %s\n", python, strerror(rc));
        return 127;
    }
    return wait_for(pid);
}

int main(int argc, char **argv) {
    atexit(stop_child);
    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    set_default_env("PYTHONPATH", "/.local/share/tolkeins");
    set_default_env("TOLKEINS_CONFIG_DIR", "/.config/tolkeins");
    if (should_bootstrap())
        return bootstrap(argc, argv);
    return run_python(argc, argv);
}
