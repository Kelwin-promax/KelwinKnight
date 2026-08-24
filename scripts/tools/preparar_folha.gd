extends SceneTree

## Prepara folhas de sprite: tira o fundo, acha cada boneco e grava as medidas.
##
## As 14 folhas do projeto NAO seguem uma convencao so. Elas foram desenhadas
## separadamente e usam tres fundos diferentes:
##
##   - chapado, com as poses em linhas soltas  (Jogador, Rastejador, Carniceiro,
##     Fome, Guerra)
##   - celulas emolduradas sobre um painel     (Vigia, Morte, Regenerador,
##     Ambutcher, Furioso, Aterrorizador, Toxoplasma)
##   - xadrez de transparencia                 (Conquista, Pele Veloz)
##
## Por isso a limpeza tem tres estagios, cada um resolvendo um desses casos.
## Um estagio so nao da conta, e rodar todos em toda folha estraga as que ja
## estavam boas - dai as travas de JA_BOM/BOM_BASTA.
##
## 1. INUNDACAO a partir das bordas, nao "toda cor parecida com o fundo vira
##    transparente". A camisa do jogador e um cinza escuro a distancia 27 do
##    verde do fundo - um filtro global comeria o tronco. A inundacao so alcanca
##    o que esta ligado a borda, entao o interior do corpo esta a salvo por
##    construcao.
##
## 2. CORES CHAPADAS DOMINANTES, para o que a inundacao nao alcanca: o painel
##    dentro de uma celula emoldurada e o xadrez de transparencia sao ilhas,
##    cercadas pela moldura. Cada uma e uma cor so ocupando uma fatia grande do
##    que sobrou; o bicho e pixel art sombreada e nenhuma cor dele chega perto
##    dessa fatia.
##
## 3. COMPONENTES OCOS: a moldura da celula. Ela preenche so o proprio perimetro
##    - menos de 10% da caixa que ocupa, contra 30-60% de um boneco. Sem tirar a
##    moldura, ela ligaria a linha inteira e a projecao de colunas devolveria uma
##    figura so, do tamanho da fila.
##
## 4. As celulas NAO formam uma grade regular. Estas folhas sao desenhadas, nao
##    geradas por ferramenta de tileset: o salto do dash, por exemplo, atravessa
##    a fronteira de duas celulas de 200px. Fatiar em 4x5 fixo cortaria o boneco
##    ao meio. Entao cada figura e achada pela propria silhueta, por projecao de
##    linhas e colunas, e o resultado sai num .json que o jogo le.
##
## Roda offline, uma vez por folha nova:
##   godot --headless --path . --script res://scripts/tools/preparar_folha.gd

const PASTA := "res://assets/sprites"

## Distancia maxima por canal ate a cor do fundo para a inundacao seguir.
## O JPEG suja o fundo chapado, entao exigir igualdade exata nao funciona.
##
## 48, e nao 38: as folhas dos monstros tem vinheta, e o centro do painel fica a
## distancia 43 do canto quase preto. Com 38 sobrava uma ilha de fundo no meio,
## que encostava nos bichos e fundia a folha inteira num blob de 1335x629.
const TOL := 48
## Bandas/figuras menores que isto sao ruido de compressao, nao boneco.
const MIN_ALTURA_BANDA := 24
const MIN_LARGURA_FIG := 16
## Fatia de baixo da figura usada para achar o centro dos pes.
const FAIXA_PES := 0.12

# --------------------------------------------------- estagio 2: cor chapada
## Tolerancia ao apagar uma cor chapada dominante.
const TOL_CHAPADO := 18
## So vale apagar uma cor que cubra esta fatia do que sobrou.
const MIN_FRACAO := 0.04
const MAX_PASSES := 6
## Quantizacao do histograma que acha a cor dominante.
const QUANT := 8
## Folha que a inundacao ja limpou ate aqui dispensa o estagio 2 - rodar assim
## mesmo comeria os cinzas da roupa do jogador e quebraria as bandas dele.
const JA_BOM := 0.82
## ...e o estagio 2 para assim que chega aqui.
const BOM_BASTA := 0.88

