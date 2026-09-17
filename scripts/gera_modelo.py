#!/usr/bin/env python3
# gera_modelo.py — constrói o mini-modelo de contexto do :dict a partir de um
# corpus de frases PT (formato Leipzig: "ID<TAB>frase").
#
# O que é gerado:
#   * bigramas  c(prev, alvo)   e trigramas c(prev2 prev1, alvo)
#   * chaves e alvos normalizados igual ao plugin (minúsculas, sem acento, a-z)
#   * arquivos embutidos ("return [===[...]===]") prontos pro <teclado>
#
# Uso:
#   python3 scripts/gera_modelo.py <sentences.txt> <saida.lua> [<saida.dat>]
#
# Formato das linhas (uma por contexto, alvos "alvo:cont" por frequência):
#   B<prev>\t<total>\t<alvo:cont>\t...
#   T<prev2 prev1>\t<total>\t<alvo:cont>\t...
# Ordenado por frequência decrescente dentro de cada contexto. O plugin lê e
# monta {B: {ctx: {alvo: p}}, T: {...}} para P(alvo | ctx) = cont/total.

import io
import os
import re
import sys
import unicodedata

NORM_RE = re.compile(r"[^a-z]")


def norm(w):
    w = unicodedata.normalize("NFD", w.lower())
    w = "".join(c for c in w if not unicodedata.combining(c))
    return NORM_RE.sub("", w)


def tokeniza(linha):
    """Frase -> tokens normalizados (len>=1), ignorando números/símbolos."""
    out = []
    for tok in re.findall(r"[A-Za-zÀ-ÿçÇ']+", linha):
        n = norm(tok)
        if n:
            out.append(n)
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit("uso: gera_modelo.py <sentences.txt> <saida.lua> [<saida.dat>]")
    src, saida_lua = sys.argv[1], sys.argv[2]
    saida_dat = sys.argv[3] if len(sys.argv) > 3 else None

    K_BI = 32      # top-K alvos por bigrama
    K_TRI = 10     # top-K alvos por trigrama
    MINC = 3       # ignora contagem < MINC (ruído/corpus pequeno)

    bi, tri = {}, {}   # (ctx,alvo) -> cont
    bi_tot, tri_tot = {}, {}
    frases = n_tok = 0
    with io.open(src, encoding="utf-8", errors="replace") as f:
        for lin in f:
            linha = lin.rstrip("\n")
            _, _, frase = linha.partition("\t")
            if not frase:
                continue
            frases += 1
            toks = tokeniza(frase)
            n_tok += len(toks)
            for i in range(1, len(toks)):
                a, b = toks[i - 1], toks[i]
                ch = (a, b)
                if ch in bi:
                    bi[ch] += 1
                else:
                    bi[ch] = 1
                bi_tot[a] = bi_tot.get(a, 0) + 1
            for i in range(2, len(toks)):
                a, b, c = toks[i - 2], toks[i - 1], toks[i]
                ctx = a + " " + b
                ch = (ctx, c)
                if ch in tri:
                    tri[ch] += 1
                else:
                    tri[ch] = 1
                tri_tot[ctx] = tri_tot.get(ctx, 0) + 1

    # Agrupa por contexto e poda (top-K, MINC)
    def poda(cont, K):
        por_ctx = {}
        for (ctx, alvo), n in cont.items():
            if n < MINC:
                continue
            por_ctx.setdefault(ctx, []).append((n, alvo))
        linhas = []
        for ctx, pares in por_ctx.items():
            pares.sort(reverse=True)
            keep = [p for p in pares[:K]]
            tot = sum(n for n, _ in keep)
            linhas.append((ctx, tot, keep))
        linhas.sort()
        return linhas

    bi_linhas = poda(bi, K_BI)
    tri_linhas = poda(tri, K_TRI)

    def monta(prefixo, linhas):
        chunk = []
        for ctx, tot, keep in linhas:
            pars = "".join("\t%s:%d" % (alvo, n) for n, alvo in keep)
            chunk.append("%s%s\t%d%s" % (prefixo, ctx, tot, pars))
        return chunk

    corpo = monta("B", bi_linhas) + monta("T", tri_linhas)

    texto = "\n".join(corpo) + "\n"
    with io.open(saida_lua, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- dicionario_modelo.lua — mini-modelo de contexto do :dict (GERADO).\n")
        f.write("-- Fonte: corpus Wikipedia pt (Leipzig Corpora, por_wikipedia_2021_300K).\n")
        f.write("-- Formato: B<ctx>\\t<total>\\t<alvo:cont>... (bigrama); T<ctx2> ... (trigrama).\n")
        f.write("-- Regenerate: python3 scripts/gera_modelo.py <sentences.txt> <saida.lua>\n")
        f.write("return [===[\n")
        f.write(texto)
        f.write("]===]\n")
    if saida_dat:
        with io.open(saida_dat, "w", encoding="utf-8", newline="\n") as f:
            f.write(texto)

    print("corpus: %d frases, %d tokens | bigramas: %d ctx | trigramas: %d ctx"
          % (frases, n_tok, len(bi_linhas), len(tri_linhas)))
    print("saída: %s (%d KB)" % (saida_lua, len(texto) // 1024))


if __name__ == "__main__":
    main()