class_name Figura
extends RefCounted

## Pintor parametrico. Nao existe nenhum asset no projeto: jogador, monstros e
## Cavaleiros saem todos daqui, do mesmo vocabulario visual (contorno preto,
## corpo curvado, olhos acesos). O que muda e porte, cor e numero de olhos.

const PX := 3.0   # 1.2: low-res. Tudo se alinha a esta grade.

static func _bloco(ci: CanvasItem, x: float, y: float, w: float, h: float, cor: Color) -> void:
	ci.draw_rect(Rect2(round(x / PX) * PX, round(y / PX) * PX,
			round(w / PX) * PX, round(h / PX) * PX), cor)

## Contorno grosso por fora do bloco - e o que da leitura em cima do chao escuro.
static func _bloco_c(ci: CanvasItem, x: float, y: float, w: float, h: float, cor: Color) -> void:
	_bloco(ci, x - PX, y - PX, w + PX * 2.0, h + PX * 2.0, Palette.CONTORNO)
	_bloco(ci, x, y, w, h, cor)

static func sombra(ci: CanvasItem, raio: float) -> void:
	ci.draw_circle(Vector2(0, 4), raio, Color(0, 0, 0, 0.38))

# --------------------------------------------------------------- CRIATURAS
## Monstro do bestiario (4). `t` anima o bamboleio; `fase_ataque` de 0 a 1
## estica o corpo pra frente durante o bote.
static func criatura(ci: CanvasItem, dados: Dictionary, mira: Vector2, t: float,
		fase_ataque: float = 0.0, alerta: int = 0) -> void:
	var cor: Color = dados.get("cor", Palette.CARNE)
	var porte: float = float(dados.get("porte", 1.0))
	var n_olhos: int = int(dados.get("olhos", 2))

	var largura := 15.0 * porte
	var altura := 21.0 * porte
	var bamboleio := sin(t * 7.0) * 1.2 * porte
	var avanco := fase_ataque * 5.0
	var lado := signf(mira.x) if absf(mira.x) > 0.05 else 1.0

	sombra(ci, largura * 0.78)

	# pernas curtas e tortas
	var passo := sin(t * 9.0) * 2.4
	_bloco_c(ci, -largura * 0.62, 0.0, largura * 0.42, 8.0 + passo, Palette.sombra(cor, 0.6))
	_bloco_c(ci, largura * 0.2, 0.0, largura * 0.42, 8.0 - passo, Palette.sombra(cor, 0.6))

	# tronco curvado pra frente
	var ty := -altura + bamboleio
	_bloco_c(ci, -largura * 0.5 + avanco * lado * 0.3, ty, largura, altura, cor)
	# nervura / costela clara
	_bloco(ci, -largura * 0.5 + avanco * lado * 0.3, ty + altura * 0.45,
			largura, PX, Palette.sombra(cor, 0.55))

	# bracos pendurados
	var braco_y := ty + altura * 0.25
	_bloco_c(ci, -largura * 0.5 - 4.0 + avanco * lado, braco_y, 4.0, altura * 0.6, Palette.sombra(cor, 0.72))
	_bloco_c(ci, largura * 0.5 + avanco * lado, braco_y, 4.0, altura * 0.6, Palette.sombra(cor, 0.72))

	# cabeca afundada nos ombros
	var cab_w := largura * 0.72
	var cab_h := 9.0 * porte
	var cx := -cab_w * 0.5 + avanco * lado * 0.6
	var cy := ty - cab_h + 2.0
	_bloco_c(ci, cx, cy, cab_w, cab_h, Palette.sombra(cor, 0.82))

	# olhos: o numero e a assinatura da especie (o Rastejador tem 6)
	var cor_olho := Palette.PUTRIDO if alerta == 0 else Palette.ALERTA
	var por_fila := maxi(1, int(ceil(float(n_olhos) / 2.0)))
	var idx := 0
	for fila in range(2):
		for i in range(por_fila):
			if idx >= n_olhos:
				break
			idx += 1
			var ox := cx + cab_w * (0.18 + 0.62 * (float(i) / maxf(1.0, float(por_fila - 1))))
			if por_fila == 1:
				ox = cx + cab_w * 0.5
			var oy := cy + cab_h * (0.28 + 0.34 * float(fila))
			_bloco(ci, ox - PX * 0.5 + lado * 1.5, oy, PX, PX, cor_olho)

	# 7.7: ponto de exclamacao no alerta, interrogacao na busca
	if alerta == 1:
		marca_alerta(ci, ty - cab_h - 14.0, Palette.ALERTA, true)
	elif alerta == 2:
		marca_alerta(ci, ty - cab_h - 14.0, Palette.BUSCA, false)

