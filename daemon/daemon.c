/*
 * vk-ipcd — ponte vi-key <-> Termux, em C.
 * Substitui o daemon Lua (plugins/ipc-loop.lua --daemon) com o MESMO protocolo
 * de arquivos em keyboard-lua/data, sem depender de intérprete:
 *   cmd  (escrito pelo teclado)  ->  tomado via rename() para busy (atômico)
 *   last-start  epoch do início do comando
 *   out  stdout+stderr do comando (redirect no filho)
 *   heartbeat   epoch, GRAVADO NO LOOP TODO 0.3s (inclusive durante comando)
 *   busy  some quando o comando termina (sinal de "concluído" pro teclado)
 *   stop  presente -> sai limpo (apaga e termina)
 *
 * Diferença de estabilidade vs Lua: o comando roda num processo FILHO, então o
 * loop nunca para de bater heartbeat — o teclado não lê mais "daemon morto"
 * por engano durante comandos longos. E C não trava nesses vácuos: se o loop
 * morrer (crash), o runit o reinicia.
 */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define DATA "/sdcard/keyboard-lua/data"
#define CMD  "/sdcard/keyboard-lua/data/cmd"
#define BUSY "/sdcard/keyboard-lua/data/busy"
#define OUT  "/sdcard/keyboard-lua/data/out"
#define HB   "/sdcard/keyboard-lua/data/heartbeat"
#define LAST "/sdcard/keyboard-lua/data/last-start"
#define STOP "/sdcard/keyboard-lua/data/stop"
#define BASH "/data/data/com.termux/files/usr/bin/bash"

#define POLL_NS 300000000L /* 0.3s, igual ao daemon lua */

static int run_child = 0;          /* pid do comando em execução, 0 = livre   */
static char busy_path[1 + sizeof BUSY];

static int file_exists(const char *p) {
  struct stat st;
  return stat(p, &st) == 0;
}

static int write_text(const char *p, const char *s) {
  FILE *f = fopen(p, "w");
  if (!f) return 0;
  fputs(s, f);
  fclose(f);
  return 1;
}

static char *epoch_text(void) {
  static char buf[32];
  snprintf(buf, sizeof buf, "%ld", (long)time(NULL));
  return buf;
}

/* Inicia o comando do arquivo busy num processo filho; o loop continua. */
static void start_command(void) {
  pid_t pid = fork();
  if (pid < 0) { /* sem fork? remove busy e segue a vida */
    remove(BUSY);
    run_child = 0;
    return;
  }
  if (pid > 0) { /* pai */
    run_child = pid;
    return;
  }
  /* filho */
  FILE *out = fopen(OUT, "w");
  if (out != NULL) {
    int fd = fileno(out);
    if (fd >= 0) {
      dup2(fd, 1);
      dup2(fd, 2);
    }
    fclose(out);
  }
  execl(BASH, BASH, busy_path, (char *)NULL);
  _exit(127);
}

int main(void) {
  struct sigaction sa;
  struct timespec ts = {0, POLL_NS};
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = SIG_IGN;
  sigaction(SIGPIPE, &sa, NULL);

  /* mkdir -p DATA (o teclado também pode já tê-la criado) */
  mkdir(DATA, 0777);
  snprintf(busy_path, sizeof busy_path, "%s", BUSY);

  for (;;) {
    write_text(HB, epoch_text());
    if (file_exists(STOP)) {
      remove(STOP);
      /* mate o comando ativo? já era; saia. */
      if (run_child) { kill(run_child, SIGTERM); waitpid(run_child, NULL, 0); }
      remove(BUSY);
      break;
    }
    if (run_child) {
      int status;
      pid_t r = waitpid(run_child, &status, WNOHANG);
      if (r == run_child || r < 0) {
        run_child = 0;
        remove(BUSY);
      }
    } else if (file_exists(CMD) && !file_exists(BUSY)) {
      if (rename(CMD, BUSY) == 0) {
        write_text(OUT, "");
        write_text(LAST, epoch_text());
        start_command();
      }
    }
    nanosleep(&ts, NULL);
  }
  return 0;
}