class_name SpriteCriatura
extends RefCounted

## Monstros e Cavaleiros desenhados a partir das folhas de sprite, no lugar do
## desenho por codigo do Figura.criatura() / Figura.cavaleiro().
##
## Mesmo contrato do SpriteJogador: quem acha cada figura e o
## scripts/tools/preparar_folha.gd, que grava um .json com a caixa apertada de
## cada boneco mais o centro dos pes. Aqui so se le esse arquivo.
##
## Sete dos quinze bichos tem folha utilizavel. Para os outros oito, desenhar()
## devolve false e o Enemy/Knight volta a se desenhar por codigo - o motivo de
## cada um esta anotado no ARQUIVO abaixo. O jogo nunca quebra por falta de
## asset, e nenhuma criatura fica invisivel.

## id do bestiario -> nome do arquivo gerado pela ferramenta. Nao da para
## derivar um do outro: o bestiario usa apelidos curtos ("vigia", "regen") e a
## folha veio com o nome de exibicao, espaco e cedilha inclusive.
const ARQUIVO := {
	"rastejador": "rastejador",
	"carniceiro": "carniceiro",
	"peleveloz": "pele veloz",
	"ambutcher": "ambutcher",
	"vigia": "vigia carniça",
	"aterror": "aterrorizador",
	"toxoplasma": "toxoplasma",
	"regen": "regenerador",
	"furioso": "furioso",
	"guerra": "guerra",
	"conquista": "conquista",
	"morte": "morte",
	"fome": "fome",
	"peste": "peste",
	# Sem folha utilizavel, todos continuam no desenho por codigo:
	#
	#   - deslizador: nao tem arte nenhuma na pasta.
	#
	# Nenhum deles quebra nada: o Enemy testa disponivel() e cai no
	# Figura.criatura() quando a folha nao existe.
}

## Altura em pixels de mundo para porte 1.0. Sai da mesma regua do jogador
## (SpriteJogador.ALTURA_ALVO = 40): o Figura.criatura() desenha ~31px de altura
## para porte 1.0, e o tile tem 48. Cada bicho multiplica isto pelo proprio
## porte, entao o Furioso (1.30) fica em 44px e o Rastejador (0.95) em 32px.
const ALTURA_BASE := 34.0
## O Cavaleiro e outra escala: o Figura.cavaleiro() desenha ~69px, e ele precisa
## continuar sendo o dobro do jogador para a ameaca do 5 se ler na tela.
const ALTURA_CAVALEIRO := 70.0