## 7.7: o ! da perseguicao e o ? da busca. Publica porque o Enemy tambem a
## chama quando desenha pela folha de sprites em vez de pelo Figura.criatura().
static func marca_alerta(ci: CanvasItem, y: float, cor: Color, exclamacao: bool) -> void:
	if exclamacao:
		_bloco_c(ci, -PX * 0.5, y, PX, 7.0, cor)
		_bloco_c(ci, -PX * 0.5, y + 9.0, PX, PX, cor)
	else:
		_bloco_c(ci, -PX * 0.5, y, PX * 2.0, PX, cor)
		_bloco_c(ci, PX * 0.5, y + PX, PX, PX * 2.0, cor)
		_bloco_c(ci, -PX * 0.5, y + PX * 3.0, PX, PX, cor)
		_bloco_c(ci, -PX * 0.5, y + PX * 5.0, PX, PX, cor)

## Corpo caido, esperando ser comido (3.3) ou inspecionado (5).
static func cadaver(ci: CanvasItem, dados: Dictionary, brilho: float) -> void:
	var cor: Color = dados.get("cor", Palette.CARNE)
	var porte: float = float(dados.get("porte", 1.0))
	var w := 24.0 * porte
	sombra(ci, w * 0.6)
	# poca de sangue
	ci.draw_circle(Vector2(0, 2), w * 0.62, Color(Palette.SANGUE.r, Palette.SANGUE.g, Palette.SANGUE.b, 0.5))
	_bloco_c(ci, -w * 0.5, -7.0, w, 9.0, Palette.sombra(cor, 0.62))
	_bloco_c(ci, -w * 0.5 - 5.0, -5.0, 6.0, 6.0, Palette.sombra(cor, 0.5))
	if brilho > 0.0:
		# pulso indicando que da para interagir
		var a := 0.25 + 0.35 * brilho
		ci.draw_circle(Vector2(0, -2), w * 0.85, Color(Palette.PUTRIDO.r, Palette.PUTRIDO.g, Palette.PUTRIDO.b, a * 0.35))

# ---------------------------------------------------------------- JOGADOR
## 1.1: voce acorda sem memoria e com fome. Um farrapo palido - o unico
## tom frio do mapa, para nunca se perder no meio dos monstros.
static func jogador(ci: CanvasItem, mira: Vector2, t: float, andando: bool,
		fase_ataque: float, pesado: bool, parry: bool, arma: String) -> void:
	var lado := signf(mira.x) if absf(mira.x) > 0.05 else 1.0
	var passo := (sin(t * 11.0) * 2.6) if andando else 0.0
	var bamboleio := (sin(t * 11.0) * 0.8) if andando else sin(t * 2.2) * 0.5

	sombra(ci, 11.0)

	# pernas
	_bloco_c(ci, -7.0, 0.0, 6.0, 9.0 + passo, Palette.TRAPO_ESC)
	_bloco_c(ci, 1.0, 0.0, 6.0, 9.0 - passo, Palette.TRAPO_ESC)

	# tronco em trapos
	var ty := -22.0 + bamboleio
	_bloco_c(ci, -8.0, ty, 16.0, 22.0, Palette.TRAPO)
	# faixa de pano rasgada
	_bloco(ci, -8.0, ty + 13.0, 16.0, PX, Palette.TRAPO_ESC)
	_bloco(ci, -8.0, ty + 4.0, 16.0, PX, Palette.sombra(Palette.TRAPO, 0.8))

	# bracos
	var by := ty + 5.0
	_bloco_c(ci, -12.0, by, 4.0, 13.0, Palette.PELE)
	_bloco_c(ci, 8.0, by, 4.0, 13.0, Palette.PELE)

	# cabeca
	var cy := ty - 10.0
	_bloco_c(ci, -6.0, cy, 12.0, 11.0, Palette.PELE)
	# cabelo emaranhado cobrindo a testa
	_bloco(ci, -6.0, cy, 12.0, 4.0, Palette.sombra(Palette.CARNE, 0.45))
	# olhos fundos
	_bloco(ci, -3.0 + lado * 1.2, cy + 5.0, PX, PX, Palette.CONTORNO)
	_bloco(ci, 1.0 + lado * 1.2, cy + 5.0, PX, PX, Palette.CONTORNO)

	if parry:
		_guarda(ci, mira)
	elif fase_ataque > 0.0:
		_golpe(ci, mira, fase_ataque, pesado, arma)
	elif arma != "":
		_arma_em_descanso(ci, lado, arma)

