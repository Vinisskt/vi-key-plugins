#!/usr/bin/env python3
# acentua_regras.py — enriquece o índice do :dict com as variantes ACENTUADAS
# que faltam, propostas pelas regras ortográficas (pt-BR, Novo Acordo) e
# VERIFICADAS no corpus (Leipzig, Wikipedia pt): só entra a grafia que o
# corpus realmente usa (contagem >= MIN_VERIF).
#
# Filosofia (consciente do risco): o acento em português marca a TÔNICA, e a
# mesma sequência de letras pode ter acento ou não ("pais"/"país", "maca"/"maça",
# "sabia"/"sabiá"). Por isso regra não decide sozinha em runtime: aqui a regra
# apenas PROPÕE as grafias plausíveis e o corpus ESCOLHE a que existe de fato
# (e com que frequência). Assim:
#   * só quebra homógrafo que o corpus desempata no sentido real de uso;
#   * nunca "troca por palavra incorreta" por achismo de terminologia.
#
# Conservador:
#   * só mexe em linhas onde a canônica é a forma PLANA e nunca ouve acento
#     (fa == 0) — não discute decisões já tomadas por frequência de corpus;
#   * depois do flip, fp/fa passam a vir do MESMO corpus (mesma unidade), então
#     a proteção 'ratio_plana_real' do plugin continua comparando certo
#     ("sabia" verbo x "sabiá" ave: fp grande do corpus preserva o verbo);
#   * exige MIN_VERIF ocorrências da grafia acentuada (>= 3).
#
# Uso:
#   python3 scripts/acentua_regras.py <sentences.txt> <dados.lua> [<saida.dat>]
#                                   [<index.dic>]
#   dados.lua é editado in-place; saida.dat recebe o miolo sem o módulo Lua.
#   index.dic (Hunspell PT) filtra: só entra grafia que o dicionário reconhece
#   como palavra — rejeita nomes próprios/espanhol/empréstimos ("agustín",
#   "álvarez", "acalmá"). É CONSERVADOR: perder uma correção é inofensivo;
#   trocar palavra por incorreta não é.

import io
import re
import sys

MIN_VERIF = 3          # ocorrências mínimas da grafia acentuada no corpus
MIN_LEN = 3            # ignora chaves minúsculas demais (ruído)

VOG = "aeiou"
ACENTOS = {
    "a": ["á", "â", "ã"],
    "e": ["é", "ê"],
    "i": ["í"],
    "o": ["ó", "ô", "õ"],
    "u": ["ú"],
}
TIL_FINAL = {"a": "ã", "o": "õ"}
TOKEN_RE = re.compile(r"[A-Za-zÀ-ÿçÇ']+")
LUA = None

# Alvos que o corpus "inventa" (empréstimo/sigla/apelido) e que o Hunspell
# aceita, mas NÃO são a palavra acentuada que queremos: bloquear à mão.
BLOCO = {
    "trocos": "troços",  # "trocos" (mudança) é palavra real; "troços" = coisas
    "paco": "paço",      # Paco (nome espanhol) x "paço" (palácio)
    "iva": "ivã",        # IVA (sigla) x Ivã (nome)
    "caqui": "cáqui",    # "caqui" (fruta, palavra real) x "cáqui" (cor)
    "nairobi": "nairóbi",  # paroxítona em -i: SEM acento por regra
}

# Curadoria final: só aplica o flip quando (chave -> canônica) foi revisado e
# aprovado (palavra real do pt-BR, grafia acentuada correta por regra + corpus).
# O pipeline inteiro (regras -> corpus -> Hunspell) continua rodando; este
# allowlist é o crivo humano que barra nomes/empréstimos/gírias que vazam.
ALLOW = {
    "esporadico": "esporádico",
    "ibis": "íbis",
    "geres": "gerês",
    "kaka": "kaká",
    "quasimodo": "quasímodo",
    "leonidas": "leônidas",
    "leticia": "letícia",
    "lidia": "lídia",
    "livia": "lívia",
    "penalti": "pênalti",
    "tamisa": "tâmisa",
    "tripoli": "trípoli",
    "viveres": "víveres",
    "vortex": "vórtex",
    "hipoxia": "hipóxia",
    "judo": "judô",
    "karaoke": "karaokê",
    "hanover": "hanôver",
    "canon": "cânon",
    "medici": "médici",
    "oma": "omã",
    "nene": "nenê",
    "meier": "méier",
    "merida": "mérida",
    "ramada": "ramadã",
    "suarez": "suárez",
    "felicia": "felícia",
    "axe": "axé",
    "katia": "kátia",
    "vitor": "vítor",
}

def ler(modelo):
    with io.open(modelo, encoding="utf-8") as f:
        inside = False
        for lin in f:
            if lin.startswith("return [===[\n"):
                inside = True
                continue
            if inside:
                if lin == "]===]\n" or lin == "]===]":
                    break
                yield lin
            # cabeçalho de comentário: ignorado


