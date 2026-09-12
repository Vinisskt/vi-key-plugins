/*
 * vk-ipcd — ponte vi-key <-> Termux, em C.
 * Mesmo protocolo de arquivos em keyboard-lua/data:
 *   cmd  (escrito pelo teclado)  ->  tomado via rename() para busy (atômico)
 *   last-start  epoch do início do comando
 *   out  stdout+stderr do comando (o worker redireciona)
 *   heartbeat   epoch, GRAVADO NO LOOP TODO 0.1s (inclusive durante comando)
 *   busy  some quando o comando termina (sinal de "concluído" pro teclado)
 *   stop  presente -> sai limpo (apaga e termina)
 *
 * O comando NÃO nasce num bash novo por chamada: o daemon mantém um bash
 * persistente (o "worker") que lê de um FIFO o caminho do arquivo [busy],
 * faz eval do conteúdo (multi-linha ok) jogando a saída em data/out e então
 * remove o [busy]. O FIFO vive em /data/data/com.termux/files/usr/var/vk-ipc
 * (o /sdcard é FUSE e não suporta FIFO); a interface com o teclado segue
 * 100% por arquivos no /sdcard. O daemon nunca bloqueia executando comando:
 * o grosso do trabalho acontece no worker, então o heartbeat não para e o
 * runit pode reiniciar o daemon se ele crashar.
 */
#include <signal.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* Interface com o teclado (FUSE /sdcard, só arquivos — sem FIFO). */
#define DATA "/sdcard/keyboard-lua/data"
#define CMD  "/sdcard/keyboard-lua/data/cmd"
#define BUSY "/sdcard/keyboard-lua/data/busy"
#define OUT  "/sdcard/keyboard-lua/data/out"
#define HB   "/sdcard/keyboard-lua/data/heartbeat"
#define LAST "/sdcard/keyboard-lua/data/last-start"
#define STOP "/sdcard/keyboard-lua/data/stop"

/* Interno (ext4 do Termux: suporta FIFO). */
#define VAR  "/data/data/com.termux/files/usr/var/vk-ipc"
#define FIFO VAR "/fifo"
#define LOOP VAR "/worker-loop.sh"
#define PIDF VAR "/worker.pid"
#define TOKEN "vk-ipc-worker"

#define BASH "/data/data/com.termux/files/usr/bin/bash"

#define POLL_NS 100000000L /* 0.1s — latência baixa no teclado */

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

/* ---- Worker persistente (bash nasce UMA vez, não por comando) ---- */
static pid_t worker_pid = 0;

static void spawn_worker(void) {
  /* Mata qualquer worker anterior (mesmo token) e limpa o FIFO. */
  if (worker_pid > 0) {
    kill(worker_pid, SIGTERM);
    waitpid(worker_pid, NULL, 0);
    worker_pid = 0;
  }
  mkdir(VAR, 0777);
  unlink(FIFO);

  /* O loop vive num ARQUIVO: evita aspas aninhadas de shell -c. Reabre o FIFO
   * a cada comando (read em FIFO dá EOF quando o writer fecha, o que mataria
   * o worker no primeiro comando). */
  FILE *s = fopen(LOOP, "w");
  if (s) {
    fprintf(s,
      "while true; do exec 3< '%s' 2>/dev/null || break; "
      "while read -r b <&3; do cd \"$HOME\" 2>/dev/null || cd /; "
      "eval \"$(cat $b)\" > '%s/out' 2>&1; rm -f $b; done; done\n",
      FIFO, DATA);
    fclose(s);
  }

  if (mkfifo(FIFO, 0666) != 0) { /* correção de corrida: alguém criou antes */
    unlink(FIFO);
    if (mkfifo(FIFO, 0666) != 0) return;
  }

  pid_t pid = fork();
  if (pid < 0) { worker_pid = 0; return; }
  if (pid == 0) {
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
      dup2(devnull, 0);
      dup2(devnull, 1);
      dup2(devnull, 2);
      close(devnull);
    }
    /* argv começa com o token: pkill -f o encontra. */
    execl(BASH, BASH, "--noprofile", "--norc", LOOP, TOKEN, (char *)NULL);
    _exit(127);
  }
  worker_pid = pid;
  FILE *pf = fopen(PIDF, "w");
  if (pf) {
    fprintf(pf, "%d\n", (int)pid);
    fclose(pf);
  }
}

static int worker_alive(void) {
  return worker_pid > 0 && kill(worker_pid, 0) == 0;
}

/* Entrega o caminho do [busy] ao worker (open O_WRONLY no FIFO só completa
 * quando o worker reabre o leitor — o handshake é o sentido da fila). */
static void worker_push(void) {
  if (!worker_alive()) spawn_worker();
  int fd = open(FIFO, O_WRONLY);
  if (fd < 0) return;
  ssize_t n = strlen(busy_path);
  if (write(fd, busy_path, (size_t)n) != n) { close(fd); return; }
  if (write(fd, "\n", 1) != 1) { close(fd); return; }
  close(fd);
}

static void worker_stop(void) {
  if (worker_pid > 0) {
    kill(worker_pid, SIGTERM);
    waitpid(worker_pid, NULL, 0);
    worker_pid = 0;
  }
  unlink(FIFO);
}

int main(void) {
  struct sigaction sa;
  struct timespec ts = {0, POLL_NS};
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = SIG_IGN;
  sigaction(SIGPIPE, &sa, NULL);

  mkdir(DATA, 0777);
  snprintf(busy_path, sizeof busy_path, "%s", BUSY);
  spawn_worker();

  for (;;) {
    write_text(HB, epoch_text());

    /* Reap: worker morto vira zombie e kill(pid,0) ainda diria "vivo". */
    if (worker_pid > 0) {
      pid_t r = waitpid(worker_pid, NULL, WNOHANG);
      if (r == worker_pid || (r < 0 && errno == ECHILD)) worker_pid = 0;
    }

    if (file_exists(STOP)) {
      remove(STOP);
      if (file_exists(BUSY)) remove(BUSY);
      worker_stop();
      break;
    }

    /* Recuperação: worker morreu com [busy] preso -> destrava o teclado. */
    if (file_exists(BUSY) && !worker_alive()) {
      remove(BUSY);
      spawn_worker();
    }

    if (!file_exists(BUSY) && file_exists(CMD)) {
      if (rename(CMD, BUSY) == 0) {
        write_text(OUT, "");
        write_text(LAST, epoch_text());
        worker_push();
      }
    }

    nanosleep(&ts, NULL);
  }
  return 0;
}