## Quais bandas da folha servem para que acao.
##
## "banda" e a linha; "de"/"ate" recortam as figuras dentro dela, da esquerda
## para a direita, na ordem em que a ferramenta achou. O recorte existe porque
## varias folhas poem duas acoes na MESMA linha - a do Rastejador tem "Lunge and
## Claw" e "Bite/Chomp" lado a lado, a da Vigia tem "Andar" e "Observar".
##
## "fps" > 0  : ciclo por tempo (parado, andar).
## "fps" == 0 : a animacao anda pelo PROGRESSO da acao (0..1), igual ao jogador:
##              o golpe do monstro tem 0.52s de telegrafo e 0.18s de impacto, e
##              um ciclo por relogio poria o bote na tela fora de hora.
const ANIMS := {
	# Idle(7) / Running(7) / Lunge+Bite(7) / Damage+Death(8)
	"rastejador": {
		"parado":  {"banda": 0, "de": 0, "ate": 6, "fps": 6.0},
		"andar":   {"banda": 1, "de": 0, "ate": 6, "fps": 11.0},
		"atacar":  {"banda": 2, "de": 3, "ate": 5, "fps": 0.0},
		"dano":    {"banda": 3, "de": 0, "ate": 0, "fps": 0.0},
		"morto":   {"banda": 3, "de": 7, "ate": 7, "fps": 0.0},
	},
	# REPOUSO(3) / MOVIMENTO(6) / ATAQUE(5) / DANO(+ rotulo)
	"carniceiro": {
		"parado":  {"banda": 0, "de": 0, "ate": 2, "fps": 5.0},
		"andar":   {"banda": 1, "de": 0, "ate": 5, "fps": 10.0},
		# a banda 2 contem a sequencia completa: preparacao, golpe de osso e
		# os dois impactos finais, sem incluir os rotulos da folha.
		"atacar":  {"banda": 2, "de": 0, "ate": 4, "fps": 0.0},
		# a fig 1 e a pose de dano boa, mas o rotulo "DANO" cai dentro dela; a
		# fig 3 e a mesma coisa com estrelas de atordoamento, e esta limpa.
		"dano":    {"banda": 3, "de": 3, "ate": 3, "fps": 0.0},
		# sem "morto": esta folha nao tem quadro de morte, so poses em pe.
	},
	# Andar(4)+Observar(3) / Ataque(4)+Habilidade(3) / Dano(2)+Morte(5)
	"vigia": {
		"parado":  {"banda": 0, "de": 4, "ate": 6, "fps": 5.0},
		"andar":   {"banda": 0, "de": 0, "ate": 3, "fps": 9.0},
		"atacar":  {"banda": 1, "de": 1, "ate": 3, "fps": 0.0},
		"dano":    {"banda": 2, "de": 0, "ate": 0, "fps": 0.0},
		"morto":   {"banda": 2, "de": 5, "ate": 5, "fps": 0.0},
	},
	# Idle(7) / Walk(8) / Aggressive+Charge(10) / Rage(10) / Roar(6) / Hurt+Death(10)
	"furioso": {
		"parado":  {"banda": 0, "de": 0, "ate": 6, "fps": 6.0},
		"andar":   {"banda": 1, "de": 0, "ate": 7, "fps": 12.0},
		# so a fig 0 pega o rotulo "Rage Attack (Primary)"
		"atacar":  {"banda": 3, "de": 1, "ate": 7, "fps": 0.0},
		"dano":    {"banda": 5, "de": 0, "ate": 0, "fps": 0.0},
		"morto":   {"banda": 5, "de": 9, "ate": 9, "fps": 0.0},
	},
	# Walk(5) / Dash+Slash(8) / Lunge+Death(12) - a folha tem um fundo com
	# grade e rotulos, entao usamos as faixas de corpo limpas na ordem correta.
	"peleveloz": {
		"parado":  {"banda": 0, "de": 0, "ate": 4, "fps": 6.0},
		"andar":   {"banda": 0, "de": 0, "ate": 4, "fps": 12.0},
		"atacar":  {"banda": 1, "de": 0, "ate": 3, "fps": 0.0},
		"investida": {"banda": 1, "de": 4, "ate": 7, "fps": 0.0},
		"dano":    {"banda": 2, "de": 0, "ate": 0, "fps": 0.0},
		"morto":   {"banda": 2, "de": 10, "ate": 10, "fps": 0.0},
	},
	# 2026-08: folhas novas para os 5 Cavaleiros (skins novas em assets/sprites,
	# preparadas por preparar_folha.gd + selecao manual - varias delas trazem a
	# folha inteira num grid 2D que a deteccao automatica de bandas nao separa
	# direito, entao os quadros abaixo foram escolhidos e recortados a mao).
	#
	# Guerra: cavaleiro sobre touro. idle(4) / andar de perfil(2) / golpe de
	# chicote em 3 tempos(3) / investida de touro(2) / morte(1).
	"guerra": {
		"parado":  {"banda": 0, "de": 0, "ate": 3, "fps": 5.0},
		"andar":   {"banda": 1, "de": 0, "ate": 1, "fps": 8.0},
		"atacar":  {"banda": 2, "de": 0, "ate": 2, "fps": 0.0},
		"investida": {"banda": 3, "de": 0, "ate": 1, "fps": 0.0},
		"morto":   {"banda": 4, "de": 0, "ate": 0, "fps": 0.0},
	},
	# Conquista: cavaleiro com garra colossal. Sem quadro de morte na folha -
	# cai no cadaver generico do Figura.
	"conquista": {
		"parado":  {"banda": 0, "de": 0, "ate": 3, "fps": 3.0},
		"andar":   {"banda": 0, "de": 0, "ate": 3, "fps": 9.0},
		"atacar":  {"banda": 1, "de": 0, "ate": 3, "fps": 0.0},
		"investida": {"banda": 2, "de": 0, "ate": 2, "fps": 0.0},
	},
	# Morte: ceifador flutuante. Flutua parado e andando (nao tem pernas), a
	# foice gira no ataque, o avanco vem da folha de "Forward Dash/Lunge"
	# (quadros de rastro de fumaca, nao do corpo solido - fiel a folha).
	# Sem quadro de morte na folha - cai no cadaver generico do Figura.
	"morte": {
		"parado":  {"banda": 0, "de": 0, "ate": 2, "fps": 3.0},
		"andar":   {"banda": 0, "de": 0, "ate": 2, "fps": 7.0},
		"atacar":  {"banda": 1, "de": 0, "ate": 2, "fps": 0.0},
		"investida": {"banda": 2, "de": 0, "ate": 2, "fps": 0.0},
	},
	# Fome: cavaleiro sobre corcel esqueletico. Sem pose parada na folha - o
	# ciclo de caminhada serve tambem de idle, so mais lento. Sem morte tambem.
	#
	# So entram os cavalos das tres primeiras fileiras. As poses empinadas da
	# ultima fileira sao lindas, mas tem o DOBRO da altura das outras, e a escala
	# da folha e uma so (altura_tipica) - usa-las faria o cavalo inchar na tela
	# no instante do ataque.
	"fome": {
		"parado":  {"banda": 0, "de": 0, "ate": 3, "fps": 3.0},
		"andar":   {"banda": 0, "de": 0, "ate": 3, "fps": 9.0},
		"atacar":  {"banda": 1, "de": 0, "ate": 1, "fps": 0.0},
		"investida": {"banda": 2, "de": 0, "ate": 1, "fps": 0.0},
	},
	# Peste: enxame de besouro com caveiras. "Walk" serve de parado/andar,
	# "Skull Bite" vira o ataque, "Charge" a investida, e os 2 primeiros
	# quadros de "Death" (corpo caido, poca derretida) o cadaver.
	#
	# O ataque comeca no 2o quadro da fileira: o 1o tem o rotulo "Skull Bite"
	# escrito dentro da caixa, e recorte e retangulo - a palavra ia junto.
	"peste": {
		"parado":  {"banda": 0, "de": 0, "ate": 2, "fps": 3.0},
		"andar":   {"banda": 0, "de": 0, "ate": 2, "fps": 9.0},
		"atacar":  {"banda": 1, "de": 0, "ate": 4, "fps": 0.0},
		"investida": {"banda": 2, "de": 0, "ate": 2, "fps": 0.0},
		"morto":   {"banda": 3, "de": 0, "ate": 1, "fps": 0.0},
	},
}

