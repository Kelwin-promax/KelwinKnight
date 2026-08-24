class_name SpriteJogador
extends RefCounted

## O jogador desenhado a partir da folha de sprites, no lugar do desenho por
## codigo do Figura.jogador().
##
## As figuras nao vem de uma grade: quem acha cada boneco e o
## scripts/tools/preparar_folha.gd, que grava um .json com a caixa apertada de
## cada um mais o centro dos pes. Aqui so se le esse arquivo. Trocar a folha
## por uma redesenhada e rodar a ferramenta de novo - nada aqui muda.
##
## Se o .png ou o .json faltarem, desenhar() devolve false e o Player volta a
## se desenhar por codigo. O jogo nunca quebra por falta de asset.

const CAMINHO_PNG := "res://assets/sprites/jogador.png"
const CAMINHO_JSON := "res://assets/sprites/jogador.json"

## Altura do boneco em pixels de mundo, medida no boneco MAIS ALTO da folha.
##
## O numero sai do Figura.jogador(), que e o desenho por codigo que a folha
## substitui: tronco em ty=-22, cabeca em cy=ty-10 com 11 de altura, mais o
## contorno de PX - do pe ao topo da cabeca da ~35px. Ficar nessa altura e o
## que mantem tres relacoes de pe:
##
##   - o tile tem 48px e os corredores 2 tiles (96px): um boneco de ~37px anda
##     por eles; um de 106px e mais alto que a largura do corredor.
##   - ATK_JAB.alcance = 40 (7.2): o golpe alcanca ~1.1x a altura do corpo.
##     Com 106px o soco nao passaria do joelho do proprio jogador.
##   - a pose neutra da folha tem 111x172, entao nesta altura o corpo fica com
##     ~24px de largura - e isso ja contando braco balancando e a sombra que
##     veio desenhada no chao. O tronco em si e bem mais estreito, e e por ele
##     que Player.RAIO = 9 (caixa de 18px) se guia.
##
## A escala e UMA para a folha inteira e sai de `altura_ref`, que nesta folha e
## 186px - a banda dos chutes, com a perna esticada pra cima. Por isso ninguem
## chega a 40px na tela: o boneco em pe da ~37px, e o chute e que ocupa os 40.
## Escalar cada pose para uma altura fixa faria o personagem encolher e crescer
## a cada golpe.
##
## Casar a ALTURA com o boneco de codigo e casar a LARGURA sao coisas
## diferentes: o desenho por codigo e atarracado (30px de largura para 35 de
## altura) e a folha e um humano de verdade. Quem manda aqui e a altura, porque
## e ela que se compara com o tile e com os monstros; a largura entra depois,
## pelo RAIO.
const ALTURA_ALVO := 40.0

## Encosta o pe na sombra. A caixa e apertada no pixel, entao o acerto e fino.
const AJUSTE_Y := 3.0

