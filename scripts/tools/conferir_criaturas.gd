extends Node2D

## Folha de conferencia das criaturas: uma linha por bicho, todas as poses que o
## jogo sabe usar, com o nome da acao embaixo. E a companheira do
## conferir_poses.gd - o jeito de ver se o mapa de animacoes bate com a folha
## sem ter que caçar o momento certo no playtest.
##
## Cada tabela do SpriteCriatura.ANIMS aponta banda e faixa de figuras; um
## indice errado ali nao quebra nada, so poe o bicho fazendo a pose errada.
## Esta cena e o que torna esse erro visivel.
##
##   godot --path . res://scenes/Criaturas.tscn -- --saida=C:/algum/lugar

const COL := 96.0
const LIN := 132.0
const ORDEM := ["parado", "andar", "atacar", "investida", "dano", "morto"]
## O viewport e travado em 960x540 logicos (stretch/aspect="keep" no
## project.godot), entao nao cabe bicho nenhum alem do terceiro. A conferencia
## sai paginada: --pagina=0, 1, 2...
const POR_PAGINA := 3

var _fonte: Font
var _saida := ""
var _pagina := 0

func _ready() -> void:
	_fonte = ThemeDB.fallback_font
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--saida="):
			_saida = a.substr(8)
		elif a.begins_with("--pagina="):
			_pagina = int(a.substr(9))
	await RenderingServer.frame_post_draw
	await get_tree().create_timer(0.3).timeout
	if _saida != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(_saida + "/criaturas_%d.png" % _pagina)
		print("[criaturas] gravado ", _saida, "/criaturas_%d.png" % _pagina)
	get_tree().quit()

func _draw() -> void:
	var tela := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, tela), Color(0.10, 0.09, 0.10))

	var todos := []
	for id in SpriteCriatura.ANIMS:
		if SpriteCriatura.disponivel(String(id)):
			todos.append(String(id))

	var lin := 0
	for k in range(_pagina * POR_PAGINA, mini((_pagina + 1) * POR_PAGINA, todos.size())):
		var id: String = todos[k]
		var y := 96.0 + float(lin) * LIN
		draw_string(_fonte, Vector2(12, y - 74), String(id),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.78, 0.67, 0.31))

		var tabela: Dictionary = SpriteCriatura.ANIMS[id]
		# Cavaleiro e outra escala: mostrar os dois na mesma regua do jogo e o
		# que deixa ver se o Guerra continua sendo o dobro de um monstro comum.
		var alt := SpriteCriatura.ALTURA_CAVALEIRO if tabela.has("investida") \
				else SpriteCriatura.ALTURA_BASE
		var col := 0
		for nome in ORDEM:
			if not tabela.has(nome):
				continue
			var d: Dictionary = tabela[nome]
			var n := int(d["ate"]) - int(d["de"]) + 1
			var fps := float(d["fps"])
			# 3 quadros por pose bastam para conferir: o que se procura aqui e
			# indice errado (bicho na pose de outra acao), nao suavidade.
			for q in range(mini(n, 3)):
				var pos := Vector2(110.0 + float(col) * COL, y)
				# chao de referencia: mostra se o pe esta ancorado certo
				draw_line(pos - Vector2(40, 0), pos + Vector2(40, 0),
						Color(1, 1, 1, 0.16), 1.0)
				var t := 0.0
				var prog := 0.0
				if fps > 0.0:
					t = float(q) / fps
				elif n > 1:
					prog = (float(q) + 0.5) / float(n)
				SpriteCriatura.desenhar(self, String(id), String(nome), t, prog,
						1.0, alt, pos)
				if q == 0:
					draw_string(_fonte, pos + Vector2(-40, 18), String(nome),
							HORIZONTAL_ALIGNMENT_LEFT, 90, 11,
							Color(0.74, 0.71, 0.64))
				col += 1
		lin += 1
