#!/usr/bin/env python3
# compara_dicionario.py — compara dicionários pt-BR baixados contra o índice
# embutido do :dict (plugins/dicionario_dados.lua) e lista as palavras que
# deveriam existir mas faltam no índice.
#
# Uso:
#   python3 scripts/compara_dicionario.py <lua_dir> <dict1> <dict2> ... [-o DIR]
#
# Formatos aceitos (detecção automática por heurística simples):
#   * hunspell/aspell:  uma palavra por linha, flags após '/' (libreoffice_pt_BR.dic)
#   * coGrOO/jspell:    linhas '#...' são metadados; palavra antes do primeiro '/'
#   * texto puro:       uma palavra por linha (wordfreq, tito, ...)
#
# Cada palavra é normalizada do mesmo jeito que o plugin faz (sem_acento):
# minúsculas + remoção de acentos (NFD) + só letras a-z. Palavra "presente"
# = a forma normalizada consta entre as chaves (ou canônicos) do índice.
#
# Saída: resumo no stdout + três arquivos por diretório de saída:
#   faltando_<fonte>.txt   faltas de cada dicionário
#   faltando_uniq.txt      união de todas as faltas (ordenado por prioridade)
#   faltando_confiavel.txt faltas presentes em >=2 fontes
# Se uma fonte for do wordfreq (ordem = frequência) ela vira a prioridade.

import argparse
import os
import re
import sys
import unicodedata
from collections import OrderedDict

NORM_RE = re.compile(r"[^a-z]")


def norm(w):
    """Mesma normalização do plugin: minúsculas + sem acentos + só a-z."""
    w = w.lower()
    w = unicodedata.normalize("NFD", w)
    w = "".join(c for c in w if not unicodedata.combining(c))
    return NORM_RE.sub("", w)


def carregar_indice_lua(path):
    """Lê plugins/dicionario_dados.lua e devolve o set de palavras conhecidas
    (chaves + canônicos, normalizados)."""
    with open(path, encoding="utf-8", errors="replace") as f:
        s = f.read()
    a = s.index("return [===[") + len("return [===[")
    b = s.index("]===]", a)
    conhecidas = set()
    linhas = 0
    for l in s[a:b].split("\n"):
        if not l.strip():
            continue
        linhas += 1
        campos = l.split("\t")
        conhecidas.add(norm(campos[0]))
        if len(campos) > 1:
            conhecidas.add(norm(campos[1]))
    return conhecidas, linhas


TOK_RE = re.compile(r"^[A-Za-zÀ-ÿçÇ''\-]+$")


def token_limpo(t):
    """Só tokens de palavras (letras, hífen, apóstrofo) — sem '.', dígitos."""
    if not t or not TOK_RE.match(t):
        return None
    return t


def token_hunspell(linha):
    """'palavra/FLAGS' -> 'palavra'; pula cabeçalho (numérico) e lixo."""
    t = linha.strip().lstrip("\ufeff")
    if not t or t[0].isdigit():
        return None
    return token_limpo(t.split("/", 1)[0])


def token_cogroo(linha):
    t = linha.strip()
    if not t or t.startswith("#"):
        return None
    return token_limpo(t.split("/", 1)[0])


def token_plain(linha):
    return token_limpo(linha.strip())


def ler_dicionario(path):
    """Detecta o formato e devolve (nome_fonte, lista de palavras)."""
    nome = os.path.basename(path)
    with open(path, encoding="utf-8", errors="replace") as f:
        linhas = f.read().splitlines()

    # Heurística de formato:
    # coGrOO jspell quase sempre tem muitas linhas '#' no início.
    n_meta = sum(1 for l in linhas[:50] if l.lstrip().startswith("#"))
    n_flags = sum(1 for l in linhas[:200] if "/" in l and l.split("/", 1)[1])
    if n_meta >= 1:
        f_token = token_cogroo
    elif n_flags >= 1:
        f_token = token_hunspell
    else:
        f_token = token_plain

    palavras = []
    for l in linhas:
        t = f_token(l)
        if t is not None:
            palavras.append(t)
    return nome, palavras