# ------------------------------------------------------------------ animacoes
## acao -> [banda, figura] na folha. Banda e a linha; figura e a ordem da
## esquerda para a direita dentro dela, do jeito que a ferramenta achou.
##
## "fps" > 0  : ciclo por tempo (caminhar, correr).
## "fps" == 0 : a animacao anda pelo PROGRESSO da acao (0..1). Isso importa:
##              o windup do ataque leve e de 0.07s (7.2), e um ciclo por tempo
##              poria o quadro do soco na tela depois de ele ja ter acertado na
##              regra. Assim o braco estica no mesmo frame em que o dano sai.
## A folha tem 4 bandas, uma por fileira rotulada no desenho:
##
##   banda 0 (Movement, 12): 0-3 caminhada · 4-5 corrida · 6 dash · 7-11 pulo
##   banda 1 (Punches,  10): 0-2 jab · 3-4 direto · 5-6 cruzado · 7-9 uppercut
##   banda 2 (Kicks,     9): 0-1 chute · 2-4 chute alto · 5-6 chute giratorio
##                           · 7-8 sobra (7 vira a guarda do parry)
##   banda 3 (Strikes,   4): 0 cabecada · 1 joelhada · 2-3 cotovelada
##
## "fps" > 0  : ciclo por tempo (caminhar, correr).
## "fps" == 0 : a animacao anda pelo PROGRESSO da acao (0..1).
##
## "golpe" e o indice do quadro em que o punho/pe CHEGA. Ele existe porque a
## folha nao desenha as sequencias todas na mesma ordem: no jab o quadro do
## impacto e o primeiro e os outros dois sao a recomposicao da guarda, enquanto
## no chute alto o impacto e o ultimo dos tres. Sem essa marca, um progresso
## linear poria a perna esticada 0.15s DEPOIS de o dano ja ter saido no chute
## alto - ver progresso_de_ataque().
const ANIMS := {
	# ------------------------------------------------------------ deslocamento
	"andar":         {"figs": [[0, 0], [0, 1], [0, 2], [0, 3]], "fps": 9.0},
	# a folha tem um ciclo de corrida proprio, de 2 quadros
	"correr":        {"figs": [[0, 4], [0, 5]], "fps": 11.0},
	"dash":          {"figs": [[0, 6]], "fps": 0.0},
	# o pulo anda pelo PROGRESSO do salto: agacha, sobe, apoga, cai, aterrissa
	"pulo":          {"figs": [[0, 7], [0, 8], [0, 9], [0, 10], [0, 11]], "fps": 0.0},
	# ------------------------------------------------------------------ socos
	"jab":           {"figs": [[1, 0], [1, 1], [1, 2]], "fps": 0.0, "golpe": 0},
	"direto":        {"figs": [[1, 3], [1, 4]], "fps": 0.0, "golpe": 1},
	"cruzado":       {"figs": [[1, 5], [1, 6]], "fps": 0.0, "golpe": 0},
	"uppercut":      {"figs": [[1, 7], [1, 8], [1, 9]], "fps": 0.0, "golpe": 1},
	# ----------------------------------------------------------------- chutes
	"chute":         {"figs": [[2, 0], [2, 1]], "fps": 0.0, "golpe": 1},
	"chute_alto":    {"figs": [[2, 2], [2, 3], [2, 4]], "fps": 0.0, "golpe": 2},
	"chute_giro":    {"figs": [[2, 5], [2, 6]], "fps": 0.0, "golpe": 1},
	# ------------------------------------------------------- golpes corporais
	# A "Headbutt" da folha e o mesmo boneco duas vezes, espelhado, batendo
	# cabeca consigo mesmo; preparar_folha.gd corta a metade esquerda. Sobra um
	# quadro so - e a joelhada tambem so tem um.
	"cabecada":      {"figs": [[3, 0]], "fps": 0.0},
	"joelhada":      {"figs": [[3, 1]], "fps": 0.0},
	"cotovelada":    {"figs": [[3, 2], [3, 3]], "fps": 0.0, "golpe": 1},
	# ---------------------------------------------------------------- estados
	# A folha e de golpes: nao tem pose de parado, de guarda nem de queda. Cada
	# estado pega emprestada a que le mais parecido:
	#   parado -> a guarda de punhos erguidos do jab. Um quadro de caminhada
	#             solto parece passo congelado; a guarda parece espera.
	#   parry  -> a guarda de bracos altos que sobrou da fileira de chutes,
	#             a unica em que os dois bracos cobrem o rosto.
	#   dano   -> a guarda encolhida do jab (a mais baixa das tres).
	#   caido  -> o agachamento do pulo, o corpo mais dobrado da folha. O caido
	#             ainda ganha rotacao e deslocamento no Player, entao os dois
	#             nao se confundem na tela.
	"parado":        {"figs": [[1, 1]], "fps": 0.0},
	"parry":         {"figs": [[2, 7]], "fps": 0.0},
	"dano":          {"figs": [[1, 2]], "fps": 0.0},
	"caido":         {"figs": [[0, 7]], "fps": 0.0},
}

## Progresso que poe o quadro do impacto na tela no instante em que o dano sai.
##
## Os quadros ANTES do golpe se espalham pelo windup; do golpe em diante, pela
## recuperacao. Com "golpe" = 0 nao ha o que mostrar antes, e o quadro do
## impacto ja entra no primeiro frame da acao.
static func progresso_de_ataque(anim: String, t: float, windup: float,
		recup: float) -> float:
	var d: Dictionary = ANIMS.get(anim, {})
	var figs: Array = d.get("figs", [])
	var n := figs.size()
	if n <= 1:
		return 0.0
	var g := clampi(int(d.get("golpe", n - 1)), 0, n - 1)
	if t < windup and g > 0:
		var f := clampf(t / maxf(0.001, windup), 0.0, 0.9999)
		return f * float(g) / float(n)
	var r := clampf((t - windup) / maxf(0.001, recup), 0.0, 0.9999)
	return (float(g) + r * float(n - g)) / float(n)

