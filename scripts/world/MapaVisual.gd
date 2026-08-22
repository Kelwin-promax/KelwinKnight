class_name MapaVisual
extends Node2D

## Desenha a planta do Submundo uma vez so. O mapa nao muda durante a run,
## entao `_draw` roda uma vez e o Godot reaproveita a lista de comandos.

const FUNDO_SUBMUNDO := preload("res://assets/Submundo.png")
const TILE_SHEET := preload("res://assets/tilesheet_submundo.svg")
const TILE_SHEET_TILE := 48
const DECO_VOID := Vector2i(4, 0)
const DECO_LAVA := Vector2i(5, 0)
const DECO_LAVA_CORE := Vector2i(1, 1)
const DECO_ROOTS := Vector2i(2, 1)
const DECO_ALTAR := Vector2i(3, 1)
const DECO_WATER := Vector2i(4, 1)
const DECO_EDGE := Vector2i(5, 1)

var dungeon: Dungeon
var _rng := RandomNumberGenerator.new()
var _deco: Dictionary = {}

func configurar(p_dungeon: Dungeon) -> void:
	dungeon = p_dungeon
	_rng.seed = dungeon.semente
	_gerar_deco()
	queue_redraw()

func _draw() -> void:
	if dungeon == null:
		return
	var T := float(Dungeon.TILE)
	var tamanho := dungeon.tamanho_px()
	draw_texture_rect(FUNDO_SUBMUNDO, Rect2(Vector2.ZERO, tamanho), false)

	for y in range(dungeon.altura):
		for x in range(dungeon.largura):
			var px := float(x) * T
			var py := float(y) * T
			if dungeon.solido(x, y):
				_desenhar_tile(px, py, 2, 0, 0.92)
				_parede(x, y, px, py, T)
				continue
			_desenhar_tile(px, py, 0 if (x + y) % 2 == 0 else 1, 0, 0.88)
			var pos := Vector2i(x, y)
			if _deco.has(pos):
				var d: Vector2i = _deco[pos]
				_desenhar_tile(px, py, d.x, d.y, 0.90)
			else:
				_chao(x, y, px, py, T)
				_caracaca(x, y, px, py, T)

	for pos in _deco:
		var d: Vector2i = _deco[pos]
		if d == DECO_LAVA or d == DECO_LAVA_CORE:
			var cx := float(pos.x) * T + T * 0.5
			var cy := float(pos.y) * T + T * 0.5
			var raio := T * 2.0 if d == DECO_LAVA_CORE else T * 1.3
			draw_circle(Vector2(cx, cy), raio, Color(1.0, 0.4, 0.1, 0.07))
		elif d == DECO_ALTAR:
			var cx := float(pos.x) * T + T * 0.5
			var cy := float(pos.y) * T + T * 0.5
			draw_circle(Vector2(cx, cy), T * 1.5, Color(1.0, 0.5, 0.15, 0.05))

