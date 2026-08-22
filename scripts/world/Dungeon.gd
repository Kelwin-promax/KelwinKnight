class_name Dungeon
extends RefCounted

## 9: o Submundo e UM mapa grande e continuo, de 15 a 20 salas.
## Geracao pura, sem canvas: da mesma semente sai sempre a mesma planta,
## entao uma morte injusta e investigavel.

const TILE := 48
const PAREDE := 0
const CHAO := 1

var largura: int
var altura: int
var tiles: PackedByteArray
var salas: Array[Rect2i] = []
var semente: int

func _init(p_semente: int = 0) -> void:
	semente = p_semente if p_semente != 0 else randi()
	_gerar()

# ------------------------------------------------------------------ geracao
func _gerar() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = semente

	# 9: mapa aberto, sem paredes nem corredores. As salas continuam sendo
	# pontos de referencia para distribuicao de entidades.
	largura = 128
	altura = 92
	tiles = PackedByteArray()
	tiles.resize(largura * altura)
	tiles.fill(CHAO)

	var alvo := rng.randi_range(15, 20)   # 9: 15-20 salas
	var tentativas := 0
	while salas.size() < alvo and tentativas < 4000:
		tentativas += 1
		var w := rng.randi_range(6, 10)
		var h := rng.randi_range(5, 9)
		var x := rng.randi_range(2, largura - w - 3)
		var y := rng.randi_range(2, altura - h - 3)
		var nova := Rect2i(x, y, w, h)
		# uma folga de 2 tiles evita salas coladas virando um salao so
		var folgada := Rect2i(x - 2, y - 2, w + 4, h + 4)
		var colide := false
		for s in salas:
			if folgada.intersects(s):
				colide = true
				break
		if colide:
			continue
		salas.append(nova)
	# Os pontos acima preservam a distribuicao deterministica dos spawns, mas
	# a geometria inteira permanece aberta para o jogador atravessar livremente.

func _escavar_sala(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_marcar(x, y, CHAO)

func _corredor(de: Vector2i, ate: Vector2i, rng: RandomNumberGenerator) -> void:
	# Corredor em L, com 2 tiles de largura: o Carniceiro Osseo e largo e
	# precisa passar sem entalar.
	if rng.randi() % 2 == 0:
		_faixa_h(de.x, ate.x, de.y)
		_faixa_v(de.y, ate.y, ate.x)
	else:
		_faixa_v(de.y, ate.y, de.x)
		_faixa_h(de.x, ate.x, ate.y)

func _faixa_h(x0: int, x1: int, y: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		_marcar(x, y, CHAO)
		_marcar(x, y + 1, CHAO)

func _faixa_v(y0: int, y1: int, x: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		_marcar(x, y, CHAO)
		_marcar(x + 1, y, CHAO)

func _selar_borda() -> void:
	for x in range(largura):
		_marcar(x, 0, PAREDE)
		_marcar(x, altura - 1, PAREDE)
	for y in range(altura):
		_marcar(0, y, PAREDE)
		_marcar(largura - 1, y, PAREDE)

func _marcar(x: int, y: int, v: int) -> void:
	if x < 0 or y < 0 or x >= largura or y >= altura:
		return
	tiles[y * largura + x] = v

# ------------------------------------------------------------------ consulta
func solido(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= largura or y >= altura:
		return true
	return tiles[y * largura + x] == PAREDE

func solido_em(p: Vector2) -> bool:
	return solido(int(floor(p.x / TILE)), int(floor(p.y / TILE)))

func centro_do_tile(x: int, y: int) -> Vector2:
	return Vector2((float(x) + 0.5) * TILE, (float(y) + 0.5) * TILE)

func tamanho_px() -> Vector2:
	return Vector2(float(largura * TILE), float(altura * TILE))

## Um ponto de chao aleatorio, opcionalmente longe de `evitar`.
func chao_aleatorio(rng: RandomNumberGenerator, evitar: Vector2 = Vector2.INF,
		dist_min: float = 0.0) -> Vector2:
	for i in range(300):
		var s := salas[rng.randi_range(0, salas.size() - 1)]
		var x := rng.randi_range(s.position.x, s.end.x - 1)
		var y := rng.randi_range(s.position.y, s.end.y - 1)
		if solido(x, y):
			continue
		var p := centro_do_tile(x, y)
		if evitar != Vector2.INF and p.distance_to(evitar) < dist_min:
			continue
		return p
	return centro_do_tile(salas[0].get_center().x, salas[0].get_center().y)

# ---------------------------------------------------------------- colisao
## Move um corpo circular resolvendo eixo por eixo. Separar X de Y e o que
## permite deslizar pela parede em vez de grudar nela.
func mover(pos: Vector2, passo: Vector2, raio: float) -> Vector2:
	var p := pos
	p.x = _eixo(p, Vector2(passo.x, 0.0), raio).x
	p.y = _eixo(p, Vector2(0.0, passo.y), raio).y
	return p

func _eixo(pos: Vector2, passo: Vector2, raio: float) -> Vector2:
	var alvo := pos + passo
	# amostra os 4 cantos da pegada; se qualquer um entra em pedra, cancela o eixo
	var cantos := [
		Vector2(alvo.x - raio, alvo.y - raio),
		Vector2(alvo.x + raio, alvo.y - raio),
		Vector2(alvo.x - raio, alvo.y + raio),
		Vector2(alvo.x + raio, alvo.y + raio),
	]
	for c in cantos:
		if solido_em(c):
			return pos
	return alvo

## 7.7: o cone de visao nao atravessa pedra. Passo curto o bastante
## para nao pular um tile inteiro na diagonal.
func linha_livre(de: Vector2, ate: Vector2) -> bool:
	var d := ate - de
	var dist := d.length()
	if dist < 0.001:
		return true
	var passos := int(dist / (float(TILE) * 0.4)) + 1
	var inc := d / float(passos)
	var p := de
	for i in range(passos):
		p += inc
		if solido_em(p):
			return false
	return true

## Sala que contem o ponto, ou -1 se e corredor.
func sala_em(p: Vector2) -> int:
	var t := Vector2i(int(p.x / TILE), int(p.y / TILE))
	for i in range(salas.size()):
		if salas[i].has_point(t):
			return i
	return -1
