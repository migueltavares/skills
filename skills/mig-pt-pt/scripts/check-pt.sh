#!/usr/bin/env bash
# Flag Brazilian Portuguese forms in files, folders or stdin.
#
# Usage: check-pt.sh [file | folder | -]...
# With no arguments it checks the usual Laravel locations: lang/pt_PT, lang/pt,
# lang/pt_PT.json, lang/pt.json, resources/lang/pt_PT, resources/lang/pt.
# Use - to read text from stdin: printf '%s\n' "Salvar arquivo" | check-pt.sh -
#
# Prints file:line, the match and the European form. Every hit needs a look:
# a few words are correct in Portugal in another sense (arquivo as an archive,
# baixar as lowering a price, tela as a painting canvas).
# Exit code 0: nothing found. 1: hits to review. 2: nothing to check.
set -euo pipefail
export LC_ALL=C.UTF-8

# pattern::European form. Patterns are PCRE, matched case-insensitively as whole words.
rules=(
  'telas?::ecrã'
  'arquivos?::ficheiro (arquivo only for an archive)'
  'usuári[oa]s?::utilizador'
  'senhas?::palavra-passe'
  'baixar::transferir'
  'fa(zer|ça|çam|z|zemos) (o )?(download|upload|login|logout)::transferir, carregar, iniciar sessão, terminar sessão'
  'salv(ar|e|ando|ou|o)::guardar'
  'delet(ar|e|ado|ada|ados|adas)::eliminar, apagar'
  'cadastr\p{L}*::registo, registar'
  'registros?::registo'
  'aplicativos?::aplicação'
  'acess(ar|e|em|ando|ou)::aceder (aceda, acede)'
  'deslogar::terminar sessão'
  'logar::iniciar sessão'
  'checar::verificar'
  'customiz\p{L}*::personalizar'
  'linkar::associar, ligar'
  'contatos?::contacto'
  'equipes?::equipa'
  'celular(es)?::telemóvel'
  'planilhas?::folha de cálculo'
  'você::formal third person without você (Pode alterar...)'
  'a gente::nós'
  'ônibus::autocarro'
  'geladeira::frigorífico'
  'banheiro::casa de banho'
  'café da manhã::pequeno-almoço'
  'recepção::receção'
  'perspectiva::perspetiva'
  '\p{L}*(ômic|êmic|ênero|ônio|ênis)\p{L}*::acute accent: económico, académico, género, António, ténis'
  'est(ou|á|amos|ão|ava|avam|eja|ive)\s+(?!(quando|comando|vindo|lindo)(?![\p{L}]))\p{L}+(ando|endo|indo)::estar a + infinitive (estou a fazer)'
  '(?!(quando|comando|vindo|lindo)(?![\p{L}]))\p{L}+(ando|endo|indo)(\.\.\.|…)::a + infinitive (a carregar...)'
)

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  for t in lang/pt_PT lang/pt lang/pt_PT.json lang/pt.json resources/lang/pt_PT resources/lang/pt; do
    [ -e "$t" ] && targets+=("$t")
  done
fi
if [ ${#targets[@]} -eq 0 ]; then
  echo "Nothing to check: pass files, folders or - for stdin." >&2
  exit 2
fi

stdin_copy=""
for i in "${!targets[@]}"; do
  if [ "${targets[$i]}" = "-" ]; then
    stdin_copy=$(mktemp)
    cat > "$stdin_copy"
    targets[$i]="$stdin_copy"
  fi
done
trap '[ -n "$stdin_copy" ] && rm -f "$stdin_copy"' EXIT

hits=0
for rule in "${rules[@]}"; do
  pattern="${rule%%::*}"
  fix="${rule#*::}"
  # Whole words: no letter, digit or underscore on either side.
  regex="(?<![\p{L}\p{N}_])(?:${pattern})(?![\p{L}\p{N}_])"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    hits=$((hits + 1))
    printf '%s  ->  %s\n' "$line" "$fix"
  done < <(grep -rnoiP --exclude-dir=.git --exclude-dir=vendor --exclude-dir=node_modules -- "$regex" "${targets[@]}" 2>/dev/null || true)
done

if [ "$hits" -gt 0 ]; then
  echo "$hits possible Brazilian forms. Fix each one or note why it stays." >&2
  exit 1
fi
echo "No Brazilian forms found."
