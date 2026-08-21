class_name MapaVisual
extends Node2D

## Desenha a planta do Submundo uma vez so. O mapa nao muda durante a run,
## entao `_draw` roda uma vez e o Godot reaproveita a lista de comandos.

const FUNDO_SUBMUNDO := preload("res://assets/Submundo.png")
const TILE_SHEET := preload("res://assets/tilesheet_submundo.svg")
const TILE_SHEET_TILE := 48

var dungeon: Dungeon
var _rng := RandomNumberGenerator.new()

func configurar(p_dungeon: Dungeon) -> void:
	dungeon = p_dungeon
	_rng.seed = dungeon.semente
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
				_desenhar_tile(px, py, 2, 0, 0.34)
				_parede(x, y, px, py, T)
			else:
				_desenhar_tile(px, py, 0 if (x + y) % 2 == 0 else 1, 0, 0.28)
				_chao(x, y, px, py, T)

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
				Color(Palette.MANCHA.r, Palette.MANCHA.g, Palette.MANCHA.b, 0.30))

	# Sombra de contato: o chao escurece encostado na pedra. E isso, mais que
	# a cor da parede, que faz a planta do mapa aparecer em vista 3/4.
	var sombra := Color(0, 0, 0, 0.22)
	if dungeon.solido(x, y - 1):
		draw_rect(Rect2(px, py, T, 7.0), sombra)
	if dungeon.solido(x - 1, y):
		draw_rect(Rect2(px, py, 5.0, T), sombra)
	if dungeon.solido(x + 1, y):
		draw_rect(Rect2(px + T - 5.0, py, 5.0, T), sombra)

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