static var _tex: Texture2D = null
static var _bandas: Array = []
static var _escala: float = 1.0
static var _tentou: bool = false

# ---------------------------------------------------------------- carregamento
static func _carregar() -> bool:
	if _tentou:
		return _tex != null
	_tentou = true

	# FileAccess + buffer em vez de load(): assim a folha funciona mesmo sem
	# ter passado pelo import do editor, que e o caso de um PNG recem-gerado.
	var fp := FileAccess.open(CAMINHO_PNG, FileAccess.READ)
	if fp == null:
		return false
	var img := Image.new()
	if img.load_png_from_buffer(fp.get_buffer(fp.get_length())) != OK:
		fp.close()
		return false
	fp.close()

	var fj := FileAccess.open(CAMINHO_JSON, FileAccess.READ)
	if fj == null:
		return false
	var dados = JSON.parse_string(fj.get_as_text())
	fj.close()
	if typeof(dados) != TYPE_DICTIONARY or not dados.has("bandas"):
		return false

	_bandas = []
	for banda in dados["bandas"]:
		var linha := []
		for f in banda:
			linha.append({
				"r": Rect2(float(f["x"]), float(f["y"]), float(f["w"]), float(f["h"])),
				"ax": float(f["ax"]),
			})
		_bandas.append(linha)

	# Uma escala unica para a folha inteira, tirada do boneco mais alto. Escalar
	# cada quadro para uma altura fixa faria o personagem encolher e crescer
	# entre poses - agachar tem que parecer agachar.
	var ref := float(dados.get("altura_ref", 0))
	_escala = ALTURA_ALVO / ref if ref > 0.0 else 1.0

	_tex = ImageTexture.create_from_image(img)
	return true

static func disponivel() -> bool:
	return _carregar()

## Faz recarregar na proxima chamada. Serve para trocar a folha sem fechar o
## jogo depois de rodar a ferramenta de novo.
static func esquecer() -> void:
	_tex = null
	_bandas = []
	_tentou = false

# --------------------------------------------------------------------- desenho
## Devolve false quando nao ha folha - o chamador entao se vira por codigo.
static func desenhar(ci: CanvasItem, anim: String, t: float, progresso: float,
		lado: float, rot: float = 0.0, desloc: Vector2 = Vector2.ZERO) -> bool:
	if not _carregar():
		return false

	var d: Dictionary = ANIMS.get(anim, ANIMS["parado"])
	var figs: Array = d["figs"]
	if figs.is_empty():
		return false

	var idx := 0
	var fps := float(d["fps"])
	if fps > 0.0:
		idx = int(t * fps) % figs.size()
	elif figs.size() > 1:
		idx = clampi(int(progresso * float(figs.size())), 0, figs.size() - 1)

	var par: Array = figs[idx]
	var bi := int(par[0])
	var fi := int(par[1])
	if bi < 0 or bi >= _bandas.size():
		return false
	var banda: Array = _bandas[bi]
	if fi < 0 or fi >= banda.size():
		return false

	var fig: Dictionary = banda[fi]
	var r: Rect2 = fig["r"]
	var ax: float = fig["ax"]

	# A origem do node e o pe do boneco. A caixa e posta de -altura ate 0 no
	# eixo Y e deslocada em X pelo centro dos pes, nao pelo centro da caixa:
	# com o braco esticado num soco a caixa cresce so de um lado, e ancorar
	# pelo centro dela faria o corpo deslizar a cada golpe.
	var espelho := -1.0 if lado < 0.0 else 1.0
	ci.draw_set_transform(desloc, rot, Vector2(_escala * espelho, _escala))
	ci.draw_texture_rect_region(_tex,
			Rect2(-ax, -r.size.y + AJUSTE_Y / _escala, r.size.x, r.size.y), r)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true

## Toda figura citada na tabela existe de fato na folha?
static func tabela_valida() -> bool:
	if not _carregar():
		return false
	for nome in ANIMS:
		for par in ANIMS[nome]["figs"]:
			var bi := int(par[0])
			if bi < 0 or bi >= _bandas.size():
				return false
			if int(par[1]) < 0 or int(par[1]) >= (_bandas[bi] as Array).size():
				return false
	return true