# ------------------------------------------------------------------ cache
## id -> {"tex": Texture2D, "bandas": Array, "escala": float} ou null quando a
## folha nao existe. Guardar o null tambem importa: sem isso o Deslizador
## tentaria abrir o arquivo que falta a cada quadro, de cada instancia.
static var _cache := {}

static func _folha(id: String) -> Variant:
	if _cache.has(id):
		return _cache[id]
	_cache[id] = null
	if not ARQUIVO.has(id):
		return null
	var base: String = ARQUIVO[id]

	# FileAccess + buffer em vez de load(): assim a folha funciona mesmo sem ter
	# passado pelo import do editor, que e o caso de um PNG recem-gerado.
	var fp := FileAccess.open("res://assets/sprites/%s.png" % base, FileAccess.READ)
	if fp == null:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(fp.get_buffer(fp.get_length())) != OK:
		fp.close()
		return null
	fp.close()

	var fj := FileAccess.open("res://assets/sprites/%s.json" % base, FileAccess.READ)
	if fj == null:
		return null
	var dados = JSON.parse_string(fj.get_as_text())
	fj.close()
	if typeof(dados) != TYPE_DICTIONARY or not dados.has("bandas"):
		return null

	var bandas := []
	for banda in dados["bandas"]:
		var linha := []
		for f in banda:
			linha.append({
				"r": Rect2(float(f["x"]), float(f["y"]), float(f["w"]), float(f["h"])),
				"ax": float(f["ax"]),
			})
		bandas.append(linha)

	# "altura_tipica" e a mediana das figuras; "altura_ref" e a mais alta.
	# Aqui vale a mediana: uma deteccao fundida na folha inflaria o maximo e
	# encolheria o bicho inteiro na tela. O SpriteJogador continua no maximo
	# porque foi calibrado contra ele.
	var ref := float(dados.get("altura_tipica", dados.get("altura_ref", 0)))
	_cache[id] = {
		"tex": ImageTexture.create_from_image(img),
		"bandas": bandas,
		"ref": ref if ref > 0.0 else 1.0,
	}
	return _cache[id]

