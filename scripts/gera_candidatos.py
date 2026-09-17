#!/usr/bin/env python3
# gera_candidatos.py — gera o lote curado de palavras faltantes (acentuadas,
# sem nomes próprios/ruído) para acrescentar ao índice do :dict.
#
# Uso:
#   python3 scripts/gera_candidatos.py \
#     plugins/dicionario_dados.lua \
#     <hermitdave_pt50k.txt> <wordfreq_pt200k.txt> \
#     <libreoffice_pt_BR.dic> <cogroo_ptbr.dic> [-o candidatos.tsv] [-n 200]
#
# Critérios (todos para reduzir falso-positivos):
#   * palavra FALTANTE no índice (mesma normalização do plugin: minúsc, sem acento)
#   * tem acento em alguma grafia (é aqui que o teclado deixa de corrigir hoje)
#   * tem >=3 letras
#   * NÃO parece nome próprio/abreviatura: se alguma fonte (LO/cogroo) grafa com
#     inicial maiúscula, é descartada (Brasília, Goiânia, TSE, STF...)
#   * aparece em >=2 fontes OU está no topo de frequência do wordfreq (<20000)
#
# Saída: TSV "chave<TAB>canonical<TAB>freq_plana<TAB>freq_acentuada",
# ordenado por prioridade (frequência). Aí é só fundir no dicionario_dados.lua
# (ordenando pela chave, padrão da busca binária do plugin).

import argparse
import io
import os
import re
import unicodedata

NORM_RE = re.compile(r"[^a-z]")
CAP_RE = re.compile(r"^[A-ZÀ-Ý][a-zà-ÿç]*$")
TOK_RE = re.compile(r"^[A-Za-zÀ-ÿçÇ''\-]+$")

# Nomes próprios/topônimos que escapam do filtro de maiúscula (as fontes os
# grafam às vezes minúsculas) e não interessam ao lote de vocabulário comum.
EXCLUIR = set("""parana maranhao paraiba piaui maracana ribeirao maceio santarem
catalao petropolis taubate maringa jundiai macae mossoro parnaiba tiete valenca
estadao timao negao verdao lobao gremio marcio brandao avila januario padua
bolivar gastao venancio egidio camoes cordoba setubal alcantara sapucai jaragua
castelao""".split())


def norm(w):
    w = unicodedata.normalize("NFD", w.lower())
    w = "".join(c for c in w if not unicodedata.combining(c))
    return NORM_RE.sub("", w)


def acentuado(w):
    return any(ord(c) > 127 for c in w)


def carregar_indice(path):
    s = io.open(path, encoding="utf-8", errors="replace").read()
    a = s.index("return [===[") + len("return [===[")
    b = s.index("]===]", a)
    conhecidas = set()
    for l in s[a:b].split("\n"):
        if not l.strip():
            continue
        f = l.split("\t")
        conhecidas.add(norm(f[0]))
        if len(f) > 1:
            conhecidas.add(norm(f[1]))
    return conhecidas


def tokens_arquivo(path, meta_prefixo="#"):
    """Palavras por arquivo, com a grafia original."""
    out = []
    with io.open(path, encoding="utf-8", errors="replace") as f:
        for l in f:
            t = l.strip().lstrip("\ufeff")
            if not t or t.startswith(meta_prefixo) or t[0].isdigit():
                continue
            t = t.split("/", 1)[0]
            if t and TOK_RE.match(t):
                out.append(t)
    return out


def contar_freq(path):
    """formas acentuadas e planas -> contagens (hermitdave/no mesmo formato)."""
    contas = {}
    with io.open(path, encoding="utf-8", errors="replace") as f:
        for l in f:
            p = l.split()
            if len(p) >= 2 and p[1].isdigit():
                contas.setdefault(norm(p[0]), []).append((p[0], int(p[1])))
    return contas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("lua")
    ap.add_argument("hermitdave", help="pt_50k.txt original do índice")
    ap.add_argument("wordfreq", help="wordfreq_pt200k.txt")
    ap.add_argument("fontes", nargs="+", help="LO/cogroo .dic (p/ grafia e inicial)")
    ap.add_argument("-o", default="candidatos.tsv", help="TSV de saída")
    ap.add_argument("-n", type=int, default=200, help="tamanho do lote")
    ap.add_argument("--top-wordfreq", type=int, default=20000,
                    help="admitir 1-fonte se rank < este valor")
    args = ap.parse_args()

    conhecidas = carregar_indice(args.lua)
    contas = contar_freq(args.hermitdave)
    palavras_wf = tokens_arquivo(args.wordfreq)
    set_wf = {norm(t) for t in palavras_wf}
    grafia_wf = {}  # norm -> grafia real de uso (1ª no wordfreq = mais frequente)
    for t in palavras_wf:
        grafia_wf.setdefault(norm(t), t)

    grafias = {}  # norm -> set de grafias originais (todas as fontes)
    origens = {}  # norm -> set de fontes (nome do arquivo)
    nome_ou_abrev = set()  # norm com alguma grafia de inicial maiúscula
    for path in args.fontes:
        nome = os.path.basename(path)
        for t in tokens_arquivo(path):
            n = norm(t)
            grafias.setdefault(n, set()).add(t)
            origens.setdefault(n, set()).add(nome)
            if CAP_RE.match(t) or t.isupper():
                nome_ou_abrev.add(n)

    rank = {}
    for i, t in enumerate(palavras_wf):
        n = norm(t)
        if len(n) >= 3 and n not in rank:
            rank[n] = i

    # Curadoria:
    #   A = palavra está no wordfreq (uso real) e a grafia vencedora é ACENTUADA.
    #       -> canônico = essa grafia (é a correção que o usuário espera).
    #   B = palavra não está no wordfreq mas em >=2 fontes, com alguma grafia
    #       acentuada -> canônico = grafia acentuada (prefere minúsculas).
    # Palavras cuja grafia real de uso é a PLANA (baiana, lapa) ficam de fora:
    # corrigi-las contrariaria a regra do plugin ("não corrigir forma comum").
    candidatos = {}  # norm -> canonical
    for n, formas in grafias.items():
        if n in conhecidas or n in nome_ou_abrev or n in EXCLUIR or len(n) < 3:
            continue
        if not any(acentuado(w) for w in formas):
            continue
        wf = grafia_wf.get(n)
        if wf:
            if not acentuado(wf):
                continue
            canon = wf
        else:
            if len(origens[n]) < 2:
                continue
            acc = min((w for w in formas if acentuado(w)),
                      key=lambda w: (w[0].isupper(), w.lower()))
            canon = acc
        candidatos[n] = canon

    lote = sorted(candidatos, key=lambda n: (rank.get(n, 9**9), n))[:args.n]

    # freq real (hermitdave) para os que estiverem lá
    saida = []
    for n in lote:
        canon = candidatos[n]
        pares = contas.get(n, [])
        fa = fp = 0
        for graf, c in pares:
            if acentuado(graf):
                fa = max(fa, c)
            else:
                fp = max(fp, c)
        if fa == 0:
            fa = 1
        saida.append("%s\t%s\t%d\t%d" % (n, canon, fp, fa))

    with io.open(args.o, "w", encoding="utf-8") as f:
        f.write("\n".join(saida) + "\n")

    print("candidatos gerados: %d (de %d faltas com acento) -> %s" % (len(saida), len(candidatos), args.o))
    for l in saida[:30]:
        print("  %s" % l.replace("\t", " | "))


if __name__ == "__main__":
    main()