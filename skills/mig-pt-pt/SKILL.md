---
name: mig-pt-pt
description: Write, translate or review text in European Portuguese (pt-PT), removing Brazilian forms and AI tells. Use for any Portuguese UI string, email, page copy, lang file or translation, for sites with a PT locale, and for /mig-pt-pt.
metadata:
  credits:
    - skill: unslop
      author: poteto
      url: https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md
      license: MIT
      note: The AI tells list follows unslop's numbered format.
---

# mig-pt-pt

Models default to Brazilian Portuguese. A Portuguese reader spots it in the first sentence ("tela", "usuário", "estou fazendo"), and the text reads as foreign or machine-made. Everything this skill writes is European Portuguese, post-1990 spelling agreement, in plain words.

## Before writing

- Read the project's glossary: `docs/glossary-pt.md`, or a glossary section in AGENTS.md. Client terms translate the same way everywhere. Add new terms to it as you settle them.
- Find out the form of address the project uses. Without one, use the default below.

## Vocabulary

Brazilian words have Portuguese equivalents. The most common in software: ecrã (not tela), ficheiro (arquivo), utilizador (usuário), telemóvel (celular), palavra-passe (senha), transferir (baixar), carregar (fazer upload), guardar (salvar), eliminar or apagar (deletar), registo (cadastro, registro), equipa (equipe, time), aplicação (aplicativo), aceder (acessar), iniciar sessão and terminar sessão (logar, deslogar), contacto (contato), facto (fato).

The full list, with everyday and business words, is in [references/vocabulary.md](references/vocabulary.md). Check every text against it.

## Grammar

- **Progressive**: "estou a fazer", "a carregar...", never "estou fazendo", "carregando...".
- **Pronouns after the verb** in affirmative main clauses: "envie-me", "inscreva-se", "ligo-te". They go before the verb after negations, question words and most subordinating conjunctions: "não se esqueça", "onde o guardou?", "se me enviar", "que lhe enviámos". A yes/no question keeps them after: "Enviou-me o ficheiro?".
- **Past tense of -ar verbs**, first person plural: write the accent that tells it apart from the present, "enviámos" (we sent) versus "enviamos" (we send). The agreement makes it optional, and Portugal uses it.
- **Address**. Default to the formal third person without "você", which can sound blunt in Portugal: "Introduza o seu email", "Pode alterar a sua palavra-passe". Imperatives in UI use the same form: "Guarde", "Clique", "Escolha". Use "tu" only when the project's brand voice says so.
- **Spelling** follows the 1990 agreement as used in Portugal: ação, ótimo, direção, fatura. Silent consonants differ both ways: Portugal writes contacto and facto (Brazil contato, fato), and receção and perspetiva (Brazil recepção, perspectiva).
- **Accents** differ from Brazil: económico, académico, género, António, ténis, Antónia.

## Formats

- Dates `02/11/2026`, or "2 de novembro de 2026". Months and weekdays in lowercase.
- Times `14h30` in running text, `14:30` in tables and inputs.
- Numbers `1234,56`, and `1 234,56` with a space as the thousands separator in long figures.
- Money `12,50 €`, with a space before the euro sign. "IVA incluído" or "acresce IVA", stated once.
- Phone `+351 912 345 678`. Postcode `1000-001 Lisboa`.
- Tax and identity: NIF (not CPF), Cartão de Cidadão (not RG), fatura (not nota fiscal), morada (not endereço residencial, in forms).

## AI tells in Portuguese

Rule numbers are stable ids.

1. **Filler connectors.** "Além disso", "No entanto", "Por outro lado" opening sentence after sentence. Cut most; join sentences instead.
2. **Inflated words.** crucial, fundamental, essencial, robusto, inovador, único, potenciar, alavancar, otimizar a experiência. Say what it does.
3. **Stock phrases.** "No panorama atual", "No mundo atual", "Em suma", "Vale ressaltar", "É importante salientar que", "desbloquear o potencial", "levar ao próximo nível". Delete.
4. **"Não é apenas X, é Y."** State Y.
5. **Em dashes.** Use a comma or a full stop instead.
6. **Title Case In Headings.** Portuguese headings use sentence case: "Os nossos serviços", never "Os Nossos Serviços".
7. **Exclamation marks** in UI and emails. One per email at most, none in UI.
8. **Anglicisms with a Portuguese word.** "Fazer o login", "fazer o download", "checar", "customizar", "linkar". Use iniciar sessão, transferir, verificar, personalizar, associar.

## Laravel and lang files

- Locale `pt_PT` (or `pt` when the project has one Portuguese variant). Translate values only, never keys or `:placeholders`.
- Keep `:attribute`-style placeholders in the grammatical position Portuguese needs, and check plural forms (`{0}`, `{1}`, `[2,*]`).
- Read translated validation messages in context, in the form where they appear.

## Done when

Every string is checked against the vocabulary list, the grammar rules, the formats and the AI tells, and the glossary holds every client term used.
