#!/usr/bin/env python3
# fundir_candidatos.py — funde um TSV "chave\tcanonical\tfreq_plana\tfreq_acu"
# (ex.: saída de gera_candidatos.py) no índice embutido do :dict,
# mantendo a ordem por chave exigida pela busca binária.
#
# Uso: python3 scripts/fundir_candidatos.py plugins/dicionario_dados.lua candidatos.tsv
#
# Idempotente: chaves já presentes (ou inválidas) são puladas; rodar de novo
# depois de curar um lote maior só acrescenta o que ainda faltar.

import io
import sys


def ler_indice(path):
    s = io.open(path, encoding="utf-8", errors="replace").read()
    ini = s.index("return [===[") + len("return [===[")
    fim = s.index("]===]", ini)
    cabecalho = s[:ini]
    linhas = []
    for l in s[ini:fim].split("\n"):
        if not l.strip():
            continue
        campos = l.split("\t")
        if len(campos) == 4:
            linhas.append(tuple(campos))
    return cabecalho, linhas, fim


def main():
    if len(sys.argv) != 3:
        sys.exit("uso: fundir_candidatos.py <dicionario_dados.lua> <candidatos.tsv>")

    lua_path, tsv_path = sys.argv[1], sys.argv[2]
    cabecalho, linhas, _ = ler_indice(lua_path)

    presentes = {c[0] for c in linhas}
    novos = []
    ignorados = 0
    for l in io.open(tsv_path, encoding="utf-8"):
        campos = l.rstrip("\n").split("\t")
        if len(campos) != 4:
            continue
        chave, canon, fp, fa = campos
        if not (chave and canon and fp.isdigit() and fa.isdigit()):
            ignorados += 1
            continue
        if chave in presentes:
            ignorados += 1
            continue
        novos.append((chave, canon, fp, fa))
        presentes.add(chave)

    todos = sorted(linhas + novos, key=lambda c: (c[0], c[1]))
    corpo = "".join("\t".join(c) + "\n" for c in todos)

    with io.open(lua_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(cabecalho)
        f.write("\n")
        f.write(corpo)
        f.write("]===]\n")

    print("fundidos %d novas palavras (%d puladas) -> %d linhas em %s"
          % (len(novos), ignorados, len(todos), lua_path))


if __name__ == "__main__":
    main()