# ------------------------------------- estagio 3: componentes que nao sao bicho
## Abaixo desta fracao da propria caixa, o componente e moldura, nao boneco.
const MIN_PREENCH := 0.10
## Caixa menor que isto nem e testada para moldura: e detalhe, nao moldura.
const MIN_CAIXA := 60

## NAO existe filtro de "componente pequeno = letra" aqui, e a tentacao e
## grande: varias folhas tem rotulo escrito dentro da banda dos bonecos ("GOLPE
## DE OSSO", na do Carniceiro), e recorte e retangulo, entao a palavra viaja
## junto para dentro do jogo.
##
## Nao funciona. Pixel art salva em JPEG chega aqui cheia de pedaco solto:
## perna que descolou do corpo, olho, ponta de cauda, respingo. Apagar todo
## componente de ate ~36px apagou 2350 pedacos na folha do Aterrorizador e
## derrubou a altura tipica do Guerra de 106px para 67px - o filtro comia o
## bicho, nao o rotulo. Rotulo dentro da banda fica; quem escolhe a figura
## limpa e a tabela do SpriteCriatura.ANIMS.

## Banda mais baixa que esta fracao da mais alta e rotulo escrito, nao pose.
const FRACAO_BANDA_UTIL := 0.45

## Coluna com POUCO pixel ainda conta como vao entre figuras (fracao da altura
## da banda). Zero = so coluna totalmente vazia separa, que e o comportamento
## historico.
##
## Existe por causa da SOMBRA. As folhas trazem uma elipse de sombra desenhada
## sob os pes, e quando os bonecos ficam lado a lado essa sombra vira uma faixa
## continua que costura a fileira inteira: na folha do jogador o ciclo de
## caminhada saiu como UM retangulo de 329x171 em vez de quatro poses. A sombra
## tem 4-6px de altura numa banda de ~180, entao uma coluna que so tem sombra
## fica em ~3% - enquanto qualquer coluna que pegue corpo passa de 25%. Cortar
## em 10% separa os bonecos e nao encosta em nenhum deles.
##
## Fica por folha, e nao global, de proposito: as outras 13 folhas ja tem o
## .json gravado e os indices delas estao escritos nas tabelas de ANIMS. Mudar
## a regra para todo mundo renumeraria figuras que ninguem pediu para mexer.
const VALE_POR_FOLHA := {"jogador": 0.10}

## Recortes que nenhuma regra automatica resolve, por folha e por "banda:figura".
## O valor e a faixa horizontal que fica, em fracao da largura achada.
##
## A "Headbutt" da folha do jogador nao e uma sequencia de poses: e o MESMO
## boneco desenhado duas vezes, espelhado, batendo cabeca com a propria imagem.
## Os dois se encostam exatamente no eixo do espelho, entao nao existe vale de
## densidade para cortar - o menor valor entre eles ainda e 55 de 153. Fica so a
## metade esquerda, que e a que olha para a direita, o lado padrao da folha.
const CORTES_MANUAIS := {
	"jogador": {"3:0": [0.0, 0.5]},
}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var alvos: Array[String] = []
	for a in args:
		if not a.begins_with("--"):
			alvos.append(a)
	if alvos.is_empty():
		var dir := DirAccess.open(PASTA)
		if dir != null:
			dir.list_dir_begin()
			var n := dir.get_next()
			while n != "":
				if n.to_lower().ends_with(".jpg") or n.to_lower().ends_with(".jpeg"):
					alvos.append(n.get_basename())
				n = dir.get_next()
	for nome in alvos:
		_preparar(nome)
	quit()

