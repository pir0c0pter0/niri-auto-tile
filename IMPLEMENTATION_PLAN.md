# Plano de correções e melhorias do Niri Auto Tile

Data: 2026-11-09. Base: versão 2.0.8, commit `8efab8d`.
Estado: código implementado, com escopo por workspace confirmado durante a
execução; testes automatizados e validação isolada concluídos. Pendências de
hardware e publicação estão registradas abaixo. Implementação e versão 2.1.0
registradas em commits locais; sem push.

## Ajuste de escopo confirmado: divisão por workspace

O usuário confirmou durante a implementação que a divisão deve ser **por
workspace**, e que cada widget deve mostrar o valor do workspace ativo em seu
monitor. Esta seção substitui as decisões de preferência global abaixo; as
garantias de foco, pausa, erros e testes continuam exigidas.

- Trocar foco/workspace atualiza somente a representação. Não redistribuir por
  uma simples troca de foco. Eventos de topologia usam a divisão do workspace
  afetado quando ele estiver focado.
- Cada widget resolve seu próprio `barWidget.outputName()` e o workspace
  `is_active` desse output. O painel recebe esse output como contexto do widget;
  quando aberto por IPC sem contexto, segue o workspace focado. Mostrar no painel
  qual workspace está sendo configurado. Controles de divisão/reaplicação ficam
  indisponíveis enquanto não houver um workspace conhecido.
- Seleção/reaplicação capturam o ID do workspace no clique. O serviço nunca
  redireciona um pedido explícito para outro workspace se o foco mudar enquanto
  ele aguarda; salva a preferência do alvo, mas só aplica quando esse alvo está
  focado. Nova seleção substitui intenção anterior ainda não iniciada. Pausa
  continua global e somente da sessão; retomar usa o workspace então focado.
- O serviço passa a ser dono da persistência: painel envia solicitação, serviço
  valida, atualiza a preferência em memória, tenta salvar e publica o resultado.
  Repetir a mesma divisão tenta salvar de novo sem redistribuir. Reaplicar não
  grava. Nenhum render grava ou pede redistribuição.
- Usar `workspace-divisions.json`, versionado em 1, com `session` igual a
  `noctalia.getenv("NIRI_SOCKET")`, `byId` e `byName`. IDs só são reaproveitados
  se o socket da sessão coincidir; nomes podem persistir entre sessões do niri.
  Sem identidade de sessão confiável, não restaurar IDs do disco. Workspaces sem
  nome mantêm preferências durante a sessão do niri, inclusive ao reiniciar
  Noctalia; nomes permitem restauração após reiniciar o compositor. Não associar
  preferências ao índice mutável do workspace nem ao monitor.
- Manter o arquivo legado `division` intacto e usá-lo como padrão para workspaces
  ainda não configurados (fallback 4). Não sobrescrever arquivo JSON malformado
  automaticamente; seleção explícita pode substituí-lo por dados válidos.
- Renomear/nomear um workspace conhecido preserva a divisão sob o novo nome sem
  redistribuir. Essa atualização automática de metadados só pode salvar se houve
  leitura válida do JSON ou salvamento explícito bem-sucedido. Leitura
  desconhecida/falha e JSON malformado nunca autorizam sobrescrita automática;
  manter estado temporário e aviso. Um salvamento completo bem-sucedido também
  resolve os avisos dos outros workspaces cujos valores foram gravados.
- Fonte viva de workspaces: eventos `WorkspacesChanged`, `WorkspaceActivated` e
  `WorkspaceActiveWindowChanged`, conforme contrato do niri. Snapshot de consulta
  serve de bootstrap/recuperação apenas se nenhum evento de workspaces mais novo
  tiver sido recebido. Eventos de foco atualizam indicadores mesmo durante pausa.
- Estado compartilhado: `workspaces` (lista), `workspaceDivisions` (mapa por ID
  textual), `workspaceRequest` (`serial`, `workspaceId`, `division` opcional;
  ausência de division significa reaplicar), `saveErrors`, `layoutStatuses` e
  `layoutErrors` (mapas por ID textual), além de `paused` e `streamError` globais.
  O painel incrementa serial a partir do pedido atual, sem reinicializar ao abrir.
  Nenhum contador antigo é reproduzido como pedido ao recarregar serviço.
