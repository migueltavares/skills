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
# Exit code 0: nothing found. 1: hits to review. 2: nothing to check, or a
# target that is missing or unreadable.
set -euo pipefail
export LC_ALL=C.UTF-8

# pattern::European form. Patterns are Perl regexes, matched case-insensitively as whole words.
rules=(
  'telas?::ecrã'
  'arquivos?::ficheiro (arquivo only for an archive)'
  'usuári[oa]s?::utilizador'
  'senhas?::palavra-passe'
  'baixar::transferir'
  'fa(zer|ça|çam|z|zemos) (o )?(download|upload|login|logout)::transferir, carregar, iniciar sessão, terminar sessão'
  'salv(ar|e|ando|ou)::guardar'
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
  'mouses?::rato'
  'fatos?::facto when it means a fact (fato is a suit in Portugal)'
  'endereços?(?!\s+(de\s+)?(e-?mail|IP|eletrónico|web|do site))::morada, in forms'
  'agend(ar|e|ou|ei) (uma |a )?consultas?::marcar uma consulta'
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
  'trem::comboio'
  'sucos?::sumo'
  'sorvetes?::gelado'
  'xícaras?::chávena'
  'pedágios?::portagem'
  'CEP::código postal'
  'notas? fisca(l|is)::fatura, only when the product issues Portuguese invoices'
  'boletos?::referência Multibanco, only when the product really uses it'
  'CPF::NIF, only when the product really uses it'
  '(vale ressaltar|no panorama atual|em suma|desbloquear o potencial|levar ao próximo nível)::AI tell 3: delete the phrase'
  'alavanc\p{L}*::AI tell 2: say what it does'
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

for t in "${targets[@]}"; do
  [ "$t" = "-" ] || [ -e "$t" ] || { echo "Not found: $t" >&2; exit 2; }
done

stdin_copy=""
for i in "${!targets[@]}"; do
  if [ "${targets[$i]}" = "-" ]; then
    stdin_copy=$(mktemp)
    cat > "$stdin_copy"
    targets[$i]="$stdin_copy"
  fi
done
trap '[ -n "$stdin_copy" ] && rm -f "$stdin_copy"' EXIT

# Every text file under the targets, skipping .git, vendor and node_modules.
files=()
for t in "${targets[@]}"; do
  if [ -d "$t" ]; then
    while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$t" \( -name .git -o -name vendor -o -name node_modules \) -prune -o -type f -print0 | sort -z)
  else
    files+=("$t")
  fi
done

# One pass over every line, with every rule. Whole words: no letter, digit or
# underscore on either side.
status=0
RULES=$(printf '%s\n' "${rules[@]}") STDIN_COPY="$stdin_copy" perl -CSD -Mutf8 -e '
  use strict; use warnings; use Encode qw(decode);
  my @rules = map { my ($p, $f) = split /::/, $_, 2;
                    [qr/(?<![\p{L}\p{N}_])(?:$p)(?![\p{L}\p{N}_])/i, $f] }
              grep { length } split /\n/, decode("UTF-8", $ENV{RULES});
  my $hits = 0;
  for my $file (@ARGV) {
    next if -B $file && -s $file;
    open my $fh, "<:encoding(UTF-8)", $file or do { print STDERR "Cannot read $file, so the result is incomplete.\n"; exit 2 };
    my $name = $file eq $ENV{STDIN_COPY} ? "stdin" : $file;
    while (my $line = <$fh>) {
      for my $r (@rules) {
        while ($line =~ /$r->[0]/g) { $hits++; print "$name:$.:$&  ->  $r->[1]\n"; }
      }
    }
    close $fh;
  }
  if ($hits) { print STDERR "$hits possible Brazilian forms. Fix each one or note why it stays.\n"; exit 1 }
  print "No Brazilian forms found.\n";
' "${files[@]+"${files[@]}"}" || status=$?
exit "$status"