func _preparar(nome: String) -> void:
	print("\n================  ", nome, "  ================")
	var f := FileAccess.open("%s/%s.jpg" % [PASTA, nome], FileAccess.READ)
	if f == null:
		print("ERRO: nao consegui ler a folha")
		return
	var bytes := f.get_buffer(f.get_length())
	f.close()

	var img := Image.new()
	if img.load_jpg_from_buffer(bytes) != OK:
		print("ERRO: o arquivo nao decodificou como JPEG")
		return
	img.convert(Image.FORMAT_RGBA8)

	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	print("folha: %d x %d" % [w, h])

	_remover_fundo(d, w, h)
	_remover_chapados(d, w, h)
	var molduras := _remover_molduras(d, w, h)
	if molduras > 0:
		print("molduras de celula removidas: %d" % molduras)
	print("limpo no total: %.1f%%" % (100.0 * _fracao_vazia(d, w, h)))
	img.set_data(w, h, false, Image.FORMAT_RGBA8, d)

	var base := nome.to_lower()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [PASTA, base]))

	# versao de conferencia: o que foi removido aparece em magenta
	var dbg := d.duplicate()
	var i := 0
	while i < dbg.size():
		if dbg[i + 3] == 0:
			dbg[i] = 255
			dbg[i + 1] = 0
			dbg[i + 2] = 255
			dbg[i + 3] = 255
		i += 4
	var img_dbg := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, dbg)
	img_dbg.save_png(ProjectSettings.globalize_path("%s/_conferir_%s.png" % [PASTA, base]))

	# ------------------------------------------------------- achar os bonecos
	# Toda folha tem rotulo escrito ("Idle", "Running Cycle", o nome do bicho).
	# Texto sobrevive a limpeza - ele nao e fundo. Mas cai numa banda propria,
	# muito mais baixa que a dos bonecos, entao some por altura.
	var todas := _bandas(d, w, h)
	var mais_alta := 0
	for b in todas:
		mais_alta = maxi(mais_alta, (b as Vector2i).y - (b as Vector2i).x + 1)
	var bandas := []
	for b in todas:
		var bv: Vector2i = b
		if float(bv.y - bv.x + 1) >= FRACAO_BANDA_UTIL * float(mais_alta):
			bandas.append(bv)
		else:
			print("  banda de texto descartada (y %d..%d, %d px)" % [bv.x, bv.y,
					bv.y - bv.x + 1])

	var saida := {"textura": "%s/%s.png" % [PASTA, base], "bandas": []}
	var altura_ref := 0
	var alturas := PackedInt32Array()

	var vale := float(VALE_POR_FOLHA.get(base, 0.0))
	for bi in range(bandas.size()):
		var b: Vector2i = bandas[bi]
		var figs := _aplicar_cortes(d, w, base, bi, _figuras(d, w, b.x, b.y, vale))
		var lista := []
		var desc := PackedStringArray()
		for fg in figs:
			var r: Rect2i = fg
			altura_ref = maxi(altura_ref, r.size.y)
			alturas.append(r.size.y)
			var ax := _centro_dos_pes(d, w, r)
			lista.append({"x": r.position.x, "y": r.position.y,
					"w": r.size.x, "h": r.size.y, "ax": ax})
			desc.append("%dx%d" % [r.size.x, r.size.y])
		saida["bandas"].append(lista)
		print("  banda %d (y %d..%d): %d figuras  [%s]" % [bi, b.x, b.y,
				figs.size(), ", ".join(desc)])

	saida["altura_ref"] = altura_ref
	# A MEDIANA, e nao o maximo, e o que serve de regua para escalar o bicho no
	# jogo. Uma deteccao fundida - duas figuras que se encostaram e viraram uma -
	# infla o maximo e encolhe o bicho inteiro na tela: na folha do
	# Aterrorizador um blob de 188px punha todo o resto a 70% do tamanho certo.
	# A mediana nao se move por um outlier. `altura_ref` fica gravado do mesmo
	# jeito porque o SpriteJogador foi calibrado contra ele.
	alturas.sort()
	var tipica := altura_ref
	if alturas.size() > 0:
		tipica = alturas[alturas.size() / 2]
	saida["altura_tipica"] = tipica
	print("  altura de referencia: %d px (mais alto)  ·  %d px (tipica)"
			% [altura_ref, tipica])

	var jf := FileAccess.open("%s/%s.json" % [PASTA, base], FileAccess.WRITE)
	jf.store_string(JSON.stringify(saida, "\t"))
	jf.close()
	print("  gravado: %s.png + %s.json  (confira _conferir_%s.png)" % [base, base, base])