## Lamina atravessada na frente do corpo: a leitura de "estou aparando".
static func _guarda(ci: CanvasItem, mira: Vector2) -> void:
	var ang := mira.angle()
	var base := Vector2(cos(ang), sin(ang)) * 13.0 + Vector2(0, -12)
	var perp := Vector2(-sin(ang), cos(ang))
	var pts := PackedVector2Array([
		base + perp * 12.0, base - perp * 12.0,
		base - perp * 12.0 + Vector2(cos(ang), sin(ang)) * 4.0,
		base + perp * 12.0 + Vector2(cos(ang), sin(ang)) * 4.0,
	])
	ci.draw_colored_polygon(pts, Palette.LAMINA)
	ci.draw_circle(base, 15.0, Color(0.85, 0.85, 0.95, 0.16))

## Arco do golpe. `fase` de 0 (windup, lamina atras) a 1 (fim do corte).
static func _golpe(ci: CanvasItem, mira: Vector2, fase: float, pesado: bool, arma: String) -> void:
	var alcance: float = (Balance.ATK_FORTE["alcance"] if pesado else Balance.ATK_LEVE["alcance"])
	var arco: float = (Balance.ATK_FORTE["arco"] if pesado else Balance.ATK_LEVE["arco"])
	var ang0 := mira.angle() - arco * 0.5
	var ang := ang0 + arco * fase
	var pivo := Vector2(0, -12)
	var comp := alcance * (0.55 + 0.45 * fase)
	var largura := 5.0 if not pesado else 8.0
	if arma != "":
		comp *= 1.15
		largura += 2.0

	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-sin(ang), cos(ang))
	var ponta := pivo + dir * comp

	# rastro do corte
	var rastro := PackedVector2Array()
	var passos := 7
	for i in range(passos + 1):
		var f := float(i) / float(passos)
		var a := ang0 + arco * fase * f
		rastro.append(pivo + Vector2(cos(a), sin(a)) * comp * 0.92)
	for i in range(passos, -1, -1):
		var f2 := float(i) / float(passos)
		var a2 := ang0 + arco * fase * f2
		rastro.append(pivo + Vector2(cos(a2), sin(a2)) * comp * 0.45)
	if rastro.size() >= 3:
		var alpha := 0.30 * (1.0 - fase * 0.35)
		var cor_rastro := Palette.SANGUE_VIVO if pesado else Palette.LAMINA
		ci.draw_colored_polygon(rastro, Color(cor_rastro.r, cor_rastro.g, cor_rastro.b, alpha))

	# a lamina
	ci.draw_line(pivo + dir * 6.0, ponta, Palette.CONTORNO, largura + 2.0)
	ci.draw_line(pivo + dir * 6.0, ponta, Palette.LAMINA, largura)
	# guarda
	ci.draw_line(pivo + dir * 7.0 - perp * 4.0, pivo + dir * 7.0 + perp * 4.0, Palette.FERRO, 3.0)

static func _arma_em_descanso(ci: CanvasItem, lado: float, _arma: String) -> void:
	var x := 10.0 * lado
	ci.draw_line(Vector2(x, -6), Vector2(x + 3.0 * lado, -30), Palette.CONTORNO, 6.0)
	ci.draw_line(Vector2(x, -6), Vector2(x + 3.0 * lado, -30), Palette.LAMINA, 4.0)

