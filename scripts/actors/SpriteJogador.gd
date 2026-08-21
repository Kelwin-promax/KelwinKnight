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
##   - o tile tem 48px e os corredores 2 tiles (96px): um boneco de 35px anda
##     por eles; um de 106px e mais alto que a largura do corredor.
##   - ATK_LEVE.alcance = 46 (7.2): o golpe alcanca 1.3x a altura do corpo.
##     Com 106px o soco nao passaria do joelho do proprio jogador.
##   - a pose 'parado' da folha tem 102x242, entao nesta altura o corpo fica
##     com ~17px de largura. E esse numero, nao a altura, que Player.RAIO tem
##     de acompanhar para a hitbox coincidir com o desenho.
##
## Casar a ALTURA com o boneco de codigo e casar a LARGURA sao coisas
## diferentes: o desenho por codigo e atarracado (30px de largura para 35 de
## altura) e a folha e um humano de verdade (2.4:1). Quem manda aqui e a
## altura, porque e ela que se compara com o tile e com os monstros; a
## largura entra depois, pelo RAIO.
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
const ANIMS := {
	# banda 0 - ciclo de caminhada, 4 quadros
	"andar":        {"figs": [[0, 0], [0, 1], [0, 2], [0, 3]], "fps": 9.0},
	# a corrida reusa o ciclo mais rapido: a folha tem uma pose de corrida
	# (banda 1, figura 0), mas parada ela nao mexe as pernas.
	"correr":       {"figs": [[0, 0], [0, 1], [0, 2], [0, 3]], "fps": 14.0},
	# banda 1 - corrida, o salto com rastro de velocidade, a aterrissagem
	"dash":         {"figs": [[1, 1]], "fps": 0.0},
	# banda 2 - soco (armado -> estendido) e chute (joelho -> perna esticada)
	"ataque_leve":  {"figs": [[2, 0], [2, 1]], "fps": 0.0},
	"chute":        {"figs": [[2, 2], [2, 3]], "fps": 0.0},
	# banda 3 - golpe pesado, a pose parada e o recuo de quem levou dano
	"ataque_forte": {"figs": [[3, 0], [3, 1]], "fps": 0.0},
	"parado":       {"figs": [[3, 2]], "fps": 0.0},
	"dano":         {"figs": [[3, 3]], "fps": 0.0},
	# banda 4 - guarda e o corpo dobrado
	"parry":        {"figs": [[4, 0]], "fps": 0.0},
	"caido":        {"figs": [[4, 3]], "fps": 0.0},
}

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