# ------------------------------------------------------------------ inundacao
func _remover_fundo(d: PackedByteArray, w: int, h: int) -> void:
	var fr := int(d[0])
	var fg := int(d[1])
	var fb := int(d[2])
	print("cor do fundo (canto): rgb(%d, %d, %d)" % [fr, fg, fb])
	var visto := PackedByteArray()
	visto.resize(w * h)
	var fila := PackedInt32Array()

	for x in range(w):
		_semear(d, visto, fila, x, 0, w, fr, fg, fb)
		_semear(d, visto, fila, x, h - 1, w, fr, fg, fb)
	for y in range(h):
		_semear(d, visto, fila, 0, y, w, fr, fg, fb)
		_semear(d, visto, fila, w - 1, y, w, fr, fg, fb)

	var qi := 0
	while qi < fila.size():
		var idx := fila[qi]
		qi += 1
		var x := idx % w
		var y := idx / w
		if x > 0:
			_semear(d, visto, fila, x - 1, y, w, fr, fg, fb)
		if x < w - 1:
			_semear(d, visto, fila, x + 1, y, w, fr, fg, fb)
		if y > 0:
			_semear(d, visto, fila, x, y - 1, w, fr, fg, fb)
		if y < h - 1:
			_semear(d, visto, fila, x, y + 1, w, fr, fg, fb)

	for j in range(w * h):
		if visto[j] == 1:
			d[j * 4 + 3] = 0
	print("fundo removido: %.1f%%" % (100.0 * float(fila.size()) / float(w * h)))

func _semear(d: PackedByteArray, visto: PackedByteArray, fila: PackedInt32Array,
		x: int, y: int, w: int, fr: int, fg: int, fb: int) -> void:
	var i := y * w + x
	if visto[i] == 1:
		return
	var b := i * 4
	if absi(int(d[b]) - fr) > TOL or absi(int(d[b + 1]) - fg) > TOL \
			or absi(int(d[b + 2]) - fb) > TOL:
		return
	visto[i] = 1
	fila.append(i)

# ------------------------------------------------ estagio 2: cores chapadas
func _fracao_vazia(d: PackedByteArray, w: int, h: int) -> float:
	var vazios := 0
	for j in range(w * h):
		if d[j * 4 + 3] == 0:
			vazios += 1
	return float(vazios) / float(w * h)

## Apaga, uma por vez, a cor dominante que sobrou - enquanto ela for chapada o
## bastante para ser painel de celula ou xadrez, e nunca corpo de boneco.
func _remover_chapados(d: PackedByteArray, w: int, h: int) -> void:
	if _fracao_vazia(d, w, h) >= JA_BOM:
		return
	for passo in range(MAX_PASSES):
		if _fracao_vazia(d, w, h) >= BOM_BASTA:
			return
		var hist := {}
		var vivos := 0
		for j in range(w * h):
			var b := j * 4
			if d[b + 3] == 0:
				continue
			vivos += 1
			var k := (int(d[b]) / QUANT) * 65536 + (int(d[b + 1]) / QUANT) * 256 \
					+ (int(d[b + 2]) / QUANT)
			hist[k] = int(hist.get(k, 0)) + 1
		if vivos == 0:
			return
		var melhor := -1
		var melhor_n := 0
		for k in hist:
			if int(hist[k]) > melhor_n:
				melhor_n = int(hist[k])
				melhor = int(k)
		if melhor < 0 or float(melhor_n) < MIN_FRACAO * float(vivos):
			return
		var cr := (melhor / 65536) * QUANT + QUANT / 2
		var cg := ((melhor / 256) % 256) * QUANT + QUANT / 2
		var cb := (melhor % 256) * QUANT + QUANT / 2
		var apagados := 0
		for j in range(w * h):
			var b := j * 4
			if d[b + 3] == 0:
				continue
			if absi(int(d[b]) - cr) <= TOL_CHAPADO \
					and absi(int(d[b + 1]) - cg) <= TOL_CHAPADO \
					and absi(int(d[b + 2]) - cb) <= TOL_CHAPADO:
				d[b + 3] = 0
				apagados += 1
		print("  cor chapada rgb(%d, %d, %d): %.1f%% da folha" % [cr, cg, cb,
				100.0 * float(apagados) / float(w * h)])
		if apagados == 0:
			return