def gerar_candidatos(w):
    """Grafias acentuadas plausíveis da chave [w] (só a-z, minúscula).

    Regras aplicadas (Novo Acordo):
      * acento agudo/circunflexo/til numa vogal:  saida -> saída, cafe -> café,
        nevoa -> névoa, robo -> robô;
      * til na última vogal (nasal final):        coracao -> coração (o->ão);
      * c -> ç antes de a/o/u (não inicial):      maca -> maça (faltou o til p/
        "maçã", vem na combinação abaixo);
      * combinações: acento + ç, acento + til final: orgao -> órgão, bracao ->
        bração, itens? (não), maça -> maçã, comentario -> comentário (só agudo).
    """
    cands = set()
    vog = [(i, ch) for i, ch in enumerate(w) if ch in VOG]
    # 1 acento numa vogal
    for i, ch in vog:
        for a in ACENTOS[ch]:
            cands.add(w[:i] + a + w[i + 1:])
    # c -> ç (antes de a/o/u, nunca inicial)
    for i in range(1, len(w)):
        if w[i] == "c" and i + 1 < len(w) and w[i + 1] in "aou":
            cands.add(w[:i] + "ç" + w[i + 1:])
    # combina: (acento em vogal) x (til na vogal final, se outra) e (acento x ç)
    possiveis = list(cands)
    for i, ch in vog:
        for a in ACENTOS[ch]:
            alt = w[:i] + a + w[i + 1:]
            for j, chj in vog:
                if j == i:
                    continue
                t = TIL_FINAL.get(chj)
                if t:
                    cands.add(alt[:j] + t + alt[j + 1:])
    for alt in possiveis:
        for i in range(1, len(w)):
            if w[i] == "c" and i + 1 < len(w) and w[i + 1] in "aou":
                cands.add(alt[:i] + "ç" + alt[i + 1:])
    cands.discard(w)
    return cands


def main():
    if len(sys.argv) < 3:
        sys.exit("uso: acentua_regras.py <sentences.txt> <dados.lua> [<saida.dat>] [<index.dic>]")
    src, modelo = sys.argv[1], sys.argv[2]
    saida_dat = sys.argv[3] if len(sys.argv) > 3 else None
    dic_path = sys.argv[4] if len(sys.argv) > 4 else None

    dic = None
    if dic_path:
        dic = set()
        with io.open(dic_path, encoding="utf-8", errors="replace") as f:
            for lin in f:
                w = lin.rstrip("\n")
                if w and not w[0].isdigit():
                    dic.add(w.split("/")[0].lower())
        print("hunspell: validando contra %d palavras" % len(dic))

    print("corpus: contando grafias exatas...")
    ort = {}
    n_tok = 0
    with io.open(src, encoding="utf-8", errors="replace") as f:
        for lin in f:
            _, _, frase = lin.rstrip("\n").partition("\t")
            if not frase:
                continue
            for tok in TOKEN_RE.findall(frase):
                tok = tok.lower()
                ort[tok] = ort.get(tok, 0) + 1
                n_tok += 1
    print("  %d tokens, %d grafias distintas" % (n_tok, len(ort)))

    linhas = [lin.rstrip("\n") for lin in ler(modelo)]
    flip = 0
    exemplos = []
    saida = []
    for lin in linhas:
        partes = lin.split("\t")
        if len(partes) != 4:
            saida.append(lin)
            continue
        chave, canon, fp, fa = partes[0], partes[1], partes[2], partes[3]
        ok = (canon == chave and int(fa or 0) == 0 and len(chave) >= MIN_LEN
              and chave.isascii() and chave.islower())
        if not ok:
            saida.append("\t".join(partes))
            continue
        best, bn = None, 0
        for cand in gerar_candidatos(chave):
            if dic is not None and cand not in dic:
                continue
            if BLOCO.get(chave) == cand:
                continue
            n = ort.get(cand, 0)
            if n > bn:
                best, bn = cand, n
        # A forma PLANA precisa NÃO ser palavra do dicionário: se "manga" (fruta/
        # manga de camisa) é palavra real, flipar a canônica corrigiria em cima
        # de grafia legítima. Homógrafo (pais/país, sabiá/sabia) fica preservado.
        if dic is not None and chave in dic:
            best, bn = None, 0
        # Só aceita quando a grafia acentuada DOMINA no corpus (mesma unidade,
        # `bn >= pla`): rejeita "acentuações" de empréstimo/informal que o corpus
        # traz mas que NÃO são palavras (adaptá < adapta, diferenciá < diferencia).
        pla = ort.get(chave, 0)
        if best and bn >= MIN_VERIF and bn >= max(MIN_VERIF, pla):
            # curadoria humana: só aplica quando o par chave->canônica foi
            # revisado e aprovado; o allowlist também barra o que vaza do
            # filtro corporativo (nomes/empréstimos como "achém", "eça").
            if ALLOW.get(chave) == best:
                canon = best
                partes[1] = best
                partes[2] = str(ort.get(chave, 0))   # mesma unidade (corpus)
                partes[3] = str(bn)
                flip += 1
                if len(exemplos) < 8:
                    exemplos.append("%s -> %s (plana=%s acentuada=%s)"
                                    % (chave, best, partes[2], partes[3]))
        saida.append("\t".join(partes))
    print("linhas com canônica nova: %d" % flip)
    for e in exemplos:
        print("  %s" % e)
    if not sys.stdin.isatty():  # nunca entra aqui; mantido por clareza
        pass

    with io.open(modelo, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- dicionario_dados.lua — índice do :dict (GERADO). Não edite à mão.\n")
        f.write("-- Fonte: lista de frequência do português (hermitdave/FrequencyWords\n")
        f.write("-- pt_50k.txt, MIT) + variações acentuadas verificadas no corpus\n")
        f.write("-- Wikipedia pt (scripts/acentua_regras.py). Formato: 'chave\\tcanonical\\t'\n")
        f.write("-- 'freq_plana\\tfreq_acu' por linha, ordenado pela chave (busca binária).\n")
        f.write("return [===[\n")
        f.write("\n".join(saida) + "\n")
        f.write("]===]\n")
    print("atualizado: %s" % modelo)
    if saida_dat:
        with io.open(saida_dat, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(saida) + "\n")
        print("atualizado: %s" % saida_dat)


if __name__ == "__main__":
    main()