- Validar com dois widgets/output distintos: A=4 e B=2; foco alterna sem mudar
  nenhum valor; mudar a divisão de B não altera A; workspace movido para outro
  monitor mantém o valor; pedido atrasado de A não redimensiona B; persistência
  respeita reinício do Noctalia versus mudança de sessão do niri. Adaptar todos
  os testes anteriores, mensagens nos dez idiomas, README e captura real.

## Objetivo e limites

Corrigir aplicação de configurações, recuperação de falhas e consistência de foco;
depois acrescentar reaplicação, pausa temporária e feedback compreensível. Cobrir
todos os achados da análise sem criar um novo sistema de configuração.

Preservar divisões inteiras de 1 a 4, padrão legado ou 4, colunas empilhadas,
isolamento dos workspaces não focados e suporte
ao Noctalia 5. Não migrar configurações da versão 1, adicionar dependências,
editar configuração do niri nem criar daemon. Debounce e reconexão continuam
internos, sem opções novas para o usuário.

A análise anterior executou `lua test_service.lua` e o lint do Noctalia com
sucesso. As reproduções de concorrência e foco usaram dados/mocks Lua, não uma
sessão real do compositor. Essa lacuna inicial foi coberta por `test_runtime.lua`
e pela validação real isolada descrita ao fim deste documento.

## Decisões de comportamento

- A divisão representa uma preferência; salvar, solicitar aplicação e confirmar
  execução são resultados distintos. Durante a sessão, estado compartilhado
  presente prevalece sobre disco. O painel envia pedidos com workspace capturado;
  o serviço salva e publica resultados por workspace. Render
  não limpa erros. Leitores usam `state.get` antes de observar mudanças, sem
  depender de uma chamada inicial do watcher.
- Solicitação explícita tem precedência sobre o filtro de eventos automáticos.
  Pedidos rápidos se agrupam e a divisão mais recente prevalece. O alvo é o
  workspace capturado no clique, que precisa estar focado para receber comandos.
  Uma tentativa automática mantém o conjunto de workspaces afetados pelo evento:
  trocar foco não autoriza aplicar em outro workspace sem evento correspondente.
- Pausa vale somente na sessão. Escolher divisão durante a pausa salva a
  preferência, sem alterar o layout. Reaplicar fica indisponível durante a pausa;
  retomar solicita uma aplicação com a preferência mais recente.
- Pausar impede novos lotes; um lote de comandos já iniciado termina, incluindo
  a tentativa de restauração do foco. Uma geração local incrementada ao pausar
  invalida consultas antigas, inclusive após retomada rápida. Não matar processos
  para interromper foco. Encerramento externo ou timeout pode impedir restauração.
- Política definida para foco flutuante: não redistribuir enquanto a janela
  efetivamente focada for flutuante, independentemente da quantidade de colunas.
  Salvar a preferência continua permitido; explicar que é necessário focar uma
  janela em mosaico e reaplicar. Não adicionar aplicação em toda mudança de foco.
  Quando o painel toma o foco, usar a janela ativa do workspace para essa decisão.
  Pedido com alvo flutuante termina sem ações e sem retentativa; voltar o foco
  para mosaico não ressuscita esse pedido. Reaplicar/retomar seguem a mesma regra.
- Divergência entre foco do workspace e foco das janelas invalida o lote. Fazer
  exatamente uma nova tentativa coalescida por intenção; se continuar divergente,
  encerrar sem comandos, liberar `busy` e informar que não foi aplicado. Um novo
  evento/pedido pode iniciar outra operação. A verificação de abertura/fechamento
  não renova esse limite. Manter o fallback do painel.
- A preferência acompanha o workspace quando ele muda de monitor. A pausa e
  a disponibilidade do stream permanecem globais para a sessão.

## Alcance por arquivo