# ------------------------------------------------ estagio 3: componente oco
## Apaga os componentes vazados - as molduras das celulas.
func _remover_molduras(d: PackedByteArray, w: int, h: int) -> int:
	var visto := PackedByteArray()
	visto.resize(w * h)
	var removidos := 0
	for j0 in range(w * h):
		if d[j0 * 4 + 3] == 0 or visto[j0] == 1:
			continue
		var fila := PackedInt32Array([j0])
		visto[j0] = 1
		var membros := PackedInt32Array()
		var minx := w
		var maxx := -1
		var miny := h
		var maxy := -1
		var qi := 0
		while qi < fila.size():
			var idx := fila[qi]
			qi += 1
			membros.append(idx)
			var x := idx % w
			var y := idx / w
			if x < minx: minx = x
			if x > maxx: maxx = x
			if y < miny: miny = y
			if y > maxy: maxy = y
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var nj := ny * w + nx
					if visto[nj] == 0 and d[nj * 4 + 3] > 0:
						visto[nj] = 1
						fila.append(nj)
		var bw := maxx - minx + 1
		var bh := maxy - miny + 1
		if bw < MIN_CAIXA or bh < MIN_CAIXA:
			continue
		# moldura: retangulo vazado, preenche so o proprio perimetro
		if float(membros.size()) < MIN_PREENCH * float(bw) * float(bh):
			for m in membros:
				d[m * 4 + 3] = 0
			removidos += 1
	return removidos

# ----------------------------------------------------------------- deteccao
## Faixas horizontais com pixel opaco, separadas por vao vazio.
func _bandas(d: PackedByteArray, w: int, h: int) -> Array:
	var out := []
	var ini := -1
	for y in range(h):
		var tem := false
		for x in range(w):
			if d[(y * w + x) * 4 + 3] > 8:
				tem = true
				break
		if tem and ini < 0:
			ini = y
		elif not tem and ini >= 0:
			if y - ini >= MIN_ALTURA_BANDA:
				out.append(Vector2i(ini, y - 1))
			ini = -1
	if ini >= 0 and h - ini >= MIN_ALTURA_BANDA:
		out.append(Vector2i(ini, h - 1))
	return out

## Aplica os CORTES_MANUAIS da folha. Um corte troca a figura por uma fatia dela,
## e nao cria figura nova - assim os indices que as tabelas de ANIMS ja citam
## continuam valendo.
func _aplicar_cortes(d: PackedByteArray, w: int, base: String, bi: int,
		figs: Array) -> Array:
	var tabela: Dictionary = CORTES_MANUAIS.get(base, {})
	if tabela.is_empty():
		return figs
	var out := []
	for fi in range(figs.size()):
		var r: Rect2i = figs[fi]
		var chave := "%d:%d" % [bi, fi]
		if not tabela.has(chave):
			out.append(r)
			continue
		var faixa: Array = tabela[chave]
		var x0 := r.position.x + int(float(r.size.x) * float(faixa[0]))
		var x1 := r.position.x + int(float(r.size.x) * float(faixa[1])) - 1
		# reaperta em Y: a fatia pode ser mais baixa que o bloco inteiro
		var novo := _apertar(d, w, x0, x1, r.position.y, r.position.y + r.size.y - 1)
		print("  corte manual %s: %dx%d -> %dx%d" % [chave, r.size.x, r.size.y,
				novo.size.x, novo.size.y])
		out.append(novo)
	return out

## Dentro de uma banda, cada boneco e um grupo de colunas com pixel opaco.
##
## `vale` afrouxa o que conta como vao: com 0.0 so uma coluna inteiramente vazia
## separa duas figuras; acima disso, uma coluna que mal tem pixel (a faixa de
## sombra entre dois bonecos) tambem separa. Ver VALE_POR_FOLHA.
func _figuras(d: PackedByteArray, w: int, y0: int, y1: int, vale: float = 0.0) -> Array:
	var out := []
	var ini := -1
	var limite := int(vale * float(y1 - y0 + 1))
	for x in range(w):
		var n := 0
		for y in range(y0, y1 + 1):
			if d[(y * w + x) * 4 + 3] > 8:
				n += 1
				if n > limite:
					break
		var tem := n > limite
		if tem and ini < 0:
			ini = x
		elif not tem and ini >= 0:
			if x - ini >= MIN_LARGURA_FIG:
				out.append(_aparar_moldura(d, w, _apertar(d, w, ini, x - 1, y0, y1)))
			ini = -1
	if ini >= 0 and w - ini >= MIN_LARGURA_FIG:
		out.append(_aparar_moldura(d, w, _apertar(d, w, ini, w - 1, y0, y1)))
	return out

