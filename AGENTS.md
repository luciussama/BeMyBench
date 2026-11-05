# AGENTS.md — BeMyBench (obrigatório)

Estas 2 regras valem para **toda execução** neste projeto. Em caso de conflito com instruções genéricas, estas regras vencem.

---

## 1. Filtrar comandos de teste e compilação

Se um comando despeja centenas de linhas de log no terminal, reduza a verbosidade e/ou filtre pelo caso específico antes de repetir.

Regras obrigatórias:

1. **Nunca rolar a suíte inteira** se já souber qual arquivo/caso falhou. Filtre pelo teste específico que falhou.
2. Use flags que reduzem verbosidade, por exemplo:
   - `flutter test --reporter compact <arquivo_de_teste_especifico>`
   - `flutter test --plain-name "<nome_do_teste_falho>"`
   - `cargo test -- --exact <nome_do_teste>`
   - `flutter analyze --no-fatal-warnings` (ou limitar escopo: `flutter analyze lib/caminho/arquivo.dart`)
3. Se um comando for inevitavelmente verboso (`flutter run`, builds longos), capture apenas o trecho relevante:
   ```bash
   flutter analyze 2>&1 | grep -E "error|warning|info|Analyzing" | head -n 50
   flutter test 2>&1 | grep -E "FAIL|✗|Expected|Actual|SOME TESTS|All tests" | head -n 30
   ```
5. Se o SDK não estiver no `PATH` (`flutter`/`dart` não encontrados), **não inventar instalação nem reinstalar por conta própria** — registre a limitação e faça checagem estática mínima (ex.: balanceamento de parênteses, grep por referências quebradas).

Aplicação analogia: assim como `dotnet test --verbosity quiet` evita 500 linhas de log, aqui `--reporter compact`, filtros por nome de teste e `grep` no output são obrigatórios.

---

## 2. Correções baseadas em resumos de erro

1. Ao reportar falha de teste/build, cole **apenas a mensagem principal do erro** (primeiras linhas significativas + arquivo/linha), nunca o log completo.
2. Ao pedir correção (minha resposta ou nova rodada do agente), inclua:
   - arquivo e linha onde falhou,
   - mensagem de erro resumida,
   - o que foi tentado / hipótese de causa (se houver).
3. **Não reexecutar a suíte inteira** para validar um fix pequeno — rode apenas o teste/analise do arquivo alterado. Só rode a suíte completa quando:
   - a mudança toca código compartilhado (ex.: `core/native`, `benchmark_runner`, temas, navegação), ou
   - o usuário pedir explicitamente, ou
   - for pré-push / validação de CI.
4. Erros envidados para o usuário devem ser curtos e acionáveis. Evite "rode de novo e me mande o log inteiro".

---

## 3. Limites de tentativa e relatório seguro

**Comando seguro para rodar testes:**
Ao executar `flutter test`, use a sintaxe abaixo para preservar o código de saída (exit code) e ainda encurtar o output:

```bash
flutter test --reporter compact <arquivo> || true
```

Isso garante que:
- O agente possa verificar o exit code após o comando (`$?` no shell) para saber se passou ou falhou.
- O output no terminal é encurtado pelo reporter compact, não exibindo 500+ linhas de log.
- Se o teste falhar, o `|| true` impede que o script pare imediatamente, permitindo que o agente processe o erro e continue.

**Limite de tentativas antes de pedir ajuda:**
Se o mesmo teste falhar **2 vezes seguidas** após tentativas de correção (usando o comando seguro acima, ajustando o código e rodando novamente), **pare a execução imediatamente e peça orientação ao usuário com o resumo do erro**. Isso impede que o modelo entre em loops de tentativas infinitas sem progresso.

---

## 4. Concisão: não reimprimir arquivos inteiros (mantida)

1. Ao implementar/ajustar código, prefira **edits cirúrgicos** (trocar apenas o trecho alterado) em vez de reescrever o arquivo inteiro.
2. Nunca reimprimir um arquivo inteiro no chat quando apenas poucas linhas mudaram — mostre apenas o diff ou o trecho alterado.
3. Leitura de arquivos: use `grep` + `read` com `offset`/`limit` para ler trechos específicos. Evite ler arquivos de > 200 linhas por inteiro.
4. Em respostas, seja conciso: o que mudou, onde, e o que resta. Sem repetir contexto já sabido.
5. O `journal.json` do repositório é a fonte de verdade entre sessões. Mantenha-o atualizado a cada avanço (1 linha por advance).