def main():
    ap = argparse.ArgumentParser(description="Compara dicionários pt-BR com o índice do :dict")
    ap.add_argument("lua", help="caminho de plugins/dicionario_dados.lua")
    ap.add_argument("dicionarios", nargs="+", help="arquivos .dic/.txt baixados")
    ap.add_argument("-o", dest="outdir", default=".", help="dir para os relatórios (default: .)")
    ap.add_argument("--min-len", type=int, default=2, help="tamanho mínimo da palavra (default 2)")
    ap.add_argument("--nao-gerar", action="store_true",
                    help="não escrever os arquivos de saída, só o resumo")
    args = ap.parse_args()

    conhecidas, n_linhas = carregar_indice_lua(args.lua)
    os.makedirs(args.outdir, exist_ok=True)

    # (palavra original) -> set(fontes) para a intersecção
    origem = {}  # norm -> set(nome fonte)
    acentuada = {}  # norm -> True se algum spelling tem letra acentuada
    por_fonte = {}  # nome -> lista de norm faltantes (para arquivo)

    for path in args.dicionarios:
        nome, palavras = ler_dicionario(path)
        tot = 0
        faltas = []
        for w in palavras:
            n = norm(w)
            if len(n) < args.min_len:
                continue
            tot += 1
            if n not in conhecidas:
                faltas.append(w)
                origem.setdefault(n, set()).add(nome)
                if any(ord(c) > 127 for c in w):
                    acentuada[n] = True
        por_fonte[nome] = faltas
        pct = 100.0 * len(faltas) / tot if tot else 0
        print("  %-24s total=%-7d presente=%-7d FALTANDO=%-6d (%.1f%%)"
              % (nome, tot, tot - len(faltas), len(faltas), pct))

    uniq = list(origem)
    confiavel = [n for n in uniq if len(origem[n]) >= 2]
    acentuadas = [n for n in uniq if n in acentuada]

    # Ordena por prioridade: primeiro os que aparecem no wordfreq (na ordem de
    # frequência dele), depois os de outras fontes, alfabeticamente.
    # Reconstitui a ordem do wordfreq a partir dos arquivos de entrada.
    wf_order = {}
    for path in args.dicionarios:
        if "wordfreq" in os.path.basename(path):
            for w in ler_dicionario(path)[1]:
                n = norm(w)
                if len(n) >= args.min_len and n not in wf_order:
                    wf_order[n] = len(wf_order)
            break

    def sortkey(n):
        return (0, wf_order[n]) if n in wf_order else (1, n)

    uniq_sorted = sorted(uniq, key=sortkey)
    acentuadas_sorted = sorted(acentuadas, key=sortkey)

    print()
    print("Índice :dict: %d linhas (%d palavras conhecidas, norm.)"
          % (n_linhas, len(conhecidas)))
    print("FALTANDO (união de todas as fontes): %d" % len(uniq))
    print("FALTANDO (em >=2 fontes):            %d" % len(confiavel))
    print("FALTANDO com acento (correção de acento ausente): %d" % len(acentuadas))
    if wf_order:
        print("FALTANDO entre as %d mais frequentes do wordfreq: %d"
              % (len(wf_order),
                 sum(1 for n in uniq if n in wf_order)))
        for top in (1000, 5000, 20000):
            c = sum(1 for n in uniq if n in wf_order and wf_order[n] < top)
            print("  top %-7d: %d faltando" % (top, c))

    if args.nao_gerar:
        return

    def escrever(nome_arq, itens, extra=""):
        with open(os.path.join(args.outdir, nome_arq), "w", encoding="utf-8") as f:
            f.write(extra)
            for i in itens:
                f.write(i + "\n")

    for nome, faltas in por_fonte.items():
        salvar = nome.rsplit(".", 1)[0]
        escrever("faltando_%s.txt" % salvar, faltas)
    escrever("faltando_uniq.txt", uniq_sorted)
    escrever("faltando_confiavel.txt", sorted(confiavel, key=sortkey))
    escrever("faltando_acentuadas.txt", acentuadas_sorted)

    print()
    print("Arquivos gerados em %s:" % args.outdir)
    for nome, faltas in por_fonte.items():
        print("  faltando_%s.txt  (%d)" % (nome.rsplit(".", 1)[0], len(faltas)))
    print("  faltando_uniq.txt       (%d)" % len(uniq_sorted))
    print("  faltando_confiavel.txt  (%d)" % len(confiavel))
    print("  faltando_acentuadas.txt (%d)" % len(acentuadas_sorted))

    print()
    print("Amostra das faltas acentuadas (as que valem adicionar):")
    for n in acentuadas_sorted[:40]:
        fontes = ",".join(sorted(origem[n]))
        print("  %-22s (%s)" % (n, fontes))


if __name__ == "__main__":
    main()