## Corta a borda da moldura quando ela encosta no boneco.
##
## O estagio 3 so apaga molduras que ficaram soltas. Na folha do Ambutcher o
## boneco pisa na base da celula, entao moldura e boneco viram um componente so,
## com preenchimento alto - e a moldura sobrevive, emoldurando o monstro dentro
## do jogo. Aqui ela sai pela outra ponta: uma linha de moldura preenche quase
## toda a largura da caixa e tem vazio logo atras; nenhuma parte de um boneco
## faz isso.
const BORDA_CHEIA := 0.80
const BORDA_VAZIA := 0.30
const MAX_APARO := 4

func _aparar_moldura(d: PackedByteArray, w: int, r: Rect2i) -> Rect2i:
	var cx := r.position.x
	var cy := r.position.y
	var cw := r.size.x
	var ch := r.size.y
	for lado in range(4):
		for i in range(MAX_APARO):
			if cw < 8 or ch < 8:
				break
			var cheia := 0.0
			var atras := 0.0
			match lado:
				0:  # topo
					cheia = _densidade_linha(d, w, cx, cw, cy)
					atras = _densidade_linha(d, w, cx, cw, cy + 1)
				1:  # base
					cheia = _densidade_linha(d, w, cx, cw, cy + ch - 1)
					atras = _densidade_linha(d, w, cx, cw, cy + ch - 2)
				2:  # esquerda
					cheia = _densidade_coluna(d, w, cy, ch, cx)
					atras = _densidade_coluna(d, w, cy, ch, cx + 1)
				_:  # direita
					cheia = _densidade_coluna(d, w, cy, ch, cx + cw - 1)
					atras = _densidade_coluna(d, w, cy, ch, cx + cw - 2)
			if cheia < BORDA_CHEIA or atras > BORDA_VAZIA:
				break
			match lado:
				0: cy += 1; ch -= 1
				1: ch -= 1
				2: cx += 1; cw -= 1
				_: cw -= 1
	return Rect2i(cx, cy, cw, ch)

func _densidade_linha(d: PackedByteArray, w: int, x0: int, larg: int, y: int) -> float:
	var n := 0
	for x in range(x0, x0 + larg):
		if d[(y * w + x) * 4 + 3] > 8:
			n += 1
	return float(n) / float(maxi(1, larg))

func _densidade_coluna(d: PackedByteArray, w: int, y0: int, alt: int, x: int) -> float:
	var n := 0
	for y in range(y0, y0 + alt):
		if d[(y * w + x) * 4 + 3] > 8:
			n += 1
	return float(n) / float(maxi(1, alt))

func _apertar(d: PackedByteArray, w: int, x0: int, x1: int, y0: int, y1: int) -> Rect2i:
	var miny := y1
	var maxy := y0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if d[(y * w + x) * 4 + 3] > 8:
				if y < miny:
					miny = y
				if y > maxy:
					maxy = y
				break
	return Rect2i(x0, miny, x1 - x0 + 1, maxy - miny + 1)

## Centro horizontal dos pes. Ancorar pelo centro da caixa faria o corpo
## deslizar quando o braco estica num soco; o pe fica parado.
func _centro_dos_pes(d: PackedByteArray, w: int, r: Rect2i) -> int:
	var alt := maxi(1, int(float(r.size.y) * FAIXA_PES))
	var y0 := r.position.y + r.size.y - alt
	var minx := r.position.x + r.size.x
	var maxx := r.position.x
	for y in range(y0, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if d[(y * w + x) * 4 + 3] > 8:
				if x < minx:
					minx = x
				if x > maxx:
					maxx = x
	if maxx < minx:
		return r.size.x / 2
	return (minx + maxx) / 2 - r.position.x