func _gerar_deco() -> void:
	_deco.clear()
	# Void border: the map fades into darkness at the edges
	for x in range(dungeon.largura):
		_deco[Vector2i(x, 0)] = DECO_VOID
		_deco[Vector2i(x, 1)] = DECO_EDGE
		_deco[Vector2i(x, dungeon.altura - 1)] = DECO_VOID
		_deco[Vector2i(x, dungeon.altura - 2)] = DECO_EDGE
	for y in range(dungeon.altura):
		_deco[Vector2i(0, y)] = DECO_VOID
		_deco[Vector2i(1, y)] = DECO_EDGE
		_deco[Vector2i(dungeon.largura - 1, y)] = DECO_VOID
		_deco[Vector2i(dungeon.largura - 2, y)] = DECO_EDGE

	# Roots creeping in from the border
	for x in range(2, dungeon.largura - 2):
		if _hash(x, 2) % 5 == 0:
			_deco[Vector2i(x, 2)] = DECO_ROOTS
		if _hash(x, dungeon.altura - 3) % 5 == 0:
			_deco[Vector2i(x, dungeon.altura - 3)] = DECO_ROOTS
	for y in range(2, dungeon.altura - 2):
		if _hash(2, y) % 5 == 0:
			_deco[Vector2i(2, y)] = DECO_ROOTS
		if _hash(dungeon.largura - 3, y) % 5 == 0:
			_deco[Vector2i(dungeon.largura - 3, y)] = DECO_ROOTS

	# Lava pools scattered between rooms
	var n_lava := _rng.randi_range(6, 10)
	for _i in range(n_lava):
		_colocar_lava()

	# Altars in ~25% of rooms
	for i in range(dungeon.salas.size()):
		var s := dungeon.salas[i]
		if _hash(s.position.x, s.position.y) % 4 == 0:
			var cx := s.position.x + s.size.x / 2
			var cy := s.position.y + s.size.y / 2
			if not _deco.has(Vector2i(cx, cy)):
				_deco[Vector2i(cx, cy)] = DECO_ALTAR

	# Water puddles
	var n_water := _rng.randi_range(10, 15)
	for _i in range(n_water):
		var wx := _rng.randi_range(4, dungeon.largura - 5)
		var wy := _rng.randi_range(4, dungeon.altura - 5)
		if not _deco.has(Vector2i(wx, wy)):
			_deco[Vector2i(wx, wy)] = DECO_WATER
			if _rng.randi() % 3 == 0:
				var dx := _rng.randi_range(-1, 1)
				var dy := _rng.randi_range(-1, 1)
				var adj := Vector2i(wx + dx, wy + dy)
				if not _deco.has(adj):
					_deco[adj] = DECO_WATER

func _colocar_lava() -> void:
	for _tentativa in range(20):
		var lx := _rng.randi_range(6, dungeon.largura - 7)
		var ly := _rng.randi_range(6, dungeon.altura - 7)
		var em_sala := false
		for s in dungeon.salas:
			if Rect2i(s.position - Vector2i(3, 3), s.size + Vector2i(6, 6)).has_point(Vector2i(lx, ly)):
				em_sala = true
				break
		if em_sala or _deco.has(Vector2i(lx, ly)):
			continue
		_deco[Vector2i(lx, ly)] = DECO_LAVA_CORE
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			if _rng.randi() % 3 != 0:
				var p := Vector2i(lx + d.x, ly + d.y)
				if not _deco.has(p):
					_deco[p] = DECO_LAVA
		return

func _desenhar_tile(px: float, py: float, coluna: int, linha: int, opacidade: float) -> void:
	var origem := Rect2(coluna * TILE_SHEET_TILE, linha * TILE_SHEET_TILE,
			TILE_SHEET_TILE, TILE_SHEET_TILE)
	draw_texture_rect_region(TILE_SHEET, Rect2(px, py, Dungeon.TILE, Dungeon.TILE), origem,
			Color(1.0, 1.0, 1.0, opacidade))

func _chao(x: int, y: int, px: float, py: float, T: float) -> void:
	# xadrez sutil: da escala sem virar tabuleiro
	var base := Palette.CHAO if ((x + y) % 2 == 0) else Palette.CHAO_ALT
	draw_rect(Rect2(px, py, T, T), Color(base.r, base.g, base.b, 0.18))

	# sujeira determinista - o mesmo tile suja sempre igual
	var h := _hash(x, y)
	if h % 11 == 0:
		var s := float(h % 7) + 4.0
		draw_rect(Rect2(px + float(h % 20), py + float((h / 3) % 20), s, s),
				Palette.sombra(base, 0.82))
	if h % 37 == 0:
		# mancha de sangue seco
		draw_circle(Vector2(px + T * 0.5, py + T * 0.5), T * 0.28,
				Color(0.38, 0.035, 0.12, 0.72))

	# Sombra de contato: o chao escurece encostado na pedra. E isso, mais que
	# a cor da parede, que faz a planta do mapa aparecer em vista 3/4.
	var sombra := Color(0, 0, 0, 0.22)
	if dungeon.solido(x, y - 1):
		draw_rect(Rect2(px, py, T, 7.0), sombra)
	if dungeon.solido(x - 1, y):
		draw_rect(Rect2(px, py, 5.0, T), sombra)
	if dungeon.solido(x + 1, y):
		draw_rect(Rect2(px + T - 5.0, py, 5.0, T), sombra)