static func disponivel(id: String) -> bool:
	return _folha(id) != null

## Faz recarregar na proxima chamada, para trocar folhas sem fechar o jogo.
static func esquecer() -> void:
	_cache.clear()

# --------------------------------------------------------------------- desenho
## Devolve false quando nao ha folha - o chamador entao se vira por codigo.
static func desenhar(ci: CanvasItem, id: String, anim: String, t: float,
		progresso: float, lado: float, altura: float,
		desloc: Vector2 = Vector2.ZERO) -> bool:
	var folha = _folha(id)
	if folha == null:
		return false
	var tabela: Dictionary = ANIMS.get(id, {})
	if not tabela.has(anim):
		# "morto" ausente NAO cai para "parado": a folha do Carniceiro nao tem
		# quadro de morte, e um cadaver desenhado de pe e pior que nenhum
		# cadaver. Devolver false manda o Enemy usar o Figura.cadaver().
		if anim == "morto":
			return false
		anim = "parado"
	if not tabela.has(anim):
		return false

	var d: Dictionary = tabela[anim]
	var bi := int(d["banda"])
	var bandas: Array = folha["bandas"]
	if bi < 0 or bi >= bandas.size():
		return false
	var banda: Array = bandas[bi]
	var de := clampi(int(d["de"]), 0, maxi(0, banda.size() - 1))
	var ate := clampi(int(d["ate"]), de, maxi(0, banda.size() - 1))
	var n := ate - de + 1
	if n <= 0:
		return false

	var idx := de
	var fps := float(d["fps"])
	if fps > 0.0:
		idx = de + (int(t * fps) % n)
	elif n > 1:
		idx = de + clampi(int(progresso * float(n)), 0, n - 1)

	var fig: Dictionary = banda[idx]
	var r: Rect2 = fig["r"]
	var ax: float = fig["ax"]
	var escala := altura / float(folha["ref"])

	# Mesma ancoragem do jogador: a origem do node e o pe do boneco, e o
	# deslocamento em X sai do centro dos pes, nao do centro da caixa - com a
	# garra esticada num bote a caixa cresce so de um lado, e ancorar pelo
	# centro dela faria o corpo deslizar a cada golpe.
	var espelho := -1.0 if lado < 0.0 else 1.0
	ci.draw_set_transform(desloc, 0.0, Vector2(escala * espelho, escala))
	ci.draw_texture_rect_region(folha["tex"],
			Rect2(-ax, -r.size.y, r.size.x, r.size.y), r)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true