| Arquivo | Alterações previstas |
| --- | --- |
| `niri-auto-tile/service.luau` | Intenção manual, agendamento, stream, erros, foco, flutuantes, pausa e verificação de layout |
| `niri-auto-tile/panel.luau` | Salvamento com feedback, reaplicação, pausa, explicações e identificação de controles |
| `niri-auto-tile/widget.luau` | Validação 1–4 e indicação acessível de pausa/erro |
| `test_service.lua` | Regressões de lógica pura, foco e topologia |
| `test_runtime.lua` (novo) | Mock local de Noctalia, fila assíncrona, falhas e estado da UI; sem dependências |
| `niri-auto-tile/translations/*.json` | Chaves e parâmetros consistentes nos dez idiomas |
| `niri-auto-tile/plugin.toml` | Dimensões do painel apenas se necessário; versão no release |
| `catalog.toml` | Versão igual à do manifesto no release |
| `README.md`, `CHANGELOG.md` | Comportamentos, limitações, comandos de validação e releases |
| `docs/column-layout.png` | Atualizar captura se o painel mudar, capturada da interface real |

Não modificar `.codegraph/` nem adicionar seus arquivos ao commit.

## Etapa 1 — Regressões e correções de execução

Os contratos abaixo foram consultados pelo revisor de integração via Context7
e [documentação oficial de runtime do Noctalia](https://github.com/noctalia-dev/noctalia-docs/blob/main/src/content/docs/noctalia/plugins/development/runtime-api.mdx).
Antes de implementar, conferir suporte na versão mínima Noctalia 5.0/API 4;
a documentação atual não comprova por si só compatibilidade com essa versão.
Não aumentar a versão mínima silenciosamente para viabilizar o plano.

### T1. Testes assíncronos mínimos — prioridade alta

Criar `test_runtime.lua` com ambientes separados para serviço, painel e widget,
evitando colisões de globais como `update()`. Compartilhar somente o mock de
estado e recursos necessários; recriar os ambientes entre casos. Usar mocks
pequenos de `noctalia`, fila de callbacks e avanço explícito de `update()`.
Não executar callbacks de consulta
imediatamente: isso esconderia a concorrência encontrada. Simular apenas APIs
usadas pelo plugin; não reproduzir o runtime inteiro. O teste não deve executar
comandos contra o compositor nem ler/escrever preferências reais.

A drenagem da fila/ticks tem limite de passos e falha se não estabilizar; não
usar um loop de espera ilimitado. Verificar no máximo um lote de layout em
andamento e nenhum lote novo após estabilização, incluindo eventos produzidos
pelo próprio plugin. Simular separadamente watchers de estado síncronos e
callbacks de processos enfileirados.

Adicionar as regressões com cada correção, demonstrando falha antes e sucesso
depois. Capturar propriedades relevantes dos controles, sem snapshots completos
da árvore visual. Manter os testes puros existentes.

### F1. Não perder solicitação manual durante `busy` — prioridade alta

Alvos: `redistribute`, `finishRedistribution`, watcher de `workspaceRequest`, `update()`.
Registrar uma intenção explícita independente de `pendingWorkspaceIds`; não
substituí-la por um simples `rerun`. Cada passagem captura a intenção que iniciou;
pedidos posteriores permanecem pendentes, inclusive se a passagem antiga falhar.
Falha de consulta encerra só aquela passagem com erro e libera `busy`, sem retry
ilimitado. Divergência de foco admite uma única retentativa como definido em F4.
Capturar a divisão efetivamente usada ao iniciar o lote: concluir um lote de 2
não comprova aplicação de 4 escolhida durante sua execução. Manter
eventos e verificações de topologia necessários, mas não deixá-los impedir a
aplicação explícita no workspace focado. Não criar fila genérica de tarefas.

Aceite: evento no workspace B inicia consulta; outro evento em B chega durante
`busy`; usuário muda a divisão com A focado; após drenar callbacks e ticks, A
recebe a última divisão e B não é redimensionado. Testar também serviço ocioso,
várias escolhas rápidas, evento recebido durante lote e falha de consulta antiga
enquanto outra escolha está pendente. Testar lote de 2 concluindo depois de uma
escolha de 4, tanto com sucesso quanto com erro na aplicação posterior de 4.
Uma falha deve liberar `busy` e permitir novo pedido, sem repetição infinita.

### F2. Recuperar falha de lançamento do stream — prioridade alta

Alvos: `startStream`, inicialização e `update()`. Marcar `streamStarted` apenas
quando a inicialização for aceita. Repetir tentativas com intervalo interno
limitado (1 s, 2 s, 4 s, 8 s, máximo 10 s entre tentativas), reaproveitando o mecanismo de
atualização existente e sem atrasar aplicações manuais. Apenas uma tentativa
pendente/stream ativo; log e estado visível sem mensagens a cada tick.

O contrato documentado de `runStream(cmd, onLine)` retorna se o processo iniciou,
sem callback documentado de encerramento. F2 recupera retornos `false`; `true`
interrompe as tentativas, mas não comprova conexão com o compositor. Receber um
evento válido comprova comunicação naquele momento, não saúde permanente.
Encerramento posterior não detectável permanece uma limitação documentada deste
ciclo. Não abrir streams extras por simples silêncio nem prometer reconexão
completa. Se a versão mínima tiver outro mecanismo documentado, revisar essa
limitação antes de ampliar o fix.

Aceite: falhar a primeira inicialização, aceitar a segunda e receber eventos;
falhar repetidamente sem loop ocupado; seleção manual continuar utilizável;
não duplicar stream; `true` sem linhas não produz status falso de conexão.
Usar ticks simulados para conferir 1/2/4/8/10 segundos e manutenção do teto,
sem relógio real. Snapshot inicial diferente do cache anterior deve alimentar a
próxima decisão de topologia; receber uma linha qualquer não basta como aceite.
Ressincronização não pode sobrescrever eventos novos com consulta antiga: após
abrir o stream, seu snapshot/eventos alimentam o cache, sem reaplicar uma consulta
anterior sobre ele. Confirmar o snapshot inicial do niri na versão suportada.

### F3. Preservar erros sem abandonar restauração de foco — prioridade alta

Alvos: `action`, `buildCommand`, callback de `runAsync`.
Deixar de descartar stderr relevante; acumular resultado de falha do lote e
devolvê-lo mesmo se a última restauração de foco funcionar. Preservar a proteção
que impede redimensionar quando o foco na janela representante falha. Continuar
até tentar restaurar o foco, sem usar um encadeamento que aborte antes disso.
Publicar falha de execução e limpar o erro apenas após recuperação comprovada.
Consultas com `timedOut` ou `stdoutTruncated`, quando fornecidos pela API, não
produzem lote. Timeout do lote, morte de processo ou encerramento do runtime podem
impedir a restauração: registrar falha/resultado não confirmado, nunca sucesso.
Não usar `set -e`, pois abortaria antes da tentativa de restauração.

Aceite: usando um `niri` falso em ambiente isolado, resize falha, foco final é
tentado, saída do lote é não zero e há diagnóstico; falha de foco não redimensiona
a janela errada; falha de restauração também é reportada. Nenhum teste usa o
binário real por acidente. Falhas de início, resposta inválida e código não zero
nas consultas liberam `busy` e não impedem novos pedidos. Cobrir timeout e stdout
truncado nas consultas, timeout no lote e falha de restauração separadamente.
Falhas de foco nas âncoras e de `center-visible-columns` também devem sobreviver
ao sucesso da restauração final. O `niri` falso registra argumentos em diretório
temporário controlado; executar o lote pelo mesmo interpretador previsto no
contrato de `runAsync`, sem fallback para um executável real.

## Etapa 2 — Foco, topologia e configurações consistentes

### F4. Rejeitar snapshots com foco incompatível — prioridade alta

Alvos: consultas de workspaces/janelas, `groupColumns`, `buildCommand`.
Antes de construir comandos, conferir se a janela focada pertence ao workspace
selecionado. Tratar ausência de foco causada pelo painel com `active_window_id`,
validando que a janela ainda existe e pertence ao workspace. A janela efetivamente
focada tem precedência; só usar a ativa na ausência de janela focada. Workspace
vazio termina sem ações como ausência de alvo, não como erro IPC; ID ativo fechado
ou incompatível usa a retentativa limitada. Não restaurar foco para ID obtido de
um snapshot já inconsistente.

Aceite: workspace A consultado e janela focada B na resposta seguinte produzem
zero comandos para A. Um pedido manual de A não é redirecionado para B;
um evento automático só de A também termina sem ações em B. Duas
divergências consecutivas não geram terceira consulta para aquela intenção. Painel
com foco continua permitindo aplicar; janela fechada entre consultas não causa
alvo inválido. Isso reduz corridas, mas não torna o lote atômico: troca de foco
durante comandos ainda requer validação real e descrição honesta da limitação.

### F5. Tornar explícita a política de foco flutuante — prioridade média

Alvos: `groupColumns`, `visibleRange`, `buildCommand` e feedback do painel.
Aplicar a política de foco flutuante descrita acima igualmente a 1, 4, 5 e mais
colunas. Diferenciar falta de alvo elegível de erro IPC. Não redimensionar nem
alterar a posição de janelas flutuantes; manter a divisão escolhida para uso
posterior. Documentar esse comportamento.

Aceite: mesma decisão com quatro e cinco colunas, com e sem foco no painel;
nenhum comando sobre flutuantes; janela em mosaico focada volta a permitir
aplicação explícita sem exigir mudança de divisão.

### F6. Ignorar alterações exclusivamente flutuantes — prioridade média

Alvos: `topology`, `addWorkspace`, `shouldRedistribute`.
Continuar atualizando o cache e ignorar apenas eventos comprovadamente exclusivos
de flutuantes. Informação incompleta não equivale a janela flutuante: manter o
tratamento conservador para abertura sem posição de coluna utilizável. Marcar
workspaces cuja topologia de mosaico foi afetada antes ou depois. Não perder transições
tiled→floating, floating→tiled, mudanças de workspace ou colunas empilhadas.

Aceite: abrir/fechar/mover uma janela exclusivamente flutuante não agenda
redistribuição nem verificação; transições que retiram/adicionam coluna em
mosaico continuam tratadas. Testar eventos incrementais, `WindowsChanged` e
abertura tiled com posição inicialmente ausente e posterior atualização.

### F7. Validar divisão igualmente em todas as entradas — prioridade média

Alvos: widget, painel e serviço. Aceitar somente inteiros de 1 a 4, com fallback
4, inclusive dados lidos do arquivo e do estado compartilhado. Reutilizar um
helper existente se o runtime permitir sem nova arquitetura; caso contrário,
manter a pequena validação local consistente. Não mudar o formato do arquivo.
Usar estado compartilhado quando presente e arquivo somente quando ausente;
estado presente inválido usa 4, sem cair silenciosamente no disco. Normalizar
localmente sem gravar arquivo nem republicar dentro dos watchers.

Aceite: nil, texto inválido, 0, 5 e fracionários resultam em 4 nos três componentes;
valores válidos e texto numérico persistido continuam funcionando. Testar startup
e atualização de estado; evitar watchers recursivos de normalização. Estado
inválido com arquivo válido deve produzir o mesmo fallback nos componentes, sem
escrita automática. Arquivo ausente é primeira utilização normal.

### F8. Informar falha de persistência — prioridade média

Alvos: solicitação do painel, serviço, leitura inicial e traduções. O serviço
valida o alvo, publica a preferência em memória e o resultado de salvamento por
workspace. Somente a alteração de divisão agenda aplicação; repetir o valor
repete a gravação. O clique emite um pedido, sem aplicação duplicada. Permitir
aplicação temporária quando `writeFile` falha ou não há diretório de dados;
mostrar aviso traduzido e mantê-lo enquanto a preferência não tiver sido salva.
Limpar o aviso após gravação bem-sucedida. Guardar o aviso no estado compartilhado
e recuperá-lo ao recriar o painel; nenhum render o apaga. Clicar novamente no
número selecionado repete a gravação sem redistribuir, e o aviso explica essa
forma de tentar salvar de novo. Não sobrescrever a preferência da sessão com o
valor antigo do disco ao reabrir o painel. Conferir e documentar o ciclo de vida
do estado entre reabertura, recarga de componente e reinício completo.

Aceite: escrita falha → seleção da sessão muda e aviso aparece; reabrir preserva
preferência/aviso; nova tentativa de salvar funciona e limpa aviso; reinício
recupera o valor realmente salvo. Reaplicar layout não deve afirmar que salvou.
Testar recriação real do contexto do painel com o mesmo mock de estado, watchers
síncronos e zero comandos de layout ao repetir gravação do número já selecionado.

## Etapa 3 — Controles e feedback

### M1. Reaplicar agora — prioridade média

Depende de F1/F4/F5. Adicionar ação explícita no painel que solicite a divisão
atual pelo mesmo caminho manual corrigido, sem alterar/gravar a preferência.
Manter seleção do mesmo número como operação sem redistribuição, preservando o
comportamento documentado e evitando ação dupla. Usar `workspaceRequest` com
serial incrementado, workspaceId e sem division; o serviço observa o novo serial
e registra a intenção de F1. O painel não reinicializa a chave
ao abrir. O serviço lê o valor inicial sem reproduzir contador antigo como pedido
novo. Pedidos durante execução são coalescidos. O sinal não vai para o arquivo.

Aceite: escolher 3, ajustar larguras, reaplicar → aplicar 3 no workspace focado;
trocar de workspace e reaplicar funciona; repetição durante `busy` é coalescida;
não grava disco e não muda workspaces não focados.

### M2. Pausar/Retomar por sessão — prioridade média

Depende de F1 e M1. Estado inicial ativo; painel alterna pausa e widget indica
estado. Continuar recebendo eventos e mantendo topologia enquanto pausado.
Descartar trabalho automático acumulado que ficou obsoleto; retomar usa consulta
atual e solicita uma aplicação manual, sem reproduzir uma fila antiga.
Pausar descarta intenções ainda não iniciadas, debounce e verificações obsoletas,
e incrementa uma geração local. Consultas capturam essa geração e não podem
iniciar lote se ela mudou, mesmo que já tenha ocorrido retomada. O callback antigo
libera `busy` sem consumir a intenção nova de retomada; callback de lote antigo
não ressuscita verificações descartadas. Escolhas durante pausa não acumulam
pedidos. Estado do serviço permanece consistente ao reabrir o painel.

Aceite: eventos pausados não geram lotes; preferência pode ser salva durante
pausa; retomar aplica a última escolha uma vez em layout estável; pausa durante
consulta impede lote; pausa durante lote deixa restauração concluir; reinício
começa ativo e usa divisão persistida. Testar retomar com foco flutuante/erro IPC,
pausar→retomar antes da resposta antiga e escolher várias divisões durante pausa.

### M3. Estado e explicação compreensíveis — prioridade média

Depende de F2/F3/F5/F8/M2. Mostrar preferência, pausa e falhas sem confundir
salvamento com execução. Usar estado transitório mínimo compartilhado; manter
erros de salvamento, lançamento/comunicação do stream e execução independentes.
Aplicação manual bem-sucedida não limpa problema do stream; consulta sem lote
não apaga erro de aplicação; callback antigo não apresenta preferência nova como
aplicada nem substitui seu resultado. Estado inicial é lido com `get` e atualizações
acompanhadas com `watch`. Abertura do painel não reinicializa esses estados.
Widget conserva número e acrescenta identificação por texto/tooltip, não só cor.
O painel identifica o workspace e explica fração por coluna e aplicação ao workspace
atual; para divisão 3, apresentar porcentagem aproximada.

Aceite: mensagens úteis para pausa, aplicação não possível com foco flutuante,
falha de salvamento, erro IPC e recuperação; nenhum sucesso falso por apenas
escolher uma divisão. Não afirmar que stream está saudável apenas por estar sem
eventos. Testes inspecionam estado/textos relevantes.
Para foco flutuante, usar orientação equivalente a “Layout não aplicado: foque
uma janela em mosaico e use Reaplicar”. Ao retomar nesse estado, indicar automação
ativa sem alegar aplicação concluída. Validar coexistência de falha de salvamento,
falha do stream e aplicação manual bem-sucedida, sem apagar avisos indevidamente.

### M4. Acessibilidade, traduções e tamanho do painel — prioridade média

Identificar o botão fechar com texto/tooltip traduzido e verificar o nome
acessível suportado pelo runtime. Usar controles existentes para navegação por
teclado, foco visível, ativação e estado selecionado; não inventar propriedades
de UI sem verificar a API. Pausa e erro precisam ser distinguíveis sem cor.

Atualizar os dez catálogos com as mesmas chaves e placeholders. Ajustar altura
do painel apenas ao conteúdo necessário; verificar textos longos, quebra,
escala e posicionamento junto à barra. Atualizar captura do README na sessão real.

Aceite: uso completo por teclado; fechar identificável; divisão selecionada e
pausa perceptíveis; traduções sem chaves ausentes/parâmetros inconsistentes;
painel sem corte em português, inglês e um idioma com textos mais longos.
Conferir ordem de foco e sua preservação após renderizações de estado, ativação
de Pausar/Retomar e indisponibilidade perceptível de Reaplicar durante pausa.
Testar altura/quebras também com dois avisos simultâneos e texto longo.

## Etapa 4 — Reduzir trabalho redundante sem perder correções tardias

### M5. Verificação sem reaplicação desnecessária — prioridade posterior

Depende de F1–F6 e testes de runtime. Medir contagem de consultas/ações em casos
de 1, 4 e 8 colunas e rajadas de abertura/fechamento. Manter a segunda leitura
necessária para detectar mudanças tardias. Evitar novo lote apenas se o estado
atual observado provar que o resultado desejado já foi atingido, incluindo
larguras, enquadramento/centralização e foco. Larguras corretas sozinhas não
permitem eliminar o lote que também ancora e centraliza colunas.

Não usar só igualdade de topologia ou do comando anterior: largura pode mudar
sem mudança de coluna. Confirmar os dados de geometria disponíveis, cálculo de
percentual, gaps, escala e tolerância de arredondamento antes de comparar.
Se esses dados não permitirem comprovação segura, entregar a medição e manter a
segunda aplicação, registrando o motivo; não trocar correção por otimização.

Aceite: layout estável evita ações redundantes quando comprovável; alteração
tardia ou falha parcial ainda provoca correção; três colunas e escala fracionada
não criam loop de correção; foco/restauração continuam iguais. Ganho será medido,
não estimado como promessa.

## Ordem de implementação e critérios de conclusão

1. T1 com F1, depois F2 e F3: concorrência, recuperação e diagnóstico.
2. F4/F5/F6: consistência de foco e eventos de mosaico.
3. F7/F8: validação e persistência.
4. M1/M2/M3/M4: controles, feedback, traduções e verificação visual.
5. M5: medir e aplicar somente otimização demonstravelmente segura.
6. Atualizar README/changelog, executar regressão completa e preparar release.

Cada correção acompanha seu teste no mesmo commit. Antes de editar função,
consultar CodeGraph e todos os chamadores; atualizar consumidores afetados no
mesmo passo. Antes de cada commit de código executar:

```bash
lua test_service.lua
lua test_runtime.lua
noctalia plugins lint niri-auto-tile
```

O comando de runtime passa a ser obrigatório após criação do arquivo. Verificar
também JSON dos catálogos, igualdade de chaves/placeholders e `git diff --check`.

Validação real antes de considerar as mudanças prontas: um e dois monitores;
divisões 1–4; mais/menos colunas que a divisão; pilhas; flutuantes; painel com
foco; mudanças rápidas de foco/workspace; fechar janela durante operação;
rajadas de eventos; pausa/retomada; reaplicação e reinício. Conferir largura,
foco final, comportamento visual e isolamento do outro monitor. Preferências
reais devem ser preservadas/restauradas no teste. Se não houver sessão adequada,
registrar o teste como pendente, sem afirmar validação completa.

Resultados da implementação e limites da validação:

| Critério | Resultado | Evidência |
| --- | --- | --- |
| Regressões T1/F1–F8 e workspaces | Passou | `lua test_service.lua`; 44 grupos em `lua test_runtime.lua`; regressões vermelhas comprovadas antes dos fixes de concorrência, stream, shell, normalização, 4/2, renomeação e leitura desconhecida |
| Controles M1–M4 | Passou no ambiente isolado | Tab/Enter, pausa/retomada, reaplicar, avisos simultâneos, rolamento, escala 125%, inglês/português/alemão; 26 chaves e placeholders iguais nos 10 catálogos; lint 0 erros/avisos |
| Desempenho M5 | Medido; segundo lote preservado | Duas passagens completas de 1/4/8 colunas geram 16/28/44 invocações niri, como antes. Eventos exclusivamente flutuantes agora geram zero passagens. Não há comprovação suficiente de enquadramento para eliminar a verificação |
| Compositor e workspaces | Passou em output virtual único | Cage headless → niri 26.04 → Noctalia 5.4, XDG e D-Bus privados; divisões 1–4, pilhas, foco flutuante com 4/5 colunas, falhas e recuperação, workspace A=4/B=2, foco sem redimensionamento e reinício do Noctalia |
| Dois monitores físicos | Pendente | Dois widgets/output e migração de workspace cobertos por mocks; não foi alterada a sessão real do usuário |
| Compatibilidade Noctalia 5.0/API 4 | APIs conferidas na fonte; execução na 5.4 | `luau_host.cpp`, `plugin_bindings.cpp` e reconciliador UI da tag v5.0.0-beta.4; interface atual testada na 5.4, sem teste de binário 5.0 |
| Release | Local 2.1.0 | Manifesto e catálogo sincronizados; changelog datado; commit de implementação separado do release e tag anotada local; sem push |

A captura `docs/column-layout.png` veio da interface real isolada. Na sessão,
cinco colunas tiveram larguras 1240/612/402/298 px para divisões 1/2/3/4 em
output de 1272 px, respeitando os gaps do niri. Outro workspace conservou uma
largura manual de 863 px enquanto o atual foi ajustado. Após o ajuste de escopo,
Development=4 e Chat=2 foram preservados ao mudar foco e reiniciar Noctalia;
renomeações foram gravadas sem redimensionar. Nomes entre sessões novas do
compositor e isolamento entre dois monitores foram validados por testes.

A revisão independente da implementação corrigiu ainda: erro antigo mascarando
motivo flutuante, erro de lote ocultado após pausa, fixture de foco incorreta,
área rolável sem altura propagada, restauração após renomear e sobrescrita de
arquivo desconhecido em autosave. Cada frente de implementação foi entregue a
subagentes iniciados sem histórico, seguida de integração e revisão separada.

## Commits e versões

Commits pequenos e imperativos, por exemplo `fix: preserve pending manual layout
requests`, `fix: retry failed event stream startup`, `fix: report layout command
failures`, `feat: add reapply layout action`, `feat: add temporary tiling pause`.
Não criar um commit gigante de refatoração nem separar o teste do fix que cobre.

Partindo de 2.0.8, a entrega conjunta com preferências por workspace, reaplicação
e pausa selecionou 2.1.0. A implementação foi registrada separadamente do commit
`chore(release): v2.1.0`, com tag anotada local correspondente.

Antes de um push futuro, seguir AGENTS.md: versão igual em `plugin.toml` e
`catalog.toml`, seção datada no changelog, commit separado `chore(release): vX.Y.Z`
e tag anotada correspondente. Atualizar referências de versão do README. No
período de testes v2, publicar commit de release/tag; sem GitHub Release nem
registro Noctalia, salvo pedido explícito. Nesta entrega foram solicitados commit
e atualização local; não foi feito push nem publicação remota.
Na preparação futura, verificar que a tag anotada aponta exatamente ao commit
de release e que manifesto, catálogo, README e changelog concordam.

## Revisão por cinco especialistas

Os cinco especialistas revisaram o rascunho completo. Todas as correções
obrigatórias foram incorporadas; a melhoria opcional de aceite de teclado também.

| Especialidade | Ajustes incorporados |
| --- | --- |
| Execução e integração | Término de intenções, retry de lançamento com escopo exato, timeout/truncamento, contador de reaplicação, callbacks antigos e erros independentes |
| Algoritmo e foco | Alvo manual versus automático, uma retentativa, precedência do foco real, descarte com flutuante, geração de pausa, topologia incompleta e enquadramento em M5 |
| Configuração e persistência | Fonte da verdade, repetir salvamento pelo número ativo, resultados antigos e fallback sem escrita; após ajuste de escopo, gravação centralizada no serviço por workspace |
| UX e acessibilidade | Avisos independentes, instrução para salvar novamente, mensagem de foco flutuante, retomada sem falsa confirmação e aceite concreto de teclado/avisos longos |
| Testes e qualidade | Ambientes separados, drenagem limitada, lote único, relógio simulado, ressincronização comprovada, falhas intermediárias e evidências de conclusão/release |

Limitações mantidas explicitamente: o lote de ações não é atômico; o contrato
documentado de stream não detecta encerramento posterior; documentação atual
precisa ser conferida na versão mínima suportada; M5 só altera execução mediante
comprovação geométrica completa; mocks não substituem validação real de foco.