func _caracaca(x: int, y: int, px: float, py: float, T: float) -> void:
	var h := _hash(x, y)
	if h % 173 != 0:
		return
	var centro := Vector2(px + T * 0.5, py + T * 0.52)
	var rot := -0.35 if h % 2 == 0 else 0.35
	draw_set_transform(centro, rot, Vector2.ONE)
	_desenhar_elipse(Vector2.ZERO, Vector2(15.0, 7.0), Color(0.12, 0.045, 0.12, 0.95))
	draw_circle(Vector2(14.0, -1.0), 5.0, Color(0.20, 0.07, 0.15, 0.98))
	draw_line(Vector2(-12.0, -3.0), Vector2(-23.0, -10.0), Color(0.10, 0.035, 0.10, 0.95), 3.0)
	draw_line(Vector2(-10.0, 3.0), Vector2(-22.0, 10.0), Color(0.10, 0.035, 0.10, 0.95), 3.0)
	draw_line(Vector2(5.0, -5.0), Vector2(18.0, -12.0), Color(0.10, 0.035, 0.10, 0.95), 3.0)
	draw_line(Vector2(5.0, 5.0), Vector2(18.0, 12.0), Color(0.10, 0.035, 0.10, 0.95), 3.0)
	draw_circle(Vector2(15.5, -2.0), 1.2, Color(0.55, 0.12, 0.20, 0.95))
	draw_circle(Vector2(15.5, 1.0), 1.2, Color(0.55, 0.12, 0.20, 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _desenhar_elipse(centro: Vector2, raios: Vector2, cor: Color) -> void:
	var pontos := PackedVector2Array()
	for i in range(24):
		var a := TAU * float(i) / 24.0
		pontos.append(centro + Vector2(cos(a) * raios.x, sin(a) * raios.y))
	draw_colored_polygon(pontos, cor)

func _parede(x: int, y: int, px: float, py: float, T: float) -> void:
	# Sem chao em volta? E rocha macica, nao precisa de detalhe.
	if not _toca_chao(x, y):
		draw_rect(Rect2(px, py, T, T), Color(0.015, 0.008, 0.02, 0.62))
		return

	draw_rect(Rect2(px, py, T, T), Color(0.10, 0.025, 0.10, 0.46))

	# A face virada para o jogador e a unica superficie que pega luz aqui.
	# Ela ocupa metade do tile: e o que da altura a pedra em 3/4.
	if not dungeon.solido(x, y + 1):
		var alt := T * 0.5
		draw_rect(Rect2(px, py + T - alt, T, alt), Color(0.18, 0.04, 0.12, 0.36))
		# juntas de cantaria na face
		draw_rect(Rect2(px, py + T - alt, T, 2.0), Color(0.03, 0.01, 0.03, 0.50))
		var h2 := _hash(x, y)
		draw_rect(Rect2(px + float(h2 % 3) * 12.0 + 10.0, py + T - alt + 2.0, 2.0, alt - 2.0),
				Color(0.03, 0.01, 0.03, 0.42))
		# base preta: separa a pedra do chao sem ambiguidade
		draw_rect(Rect2(px, py + T - 3.0, T, 3.0), Palette.CONTORNO)

	var h := _hash(x, y)
	if h % 5 == 0:
		draw_rect(Rect2(px + float(h % 24), py + float((h / 5) % 24), 6.0, 4.0),
				Color(0.02, 0.005, 0.02, 0.38))

func _toca_chao(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not dungeon.solido(x + dx, y + dy):
				return true
	return false

func _hash(x: int, y: int) -> int:
	var n := (x * 73856093) ^ (y * 19349663) ^ int(dungeon.semente)
	return absi(n) % 1000