# -------------------------------------------------------------- CAVALEIRO
## 5: um Cavaleiro precisa dominar a tela de relance. Moldura propria,
## quase o dobro do monstro comum.
static func cavaleiro(ci: CanvasItem, dados: Dictionary, mira: Vector2, t: float,
		fase_ataque: float, telegrafo: float) -> void:
	var cor: Color = dados.get("cor", Palette.SANGUE)
	var lado := signf(mira.x) if absf(mira.x) > 0.05 else 1.0
	var bamboleio := sin(t * 3.4) * 1.6

	sombra(ci, 22.0)

	# pernas em armadura
	_bloco_c(ci, -13.0, 0.0, 10.0, 15.0, Palette.sombra(Palette.FERRO, 0.7))
	_bloco_c(ci, 3.0, 0.0, 10.0, 15.0, Palette.sombra(Palette.FERRO, 0.7))

	# tronco largo
	var ty := -44.0 + bamboleio
	_bloco_c(ci, -17.0, ty, 34.0, 44.0, cor)
	_bloco(ci, -17.0, ty + 26.0, 34.0, PX, Palette.sombra(cor, 0.55))
	# manto sobre um ombro
	_bloco_c(ci, -21.0 * lado, ty + 2.0, 8.0, 34.0, Palette.sombra(cor, 0.5))

	# ombreiras
	_bloco_c(ci, -23.0, ty + 1.0, 9.0, 11.0, Palette.FERRO)
	_bloco_c(ci, 14.0, ty + 1.0, 9.0, 11.0, Palette.FERRO)

	# elmo sem rosto, so uma fresta acesa
	var cy := ty - 17.0
	_bloco_c(ci, -11.0, cy, 22.0, 18.0, Palette.sombra(Palette.FERRO, 0.85))
	_bloco(ci, -8.0 + lado * 2.0, cy + 7.0, 16.0, PX * 1.4, Palette.SANGUE_VIVO)
	# chifres
	_bloco_c(ci, -14.0, cy - 5.0, PX, 7.0, Palette.OSSO)
	_bloco_c(ci, 11.0, cy - 5.0, PX, 7.0, Palette.OSSO)

	# 5: todo golpe de Cavaleiro e mortal com resistencia < 100, entao
	# o telegrafo tem que ser impossivel de nao ver.
	if telegrafo > 0.0:
		var raio := 40.0 + 40.0 * telegrafo
		ci.draw_arc(Vector2(0, -20), raio, 0.0, TAU, 40,
				Color(Palette.ALERTA.r, Palette.ALERTA.g, Palette.ALERTA.b, 0.25 + 0.45 * telegrafo), 3.0)

	if fase_ataque > 0.0:
		_golpe_colossal(ci, mira, fase_ataque)
	else:
		# espada colossal apoiada no chao
		var x := 20.0 * lado
		ci.draw_line(Vector2(x, 4), Vector2(x - 6.0 * lado, -52), Palette.CONTORNO, 11.0)
		ci.draw_line(Vector2(x, 4), Vector2(x - 6.0 * lado, -52), Palette.FERRO, 8.0)

static func _golpe_colossal(ci: CanvasItem, mira: Vector2, fase: float) -> void:
	var arco := 2.6
	var ang0 := mira.angle() - arco * 0.5
	var ang := ang0 + arco * fase
	var pivo := Vector2(0, -22)
	var comp := 96.0
	var dir := Vector2(cos(ang), sin(ang))

	var rastro := PackedVector2Array()
	for i in range(11):
		var f := float(i) / 10.0
		var a := ang0 + arco * fase * f
		rastro.append(pivo + Vector2(cos(a), sin(a)) * comp)
	for i in range(10, -1, -1):
		var f2 := float(i) / 10.0
		var a2 := ang0 + arco * fase * f2
		rastro.append(pivo + Vector2(cos(a2), sin(a2)) * comp * 0.35)
	if rastro.size() >= 3:
		ci.draw_colored_polygon(rastro, Color(Palette.SANGUE_VIVO.r, Palette.SANGUE_VIVO.g,
				Palette.SANGUE_VIVO.b, 0.34))

	ci.draw_line(pivo + dir * 10.0, pivo + dir * comp, Palette.CONTORNO, 15.0)
	ci.draw_line(pivo + dir * 10.0, pivo + dir * comp, Palette.FERRO, 11.0)
